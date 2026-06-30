# Deployment Guide

This document describes how to deploy UPORTAL on a Linux server and how to
verify, export, back up, and restore the runtime state.

UPORTAL is intentionally filesystem-backed. The repository contains the admin
UI, nginx/njs runtime files, shhoook endpoint definitions, bash scripts, and
templates. Production data lives outside the repository under `/data/files`.

## Target Architecture

```text
browser/admin/plugin
        |
        v
nginx public edge
        |
        +-- njs runtime reads meta/storage and serves short links/pages/files
        |
        +-- admin API proxy -> shhoook -> bash scripts -> filesystem
        |
        +-- tracking mirrors/subrequests -> shhoook -> event JSON/index files
```

Default production domain used by the current configs:

```text
https://links.example.com
```

For another domain, update nginx server names, certificates, and the base URLs
in the nginx UPORTAL config before starting production traffic.

## Runtime Paths

Typical production install paths:

```text
runtime/nginx/conf.d/*          -> /etc/nginx/conf.d/
runtime/nginx/nginx.conf        -> reference only; merge required parts manually
runtime/nginx/sites-available/* -> /etc/nginx/sites-available/
runtime/nginx/snippets/*        -> /etc/nginx/snippets/
runtime/njs/*                   -> /etc/nginx/njs/
runtime/shhoook/*.json          -> /etc/shhoook/
runtime/scripts/*               -> /usr/local/bin/
runtime/templates/*             -> /data/files/uportal/templates/
runtime/system/shhoook.service  -> /etc/systemd/system/shhoook.service
runtime/system/shhoook-wrapper  -> /usr/local/bin/shhoook-wrapper
```

Runtime data paths:

```text
/data/files/uportal/meta/<publication_id>/<token>.json
/data/files/uportal/short/<short>.json
/data/files/uportal/storage/<publication_id>/<token>/page/
/data/files/uportal/storage/<publication_id>/<token>/payload/
/data/files/uportal/templates/
/data/files/uportal/pixel/1x1.gif
/data/files/uportal/user-tokens/
/data/files/uportal/user-tokens-enabled/
/data/files/uportal/dictionaries/
/data/files/uportal/events/
/data/files/uportal/index/
/data/files/uportal/audit/
/data/files/uportal/sticky/
/data/files/inbox/<publication_id>/<token>/
```

## Prerequisites

Install Git, nginx with njs, Docker tooling, and common script dependencies:

```bash
sudo apt update
sudo apt install \
  git \
  nginx libnginx-mod-http-js \
  jq curl openssl tar gzip coreutils util-linux \
  docker.io docker-compose-plugin

sudo systemctl enable --now docker
```

UPORTAL also expects standard Unix tools used by the scripts: `bash`, `flock`,
`find`, `sed`, `tr`, `sha256sum`, `mktemp`, `chmod`, `cp`, `mv`, and `rm`.

The nginx runtime needs these capabilities:

- `ngx_http_js_module` / njs for `js_import` and `js_content`.
- `ngx_http_secure_link_module` for signed tracking and download URLs.
- `ngx_http_mirror_module` for mirrored tracking events.
- `ngx_http_auth_request_module` for admin/upload authorization.
- `ngx_http_dav_module` for `PUT /upload/...`.

Check the active nginx build:

```bash
nginx -V 2>&1 | grep -E 'http_secure_link|http_mirror|http_auth_request|http_dav'
nginx -t
```

If nginx reports unknown directives such as `js_content`, `secure_link`,
`mirror`, `auth_request`, or `dav_methods`, install an nginx package/build that
includes the missing module.

Install shhoook separately. It is not vendored in this repository:

```text
https://github.com/mopkob1/shhoook
```

Docker is used by the repository's development/self-hosted admin UI compose
setup. The nginx+njs+shhoook runtime itself is deployed as system services and
filesystem files, not as the current compose service.

## Get the Repository

Clone UPORTAL before copying runtime files:

```bash
git clone <uportal-repository-url> uportal
cd uportal
```

For local admin UI development or quick self-hosted admin access:

```bash
docker compose up --build
```

The current compose file runs the Vite admin UI with `network_mode: host`, so
the UI is normally available at:

```text
http://localhost:5173
```

## Install shhoook

shhoook must be cloned, built, and installed before UPORTAL runtime deployment.
It is an external dependency and is not bundled in this repository:

```bash
git clone https://github.com/mopkob1/shhoook.git
cd shhoook
```

Then follow the build/install instructions in the shhoook repository README.
After installation, return to the UPORTAL repository root before continuing.

The provided UPORTAL configs assume shhoook listens on:

```text
127.0.0.1:8080
```

## Fresh Deployment

For a one-shot root filesystem installer container, see
`docs/docker-installer.md`. The manual steps below remain the canonical
reference for what the installer copies and configures.

### 1. Create Runtime Directories

```bash
sudo mkdir -p \
  /etc/nginx/njs \
  /etc/shhoook \
  /data/files/uportal/{meta,short,storage,templates,pixel,user-tokens,user-tokens-enabled,dictionaries,events,sticky,index,audit} \
  /data/files/inbox
```

### 2. Copy Runtime Files

Run these commands from the repository root:

```bash
sudo cp runtime/nginx/conf.d/* /etc/nginx/conf.d/
sudo cp runtime/nginx/snippets/* /etc/nginx/snippets/
sudo cp runtime/nginx/sites-available/uportal.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/uportal.conf /etc/nginx/sites-enabled/uportal.conf

sudo cp runtime/njs/* /etc/nginx/njs/
sudo cp runtime/shhoook/*.json /etc/shhoook/
sudo cp runtime/scripts/* /usr/local/bin/
sudo cp runtime/templates/* /data/files/uportal/templates/
```

Do not blindly replace `/etc/nginx/nginx.conf` on an existing server. Merge the
UPORTAL requirements from the next section into the server's active nginx.conf.

### 3. Update nginx.conf

UPORTAL needs nginx to load the njs module and import `portal.js` inside the
`http { ... }` block.

On Debian/Ubuntu with `libnginx-mod-http-js`, nginx normally loads dynamic
modules through:

```nginx
include /etc/nginx/modules-enabled/*.conf;
```

This line usually lives at the top level of `/etc/nginx/nginx.conf`, before the
`events` and `http` blocks. Keep it enabled.

Inside the `http { ... }` block, add:

```nginx
js_import portal from /etc/nginx/njs/portal.js;
```

Also ensure the standard config includes are present inside `http { ... }`:

```nginx
include /etc/nginx/conf.d/*.conf;
include /etc/nginx/sites-enabled/*;
```

Minimal expected shape:

```nginx
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    js_import portal from /etc/nginx/njs/portal.js;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

The repository also contains `runtime/nginx/nginx.conf` as a reference file
from the curated runtime. Treat it as an example, not as a safe drop-in
replacement for every server. If it contains extra `js_import` lines for modules
that are not installed on your server, remove those imports or nginx validation
will fail.

Validate after editing:

```bash
sudo nginx -t
```

### 4. Install shhoook Service Files

```bash
sudo cp runtime/system/shhoook-wrapper /usr/local/bin/shhoook-wrapper
sudo cp runtime/system/shhoook.service /etc/systemd/system/shhoook.service

sudo chmod 755 \
  /usr/local/bin/shhoook-wrapper \
  /usr/local/bin/uportal-*.sh \
  /usr/local/bin/publish-*.sh \
  /usr/local/bin/admin-*.sh

sudo systemctl daemon-reload
```

### 5. Configure Secrets

UPORTAL nginx variables are split into two files:

```text
/etc/nginx/conf.d/00-uportal.conf         # non-secret paths, URLs, maps
/etc/nginx/conf.d/00-uportal-secrets.conf # secrets and integration tokens
```

For production, keep real values in `00-uportal-secrets.conf` and do not
overwrite that file during routine deploys unless secrets are intentionally
rotated.

Replace all placeholders before starting services:

```bash
grep -R "CHANGE_ME_" /etc/nginx /etc/shhoook /usr/local/bin
```

Required values:

```text
CHANGE_ME_UPORTAL_ADMIN_SECRET
CHANGE_ME_UPORTAL_INTERNAL_KEY
CHANGE_ME_N8N_HOST
CHANGE_ME_DOWNLOAD_SALT
CHANGE_ME_STAT_SECRET
CHANGE_ME_PAGE_SECRET
```

The same admin secret must be used by:

```text
/etc/nginx/conf.d/00-uportal-secrets.conf
/etc/shhoook/*.json
```

### 6. Configure Optional n8n Integration

n8n is optional. UPORTAL can record operational events locally through
shhoook/bash even when no n8n workflow is attached.

If you use n8n, set these values in
`/etc/nginx/conf.d/00-uportal-secrets.conf`:

```text
$uportal_webhook_base
$uportal_internal_key
```

The default event path is configured in `/etc/nginx/conf.d/00-uportal.conf`:

```text
$uportal_track_webhook = /webhook/track-event
```

If you do not use n8n, either:

- point `$uportal_webhook_base` at a local reachable no-op endpoint, or
- remove/disable the `mirror /__uportal_track_n8n...` lines and the n8n
  subrequest path from your nginx site config.

Do not leave n8n pointing at an unreachable slow host in production. Tracking
through shhoook is the required local path; n8n is the optional integration
path.

### 7. Configure Domain and TLS

Update the nginx site file for your public domain:

```text
/etc/nginx/sites-available/uportal.conf
```

Check:

- `server_name`
- certificate paths
- public base URL in `/etc/nginx/conf.d/00-uportal.conf`
- fallback URL in `/etc/nginx/conf.d/00-uportal.conf`
- CORS policy in `/etc/nginx/snippets/uportal-cors.conf`, if the admin UI is
  hosted from another origin

### 8. Add Pixel Asset

The tracking pixel file must exist:

```bash
sudo mkdir -p /data/files/uportal/pixel
# place a valid 1x1 GIF here:
# /data/files/uportal/pixel/1x1.gif
```

### 9. Start Services

```bash
sudo nginx -t
sudo systemctl enable --now shhoook
sudo systemctl reload nginx
```

If nginx is not already running:

```bash
sudo systemctl enable --now nginx
```

## User Tokens

Admin UI and plugin requests normally authenticate with:

```text
X-User-Token: <token>
```

Canonical token cards live in:

```text
/data/files/uportal/user-tokens/<token>.json
```

Each token card should contain a stable `user_id`. Scripts use `user_id` as the
actor/owner identity. Legacy cards without `user_id` resolve to the token string
itself, which preserves old installations.

Runtime authorization checks the enabled projection:

```text
/data/files/uportal/user-tokens-enabled/<token>.json
```

After copying existing tokens or upgrading an older installation, rebuild the
projection:

```bash
sudo /usr/local/bin/uportal-token-projection-rebuild.sh
```

To rotate a compromised user token without changing ownership, call the admin
token rotation endpoint with `X-Admin-Key`:

```bash
curl -i -X POST \
  -H "X-Admin-Key: <admin-secret>" \
  -H "Content-Type: application/json" \
  -d '{"token":"<old-token>","new_token":""}' \
  https://links.example.com/api/admin/tokens/rotate
```

The response contains `new_token`. The old token is marked `revoked` and removed
from the enabled projection; the new token keeps the same `user_id`.

## Bootstrap the First User

A fresh deployment has no user token, so the admin UI cannot be entered until
you create the first user token.

Create it locally on the server after scripts are installed:

```bash
PAYLOAD_B64="$(
  printf '%s' '{"user":"admin","user_id":"admin","scope":["admin"],"status":"active","tags":["bootstrap"]}' \
    | base64 -w0
)"

sudo /usr/local/bin/uportal-token-upsert.sh "" "$PAYLOAD_B64"
```

The script prints JSON containing the generated `token`. Use that value in the
admin UI as `X-User-Token`.

Confirm that both files exist:

```bash
ls -l /data/files/uportal/user-tokens/
ls -l /data/files/uportal/user-tokens-enabled/
```

Then verify API access:

```bash
curl -i \
  -H "X-User-Token: <generated-token>" \
  https://links.example.com/api/admin/dictionary
```

## Index Rebuilds After Install or Upgrade

New events and links update indexes during normal operation. Existing
installations should rebuild projections once after deployment.

Rebuild event indexes:

```bash
sudo /usr/local/bin/uportal-events-index-rebuild.sh
```

Rebuild one user's event index:

```bash
sudo /usr/local/bin/uportal-events-index-rebuild.sh <user-token>
```

Rebuild link list indexes:

```bash
sudo /usr/local/bin/uportal-links-index-rebuild.sh
```

Rebuild audit log snapshots from current meta actions:

```bash
sudo /usr/local/bin/uportal-audit-rebuild.sh
```

Audit rebuild writes a separate `rebuild-<timestamp>.jsonl` file. It cannot
recover actions for links whose meta files were already deleted before the audit
log existed.

## Verification Commands

### nginx

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo tail -n 100 /var/log/nginx/error.log
```

If the virtual host has its own logs, check them too:

```bash
sudo tail -n 100 /var/log/nginx/uportal_error.log
sudo tail -n 100 /var/log/nginx/uportal_access.log
```

### shhoook

```bash
sudo systemctl status shhoook --no-pager
curl -i -H "X-Token: <admin-secret>" http://127.0.0.1:8080/catalog
```

### Admin API Auth

```bash
curl -i \
  -H "X-User-Token: <user-token>" \
  https://links.example.com/api/admin/dictionary
```

Expected result is a JSON response from the dictionary endpoint. A disabled or
missing token should fail authorization.

### Link List

```bash
curl -i \
  -H "X-User-Token: <user-token>" \
  -H "Content-Type: application/json" \
  -d '{"page":1,"limit":25}' \
  https://links.example.com/api/admin/links/list
```

### Tracking

Direct shhoook test:

```bash
curl -i -X POST \
  -H "X-Token: <admin-secret>" \
  "http://127.0.0.1:8080/track/event?event=click&publication=<pub>&token=<token>&uid=testuid|sig&ip=127.0.0.1&ua=test"
```

Check event output:

```bash
find /data/files/uportal/events/raw -type f -name '*.json' | tail
find /data/files/uportal/events/by-link -name '<pub>_<token>*' -ls
```

### Uploads

```bash
printf 'hello\n' > /tmp/uportal-upload-test.txt

curl -i -X PUT \
  -H "X-User-Token: <user-token>" \
  --data-binary @/tmp/uportal-upload-test.txt \
  https://links.example.com/upload/<publication_id>/<token>/uportal-upload-test.txt

ls -l /data/files/inbox/<publication_id>/<token>/
```

### Page Assets and Range Support

For page assets:

```bash
curl -I https://links.example.com/assets/<publication_id>/<token>/<file>
```

For large MP4 assets, verify byte-range support:

```bash
curl -I -H "Range: bytes=0-1023" \
  https://links.example.com/assets/<publication_id>/<token>/<video>.mp4
```

Expected headers should include partial-content behavior for valid range
requests. If a specific MP4 still behaves poorly on mobile clients, repack it
with fast-start metadata:

```bash
ffmpeg -i input.mp4 -c copy -movflags +faststart output.mp4
```

### Short-Link Previews

HTML preview:

```bash
curl -i -H "Accept: text/html" https://links.example.com/s/<short>
```

Image/pixel behavior:

```bash
curl -i -H "Accept: image/gif,*/*" https://links.example.com/s/<pixel-short>
find /data/files/uportal/events/by-link -name '<publication_id>_<token>*' -ls
```

Download signing:

```bash
curl -i https://links.example.com/api/sign/<publication_id>/<token>
```

## Performance and Server Tuning

UPORTAL is optimized around nginx serving public traffic and small filesystem
indexes serving the admin UI. Most performance problems come from missing
indexes, slow optional integrations, low file limits, or putting runtime data on
slow storage.

### Keep Indexes Warm

Run projection rebuilds after deploy, restore, or migration:

```bash
sudo /usr/local/bin/uportal-token-projection-rebuild.sh
sudo /usr/local/bin/uportal-events-index-rebuild.sh
sudo /usr/local/bin/uportal-links-index-rebuild.sh
```

Without these projections, publication and statistics reads may fall back to
walking larger file trees.

### nginx Worker and File Limits

Recommended nginx-level settings:

```nginx
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
}
```

If systemd limits are lower, add an override:

```bash
sudo systemctl edit nginx
```

```ini
[Service]
LimitNOFILE=65535
```

Then reload systemd and nginx:

```bash
sudo systemctl daemon-reload
sudo nginx -t
sudo systemctl restart nginx
```

### nginx HTTP Settings

Recommended `http { ... }` settings:

```nginx
sendfile on;
tcp_nopush on;
tcp_nodelay on;
keepalive_timeout 30;
types_hash_max_size 4096;
server_tokens off;
```

Large page assets and MP4 files should stay on nginx static paths with Range
support. Avoid proxying large assets through shell scripts or application
workers.

### shhoook Service Limits

shhoook runs shell scripts for admin and tracking operations. Keep its service
limits high enough for concurrent file/index work:

```bash
sudo systemctl edit shhoook
```

```ini
[Service]
Restart=on-failure
RestartSec=1
LimitNOFILE=65535
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl restart shhoook
```

For very high tracking traffic, the shell-per-event model becomes the next
bottleneck. nginx will usually not be the limiting part; event logging and index
writes will be.

### Optional n8n Must Not Slow the Hot Path

n8n is optional. If it is unused, unreachable, or slow, do not leave nginx
tracking mirrors/subrequests pointing at it. Either disable the n8n mirror paths
in the site config or point `$uportal_webhook_base` at a fast local no-op
endpoint.

Local shhoook tracking is the required local event path. n8n is an integration
path, not the primary durability path.

### Filesystem and Storage

Use SSD-backed ext4 or xfs for:

```text
/data/files/uportal/events
/data/files/uportal/index
/data/files/uportal/meta
```

Avoid slow network filesystems for events and indexes. The runtime creates many
small JSON files, symlinks, and JSONL projection appends.

### Logs and Rotation

Configure log rotation for nginx logs and monitor runtime growth:

```text
/var/log/nginx/*.log
/data/files/uportal/audit/*.jsonl
/data/files/uportal/events/
```

The event tree can grow quickly on busy installations. If disk space or inode
usage runs out, both tracking and admin statistics will degrade or fail.

Useful checks:

```bash
df -h /data
df -i /data
du -sh /data/files/uportal/events /data/files/uportal/index /data/files/uportal/audit
```

## Backup

Back up repository state separately from runtime data.

Repository:

```bash
git status --short
git log --oneline -5
git bundle create /tmp/uportal-repo.bundle --all
```

Runtime data:

```bash
sudo tar -czf /tmp/uportal-data-$(date -u +%Y%m%dT%H%M%SZ).tar.gz \
  /data/files/uportal \
  /data/files/inbox
```

System/runtime config:

```bash
sudo tar -czf /tmp/uportal-system-$(date -u +%Y%m%dT%H%M%SZ).tar.gz \
  /etc/nginx/conf.d/00-uportal.conf \
  /etc/nginx/conf.d/00-uportal-secrets.conf \
  /etc/nginx/sites-available/uportal.conf \
  /etc/nginx/snippets/uportal-cors.conf \
  /etc/nginx/njs \
  /etc/shhoook \
  /etc/systemd/system/shhoook.service \
  /usr/local/bin/shhoook-wrapper \
  /usr/local/bin/uportal-*.sh \
  /usr/local/bin/publish-*.sh \
  /usr/local/bin/admin-*.sh
```

Do not publish backups that contain real secrets, user tokens, event data, or
publication content.

## Restore

1. Install prerequisites and shhoook.
2. Restore `/etc/nginx`, `/etc/shhoook`, `/usr/local/bin`, and systemd files.
3. Restore `/data/files/uportal` and `/data/files/inbox`.
4. Check executable permissions:

   ```bash
   sudo chmod 755 \
     /usr/local/bin/shhoook-wrapper \
     /usr/local/bin/uportal-*.sh \
     /usr/local/bin/publish-*.sh \
     /usr/local/bin/admin-*.sh
   ```

5. Rebuild projections:

   ```bash
   sudo /usr/local/bin/uportal-token-projection-rebuild.sh
   sudo /usr/local/bin/uportal-events-index-rebuild.sh
   sudo /usr/local/bin/uportal-links-index-rebuild.sh
   ```

6. Validate and reload:

   ```bash
   sudo systemctl daemon-reload
   sudo nginx -t
   sudo systemctl restart shhoook
   sudo systemctl reload nginx
   ```

7. Run the verification commands above.

## Admin UI Deployment Notes

The development compose file runs the Vite admin UI:

```bash
docker compose up --build
```

For a public service, build and host the admin UI behind your chosen frontend
deployment path or domain. The browser must be able to reach the UPORTAL admin
API and send `X-User-Token` or privileged admin headers where appropriate.

The current compose file uses `network_mode: host` for local/self-hosted
development convenience.

### Build and Publish Admin UI

The admin app is a Vite SPA. Build it with Docker, not with a host-local Node
installation. Its production build is configured for `/ui/`:

```text
admin/package.json -> npm run build -> vite build --base=/ui/
```

Build it through the repository compose service:

```bash
cd /path/to/uportal
docker compose run --rm app sh -c "npm install && npm run build"
```

Equivalent one-shot Docker command:

```bash
cd /path/to/uportal
docker run --rm \
  -v "$PWD":/app \
  -w /app/admin \
  node:22-alpine \
  sh -c "npm install && npm run build"
```

Place the built files where nginx can serve them:

```bash
cd /path/to/uportal/admin
sudo mkdir -p /data/files/uportal/build/admin
sudo rsync -a --delete dist/ /data/files/uportal/build/admin/
```

If `rsync` is not installed:

```bash
sudo rm -rf /data/files/uportal/build/admin
sudo mkdir -p /data/files/uportal/build/admin
sudo cp -a dist/. /data/files/uportal/build/admin/
```

### nginx Example for Admin UI

Recommended production setup is same-origin:

```text
https://links.example.com/ui/        -> admin SPA
https://links.example.com/api/admin/ -> runtime admin API
https://links.example.com/upload/... -> runtime uploads
```

Add this to the same nginx `server { ... }` block that serves UPORTAL:

```nginx
location = /ui {
    return 301 /ui/;
}

location /ui/ {
    alias /data/files/uportal/build/admin/;
    try_files $uri $uri/ /ui/index.html;
    add_header Cache-Control "no-store" always;
}

location /ui/assets/ {
    alias /data/files/uportal/build/admin/assets/;
    try_files $uri =404;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
}
```

The `/api/admin/` and `/upload/` locations are already provided by the UPORTAL
runtime site config. With same-origin hosting, the browser can use:

```text
Server URL: https://links.example.com
Auth header: X-User-Token
Token: <generated-token>
```

Validate and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Open:

```text
https://links.example.com/ui/
```

If the admin UI is hosted on a different domain, keep the runtime API on
`https://links.example.com` and configure `/etc/nginx/snippets/uportal-cors.conf` so the
admin origin is allowed to send `X-User-Token`, `X-Admin-Key`,
`X-Upload-Key`, and credentialed requests.

## GitHub Publication Safety Checklist

Before publishing the repository:

- Ensure real secrets are not committed.
- Keep production `00-uportal-secrets.conf` values out of public commits.
- Do not commit raw backup archives.
- Do not commit `/data/files/uportal` production data.
- Do not commit real user token files.
- Keep sample domains and placeholder values clearly marked.
- Review `runtime/data/` and any extracted production backups before pushing.

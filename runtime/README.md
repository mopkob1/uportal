# UPORTAL Runtime

Runtime package for the server-side part of UPORTAL:

- nginx site/conf snippets
- njs runtime (`portal.js`)
- shhoook endpoint configs
- bash publish/admin/tracking scripts
- HTML/CSS templates

Runtime implementation notes and planned work are tracked in `TODO.md`.

`shhoook` itself is not vendored here. It is an external dependency from:

```text
https://github.com/mopkob1/shhoook
```

## Structure

```text
runtime/
  nginx/       curated nginx site, conf.d and snippets
  njs/         nginx njs runtime files
  shhoook/     endpoint JSON configs for external shhoook
  scripts/     bash scripts normally installed to /usr/local/bin
  templates/   files normally installed to /data/files/uportal/templates
  system/      shhoook systemd/wrapper references
  data/        local backup archives; raw archives are ignored by git
```

The files were curated from a production backup and redacted before versioning.
Raw backup archives must stay local and ignored.

## Deployment Paths

Typical production paths:

```text
runtime/nginx/conf.d/*          -> /etc/nginx/conf.d/
runtime/nginx/nginx.conf        -> /etc/nginx/nginx.conf
runtime/nginx/sites-available/* -> /etc/nginx/sites-available/
runtime/nginx/snippets/*        -> /etc/nginx/snippets/
runtime/njs/*                   -> /etc/nginx/njs/
runtime/shhoook/*               -> /etc/shhoook/
runtime/scripts/*               -> /usr/local/bin/
runtime/templates/*             -> /data/files/uportal/templates/
runtime/system/shhoook.service  -> /etc/systemd/system/shhoook.service
runtime/system/shhoook-wrapper  -> /usr/local/bin/shhoook-wrapper
```

Before deployment, replace placeholder values such as:

```text
CHANGE_ME_UPORTAL_ADMIN_SECRET
CHANGE_ME_UPORTAL_INTERNAL_KEY
CHANGE_ME_N8N_HOST
CHANGE_ME_DOWNLOAD_SALT
CHANGE_ME_STAT_SECRET
CHANGE_ME_PAGE_SECRET
```

Nginx runtime variables are split between:

```text
runtime/nginx/conf.d/00-uportal.conf         # common paths, URLs and maps
runtime/nginx/conf.d/00-uportal-secrets.conf # secrets and integration tokens
```

For production, keep real values in `/etc/nginx/conf.d/00-uportal-secrets.conf`
and avoid replacing that file from public/template configs during routine
deploys unless the secrets are intentionally rotated.

## Nginx Modules

UPORTAL needs nginx with these capabilities enabled:

- `ngx_http_js_module` / njs: used by `js_import` and `js_content portal.*`.
- `ngx_http_secure_link_module`: used by signed tracking and download URLs.
- `ngx_http_mirror_module`: used to mirror page/download events to tracking.
- `ngx_http_auth_request_module`: used for admin/upload token checks.
- `ngx_http_dav_module`: used by `PUT /upload/...` and `dav_methods`.

On Debian/Ubuntu with packaged nginx, install the dynamic njs module first:

```bash
sudo apt update
sudo apt install nginx libnginx-mod-http-js
```

Then enable the module if the package did not do it automatically:

```bash
sudo ln -s /usr/share/nginx/modules-available/mod-http-js.conf \
  /etc/nginx/modules-enabled/50-mod-http-js.conf
```

The other modules are commonly compiled into Debian/Ubuntu nginx builds. Check
the active build before deployment:

```bash
nginx -V 2>&1 | grep -E 'http_secure_link|http_mirror|http_auth_request|http_dav'
nginx -t
```

If a directive such as `secure_link`, `mirror`, `auth_request`, `dav_methods`,
or `js_content` is reported as unknown, install an nginx build/package variant
that includes the corresponding module.

## Deployment Order

Recommended high-level order for a fresh server:

1. Install system packages.

   ```bash
   sudo apt update
   sudo apt install nginx libnginx-mod-http-js jq curl openssl tar gzip
   ```

   The publish scripts also expect common Unix tools such as `bash`, `flock`,
   `find`, `sed`, `tr`, `sha256sum`, `mktemp`, `chmod`, `cp`, `mv`, and `rm`.

2. Install shhoook.

   Clone/build/install it from the public repository:

   ```text
   https://github.com/mopkob1/shhoook
   ```

   The runtime configs in `runtime/shhoook/` assume shhoook listens on:

   ```text
   127.0.0.1:8080
   ```

3. Create runtime directories.

   ```bash
   sudo mkdir -p \
     /etc/nginx/njs \
     /etc/shhoook \
     /data/files/uportal/{meta,short,storage,templates,pixel,user-tokens,user-tokens-enabled,dictionaries,events,sticky,index,audit} \
     /data/files/inbox
   ```

4. Copy UPORTAL files into production paths.

   ```bash
   sudo cp runtime/nginx/nginx.conf /etc/nginx/nginx.conf
   sudo cp runtime/nginx/conf.d/* /etc/nginx/conf.d/
   sudo cp runtime/nginx/snippets/* /etc/nginx/snippets/
   sudo cp runtime/nginx/sites-available/example.com /etc/nginx/sites-available/
   sudo ln -sf /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/example.com

   sudo cp runtime/njs/* /etc/nginx/njs/
   sudo cp runtime/shhoook/*.json /etc/shhoook/
   sudo cp runtime/scripts/* /usr/local/bin/
   sudo cp runtime/templates/* /data/files/uportal/templates/
   ```

5. Install shhoook service files.

   ```bash
   sudo cp runtime/system/shhoook-wrapper /usr/local/bin/shhoook-wrapper
   sudo cp runtime/system/shhoook.service /etc/systemd/system/shhoook.service
   sudo chmod 755 /usr/local/bin/shhoook-wrapper /usr/local/bin/uportal-*.sh /usr/local/bin/publish-*.sh /usr/local/bin/admin-*.sh
   sudo systemctl daemon-reload
   ```

6. Replace deployment secrets and local endpoints.

   Search and replace placeholders before starting services:

   ```bash
   grep -R "CHANGE_ME_" /etc/nginx /etc/shhoook /usr/local/bin
   ```

   Required placeholders include:

   ```text
   CHANGE_ME_UPORTAL_ADMIN_SECRET
   CHANGE_ME_UPORTAL_INTERNAL_KEY
   CHANGE_ME_N8N_HOST
   CHANGE_ME_DOWNLOAD_SALT
   CHANGE_ME_STAT_SECRET
   CHANGE_ME_PAGE_SECRET
   ```

7. Prepare static assets.

   Ensure the pixel asset exists:

   ```bash
   sudo mkdir -p /data/files/uportal/pixel
   # place 1x1.gif at:
   # /data/files/uportal/pixel/1x1.gif
   ```

   If templates are generated from a CSS build step, make sure
   `/data/files/uportal/templates/shell.tailwind.css` exists before testing
   pages.

8. Check nginx config and start services.

   ```bash
   sudo nginx -t
   sudo systemctl enable --now shhoook
   sudo systemctl reload nginx
   ```

9. Verify shhoook and public runtime.

   ```bash
   curl -i -H "X-Token: <admin-secret>" http://127.0.0.1:8080/catalog
   curl -I https://example.com/link-fallback
   ```

10. Create or copy user tokens.

    User auth is file-based:

    ```text
    /data/files/uportal/user-tokens/<token>.json
    ```

    Admin UI and plugin use `X-User-Token`. Runtime auth checks the fast
    enabled projection:

    ```text
    /data/files/uportal/user-tokens-enabled/<token>.json
    ```

    After upgrading an existing installation, rebuild this projection once:

    ```bash
    sudo /usr/local/bin/uportal-token-projection-rebuild.sh
    ```

11. Verify admin API.

    ```bash
    curl -i \
      -H "X-User-Token: <user-token>" \
      https://example.com/api/admin/dictionary
    ```

12. Publish and test one item per type.

    Recommended smoke tests:

    - publish one `redirect`, open `/s/<short>`;
    - publish one `pixel`, request `/s/<short>` and check event output;
    - publish one `download`, test `/api/sign/...` then `/f/...`;
    - publish one `page`, check `/s/<short>` preview HTML and `/api/page-content/...`.

## Event Index Maintenance

Statistics reads user-visible activity through secondary indexes under:

```text
/data/files/uportal/events/by-user
```

New events are indexed when they are written. After upgrading an existing
installation, rebuild the index once so old raw events get a user index and a
complete metadata snapshot:

```bash
sudo /usr/local/bin/uportal-events-index-rebuild.sh
```

To rebuild only one user token:

```bash
sudo /usr/local/bin/uportal-events-index-rebuild.sh <user-token>
```

## Link Index Maintenance

Publication list read-path can use an append-only JSONL projection under:

```text
/data/files/uportal/index/links/by-user/<user-token>.jsonl
```

New publish/unpublish operations update the projection when
`uportal-links-index-upsert.sh` is installed. After upgrading an existing
installation, rebuild the projection once:

```bash
sudo /usr/local/bin/uportal-links-index-rebuild.sh
```

## Audit Log Maintenance

Link actions are stored both in each link meta file and in a global append-only
audit log:

```text
/data/files/uportal/audit/YYYY-MM.jsonl
```

New actions are appended by `uportal-actions.sh`. `unpublish` writes an audit
record before deleting the link meta, so the action history survives removed
links.

After upgrading an existing installation, rebuild the audit log once from the
actions still present in current meta files:

```bash
sudo /usr/local/bin/uportal-audit-rebuild.sh
```

The rebuild writes a separate `rebuild-<timestamp>.jsonl` file. It does not
recover history for links whose meta files were already deleted before this
audit log existed.

## Current Backup

The current server backup is stored as:

```text
runtime/data/backups/uportal_2026-05-30_23-00-44.tar.gz
```

It contains nested archives for nginx, shhoook, `/usr/local/bin` UPORTAL
scripts, `/data/files/uportal`, and shhoook systemd files. See
`../docs/runtime-backup-inventory.md` for the curated inventory.

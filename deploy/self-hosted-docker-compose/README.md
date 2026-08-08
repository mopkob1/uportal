# UPORTAL Self-Hosted Docker Compose Deployment

This deployment mode runs UPORTAL Community runtime in Docker Compose and keeps
TLS on the host nginx. The container listens on plain HTTP, usually on
`127.0.0.1:18080`, and host nginx proxies the public HTTPS virtual host to it.

All commands below assume a fresh install into `/opt/uportal`.

## Files

All files for this deployment mode are in `deploy/self-hosted-docker-compose/`.

- `docker-compose.yml` - UPORTAL runtime and Community service worker.
- `.env.example` - example compose environment.
- `docker/uportal/` - container Dockerfile, entrypoint and nginx config.
- `nginx/uportal-external-proxy.conf` - minimal host nginx example.
- `nginx/uportal-host-vhost.conf` - full host nginx example with UPORTAL runtime,
  site-backend, auth-gateway and Astro site routes.

## Install

Install Docker, Docker Compose plugin, git and host nginx first. The host nginx
must already have a valid certificate for your domain.

```bash
cd /opt
git clone https://github.com/mopkob1/uportal.git
cd /opt/uportal/deploy/self-hosted-docker-compose
cp .env.example .env
```

Edit `.env`:

```env
UPORTAL_DOMAIN=u.example.com
UPORTAL_BASE_URL=https://u.example.com
UPORTAL_SHORT_BASE_URL=https://go.example.com
UPORTAL_HTTP_PORT=18080
UPORTAL_BIND_ADDR=127.0.0.1
UPORTAL_DATA_DIR=./data/files
UPORTAL_UI_LANG=ru
```

Optional values:

```env
UPORTAL_PLUGIN_DEFAULT_BASE_URL=https://u.example.com
UPORTAL_PUBLIC_BASE_URL=https://u.example.com
UPORTAL_FALLBACK_URL=https://go.example.com/link-fallback
UPORTAL_N8N_URL=
```

Leave secret values empty for the first run unless you need deterministic
secrets:

```env
UPORTAL_ADMIN_SECRET=
UPORTAL_DOWNLOAD_SALT=
UPORTAL_STAT_SECRET=
UPORTAL_PAGE_SECRET=
UPORTAL_INTERNAL_KEY=
```

Start:

```bash
docker compose --env-file .env up -d --build
```

All runtime data is stored in `UPORTAL_DATA_DIR` on the host and mounted as
`/data/files` in the container. With the default `.env`, that is:

```text
/opt/uportal/deploy/self-hosted-docker-compose/data/files
```

Useful paths:

- `data/files/uportal/meta`
- `data/files/uportal/storage`
- `data/files/uportal/events`
- `data/files/uportal/index`
- `data/files/uportal/build/admin`
- `data/files/uportal/build/plugin/uportal-link-inserter.xpi`
- `data/files/inbox`

On first start the container prints bootstrap credentials:

```bash
docker compose --env-file .env logs uportal | grep -E 'admin token:|first user token:|plugin xpi download:'
```

The same values are saved in:

```text
data/files/uportal/config/first-run-tokens.env
```

## Update From Git

Example destructive refresh used for test hosts where `/opt/uportal` can be
replaced. This removes the repository checkout. Runtime data is preserved only
if it lives outside `/opt/uportal` or you back it up first.

```bash
#!/usr/bin/env bash
set -euo pipefail

cd /opt/uportal/deploy/self-hosted-docker-compose
docker compose --env-file .env down

cd /opt
rm -rf /opt/uportal
git clone https://github.com/mopkob1/uportal.git

cd /opt/uportal/deploy/self-hosted-docker-compose
cp /opt/uportal.self ./.env

docker compose --env-file .env up -d --build

docker compose --env-file .env logs
```

For production, prefer keeping `UPORTAL_DATA_DIR` outside the repository, for
example `/opt/uportal-data/files`, so `rm -rf /opt/uportal` cannot remove live
data.

## Host Nginx

The host nginx owns certificates. The container does not terminate TLS.

Minimal runtime-only install:

```bash
sudo cp nginx/uportal-external-proxy.conf /etc/nginx/sites-available/uportal.conf
sudo ln -sfn /etc/nginx/sites-available/uportal.conf /etc/nginx/sites-enabled/uportal.conf
sudo nginx -t
sudo systemctl reload nginx
```

Edit `server_name`, certificate paths and `proxy_pass` target before enabling
the file.

Single-domain commercial/website install:

```bash
sudo cp nginx/uportal-host-vhost.conf /etc/nginx/sites-available/u.example.com
sudo ln -sfn /etc/nginx/sites-available/u.example.com /etc/nginx/sites-enabled/u.example.com
sudo nginx -t
sudo systemctl reload nginx
```

This full example expects upstreams such as `uportal_runtime`,
`uportal_site_backend`, `uportal_auth_gateway` and `uportal_astro_site` to be
defined in `/etc/nginx/conf.d/*.conf`. Adjust addresses to your host ports.

## Tokens

Open the admin UI:

```text
https://u.example.com/ui/
```

Use the first user token from the logs or from:

```text
data/files/uportal/config/first-run-tokens.env
```

The generated Thunderbird XPI is available from:

```text
data/files/uportal/build/plugin/uportal-link-inserter.xpi
```

The first user also gets a publication with the Thunderbird plugin download
link. It is visible in the publication list for that user.

To create another user token manually:

```bash
docker compose --env-file .env exec uportal bash

PAYLOAD_B64="$(printf '%s' '{"user":"admin","user_id":"admin","scope":["admin","upload","activity","dictionary"],"status":"active","tags":["manual"]}' | base64 -w0)"
/usr/local/bin/uportal-token-upsert.sh "" "$PAYLOAD_B64"
```

## Rebuild Indexes

If restoring existing data into the volume:

```bash
docker compose --env-file .env exec uportal uportal-events-index-rebuild.sh
docker compose --env-file .env exec uportal uportal-links-index-rebuild.sh
```

## Stop And Remove

Stop containers without deleting data:

```bash
docker compose --env-file .env stop
```

Start again:

```bash
docker compose --env-file .env up -d
```

Remove containers and network without deleting data:

```bash
docker compose --env-file .env down
```

Delete all runtime data from the default host directory:

```bash
sudo rm -rf ./data/files
```

## Backup

Back up `UPORTAL_DATA_DIR` on the host, for example:

```text
/opt/uportal/deploy/self-hosted-docker-compose/data/files
```

## Troubleshooting

### BuildKit parent snapshot does not exist

If `docker compose up -d --build` fails with an error like:

```text
failed to prepare extraction snapshot ... parent snapshot ... does not exist
```

clean only Docker build cache and retry:

```bash
docker builder prune -af
docker compose --env-file .env up -d --build
```

If it still fails:

```bash
systemctl restart docker
docker compose --env-file .env build --no-cache
docker compose --env-file .env up -d
```

### Upload returns 500

Redirect, download and page publications upload files to `/data/files/inbox`
before publishing. Pixel publications do not upload files, so they can keep
working when upload is broken.

Check:

```bash
docker compose --env-file .env exec uportal ls -ld /data/files/inbox
```

Temporary fix without rebuild:

```bash
docker compose --env-file .env exec uportal \
  sh -lc 'chown -R www-data:www-data /data/files/inbox && chmod 775 /data/files/inbox'
```

# UPORTAL Self-Hosted Docker Compose Deployment

This mode keeps TLS on the host nginx. The UPORTAL container listens on plain
HTTP and the host nginx proxies one HTTPS virtual host to it.

It does not replace the existing host-install runtime files.

## Files

All files for this deployment mode are in `deploy/self-hosted-docker-compose/`.

- `../../VERSION` - canonical UPORTAL version used by the generated plugin XPI.
- `docker-compose.yml` - compose stack.
- `.env.example` - example compose environment.
- `docker/uportal/` - container Dockerfile, entrypoint and nginx config.
- `nginx/uportal-external-proxy.conf` - host nginx example.

Run the commands below from this directory:

```bash
cd deploy/self-hosted-docker-compose
```

## Configure

```bash
cp .env.example .env
```

Edit:

```env
UPORTAL_DOMAIN=links.example.com
UPORTAL_BASE_URL=https://links.example.com
UPORTAL_HTTP_PORT=18080
UPORTAL_BIND_ADDR=127.0.0.1
UPORTAL_DATA_DIR=./data/files
UPORTAL_UI_LANG=en
```

`UPORTAL_PLUGIN_DEFAULT_BASE_URL` controls the default server URL baked into the
generated XPI. If omitted, it uses `UPORTAL_BASE_URL`.

`UPORTAL_DATA_DIR` is a host directory mounted to `/data/files` in the
container. The default `./data/files` keeps runtime data next to this deployment
kit and is ignored by git.

`UPORTAL_UI_LANG` controls the default language baked into the admin UI and the
generated plugin XPI. Supported values:

- `en`
- `ru`
- `es`

Changing this value requires rebuilding the image:

```bash
docker compose --env-file .env up -d --build
```

## Build And Run

```bash
docker compose --env-file .env up -d --build
```

The container exposes HTTP on `127.0.0.1:18080` by default. All data is stored in
`UPORTAL_DATA_DIR` on the host and mounted under `/data/files` in the container.

Useful paths inside `./data/files` and inside the container:

- `/data/files/uportal/meta`
- `/data/files/uportal/storage`
- `/data/files/uportal/events`
- `/data/files/uportal/index`
- `/data/files/uportal/build/admin`
- `/data/files/uportal/build/plugin/uportal-link-inserter.xpi`
- `/data/files/inbox`

On first start the container prints bootstrap credentials to logs:

```text
admin token: ...
first user token: ...
plugin xpi download: https://links.example.com/s/...
```

The same values are saved in:

```text
./data/files/uportal/config/first-run-tokens.env
```

Use `plugin xpi download` to install the generated Thunderbird XPI for the
deployment.

The first user also gets a publication with the Thunderbird plugin download
link. It is visible in the publication list for that user.

## Host Nginx

Install the sample vhost:

```bash
sudo cp nginx/uportal-external-proxy.conf /etc/nginx/sites-available/uportal-external-proxy.conf
sudo ln -sfn /etc/nginx/sites-available/uportal-external-proxy.conf /etc/nginx/sites-enabled/uportal-external-proxy.conf
sudo nginx -t
sudo systemctl reload nginx
```

Replace `links.example.com` and `127.0.0.1:18080` in the sample when needed.

The host nginx owns certificates. The container does not terminate TLS.

## Tokens

The first user token is generated automatically on the first container start.
Use it as `X-User-Token` in:

```text
https://links.example.com/ui/
```

If you want to publish from the first user, remember that UPORTAL binds
publishing to the selected client instance. After the first failed publish
attempt from the web UI or plugin, open the user settings and switch the active
publishing client to the client you are actually using. Alternatively, create a
new user token and publish from that user.

To view the generated values later:

```bash
docker compose --env-file .env logs uportal | grep -E 'admin token:|first user token:|plugin xpi download:'

cat ./data/files/uportal/config/first-run-tokens.env
```

To create another user token manually:

```bash
docker compose --env-file .env exec uportal bash

PAYLOAD_B64="$(printf '%s' '{"user":"admin","user_id":"admin","scope":["admin","upload","activity","dictionary"],"status":"active","tags":["manual"]}' | base64 -w0)"
/usr/local/bin/uportal-token-upsert.sh "" "$PAYLOAD_B64"
```

## Rebuild Indexes

If restoring existing data into the volume:

```bash
docker compose --env-file .env exec uportal \
  uportal-events-index-rebuild.sh

docker compose --env-file .env exec uportal \
  uportal-links-index-rebuild.sh
```

## Stop And Remove

Stop the container without deleting data:

```bash
docker compose --env-file .env stop
```

Start it again:

```bash
docker compose --env-file .env up -d
```

Remove the container and network without deleting data:

```bash
docker compose --env-file .env down
```

Delete all runtime data from the default host directory:

```bash
sudo rm -rf ./data/files
```

## Backup

Back up `UPORTAL_DATA_DIR` on the host, for example `./data/files`.

## Troubleshooting

### Upload returns 500

Redirect, download and page publications upload files to `/data/files/inbox`
before publishing. Pixel publications do not upload files, so they can keep
working when upload is broken.

For an already running container, check:

```bash
docker compose --env-file .env exec uportal \
  ls -ld /data/files/inbox
```

The inbox must be writable by the nginx worker. Temporary fix without rebuild:

```bash
docker compose --env-file .env exec uportal \
  sh -lc 'chown -R www-data:www-data /data/files/inbox && chmod 775 /data/files/inbox'
```

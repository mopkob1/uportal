# Runtime Backup Inventory

Current production domain:

```text
https://example.com
```

Backup file:

```text
runtime/data/backups/uportal_2026-05-30_23-00-44.tar.gz
```

The archive contains a top-level directory:

```text
uportal_2026-05-30_23-00-44/
```

## Nested Archives

```text
files/etc_nginx.tar.gz
files/etc_shhoook.tar.gz
files/usr_local_bin_uportal.tar.gz
files/uportal_data.tar.gz
system/shhoook-wrapper
system/shhoook.service
```

The external webhook runner is not vendored in this repository. Use:

```text
https://github.com/mopkob1/shhoook
```

## Relevant Nginx Files

The nginx backup includes many unrelated virtual hosts. The UPORTAL-relevant
files are:

```text
nginx/sites-available/example.com
nginx/sites-enabled/example.com
nginx/nginx.conf
nginx/conf.d/00-uportal.conf
nginx/conf.d/00-uportal-api.conf
nginx/conf.d/00-dl-secrets.conf
nginx/conf.d/track-settings.conf
nginx/snippets/uportal-cors.conf
nginx/njs/portal.js
```

Other nginx files in the backup should be treated as server noise until proven
needed.

`nginx/nginx.conf` is relevant because it imports the njs modules with
`js_import`, including `portal` from `/etc/nginx/njs/portal.js`. The
`example.com` site file depends on these imports through `js_content portal.*`.

## Shhoook Endpoints

Relevant endpoint configs:

```text
publish-redirect.json
publish-page.json
publish-download.json
publish-pixel.json
publish-increase.json
publish-decrease.json
publish-freshness.json
unpublish.json
link-list.json
activity-list.json
dictionary-get.json
dictionary-post.json
dictionary-delete.json
tokens-list.json
tokens-upsert.json
tokens-delete.json
track-event.json
_catalog.json
```

External routes are normally prefixed by nginx with `/api/admin/`. For example:

```text
/publish/redirect      -> POST /api/admin/publish/redirect
/dictionary            -> GET/POST/DELETE /api/admin/dictionary
/tokens                -> GET/POST/DELETE /api/admin/tokens
/admin/increase-click  -> POST /api/admin/admin/increase-click
/admin/decrease-click  -> POST /api/admin/admin/decrease-click
/admin/set-freshness   -> POST /api/admin/admin/set-freshness
/admin/unpublish       -> POST /api/admin/admin/unpublish
```

## Bash Scripts

Runtime scripts from `usr_local_bin_uportal.tar.gz`:

```text
publish-redirect.sh
publish-page.sh
publish-download.sh
publish-pixel.sh
unpublish.sh
admin-increase-click.sh
admin-decrease-click.sh
admin-set-freshness.sh
uportal-actions.sh
uportal-track-event.sh
uportal-links-list.sh
uportal-activity-list.sh
uportal-dictionary-list.sh
uportal-dictionary-upsert.sh
uportal-dictionary-delete.sh
uportal-token-list.sh
uportal-token-upsert.sh
uportal-token-delete.sh
admin-token-create.sh
admin-token-revoke.sh
shhoook-catalog.sh
shhoook-wrapper
```

## Data Layout In Backup

The `uportal_data` archive confirms the production data layout:

```text
/data/files/uportal/build/
/data/files/uportal/dictionaries/
/data/files/uportal/events/
/data/files/uportal/meta/
/data/files/uportal/pixel/
/data/files/uportal/short/
/data/files/uportal/storage/
/data/files/uportal/templates/
/data/files/uportal/user-tokens/
```

The `events` tree contains runtime event data and indexes:

```text
events/raw/
events/by-uid/
events/by-pub/
events/by-event/
events/by-link/
events/.locks/
events/.seq/
```

The backup also contains real data and secrets. Do not publish extracted config
files unchanged without reviewing and redacting credentials.

# Architecture

UPORTAL is a publishing/runtime system for short links, redirects, pages,
downloads and tracking pixels.

```text
admin/plugin -> admin API -> nginx -> shhoook -> bash -> filesystem
                                 |
                                 v
                            njs runtime -> meta/storage/events
```

## Parts

- `admin/` - Vue/Vite admin UI.
- `runtime/` - nginx, njs, shhoook configs, bash scripts and templates.
- `plugin/` - editor/client integration.

## Runtime Roots

```text
/data/files/uportal/meta/<publication_id>/<token>.json
/data/files/uportal/short/<short>.json
/data/files/uportal/storage/<publication_id>/<token>/page/
/data/files/uportal/storage/<publication_id>/<token>/payload/
/data/files/uportal/templates/
/data/files/uportal/pixel/1x1.gif
/data/files/inbox/<publication_id>/<token>/
/data/files/uportal/user-tokens/<token>.json
```

The runtime reads publication contracts. Publish/admin scripts create and update
files through shhoook.

## Public Domain

```text
https://example.com
```

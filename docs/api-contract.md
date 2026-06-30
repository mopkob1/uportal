# API Contract

The admin API is exposed through nginx:

```text
POST /api/admin/...
```

Authentication is normally:

```text
X-User-Token: <token>
```

nginx verifies that `/data/files/uportal/user-tokens/<token>.json` exists, then
forwards the request to shhoook. shhoook scripts receive `user_token`, resolve
it to the stable `user_id` stored in the token payload, and use `user_id` as the
actor/owner identity.

Legacy token files without `user_id` resolve to the token string itself. This
keeps existing publications visible until the token is explicitly rotated.

## Publish Endpoints

```text
POST /api/admin/publish/redirect
POST /api/admin/publish/page
POST /api/admin/publish/download
POST /api/admin/publish/pixel
```

Publish requests must also identify the concrete client instance:

```text
X-UPortal-Client-Uid: <web-or-plugin-client-uid>
X-UPortal-Client-Type: web | plugin
```

For every user token, the token payload stores:

```json
{
  "known_clients": {
    "web": [{"uid": "web-..."}],
    "plugin": [{"uid": "plugin-..."}]
  },
  "active_clients": {
    "web": "web-...",
    "plugin": "plugin-..."
  }
}
```

The first seen client of each type is auto-selected when it is the only known
client. Later clients are still recorded in `known_clients`, but publish is
rejected unless their uid matches `active_clients.<type>`.

Successful response shape:

```json
{
  "status": "success",
  "message": [
    {
      "short_id": "AbC123xYz",
      "short_url": "https://example.com/s/AbC123xYz",
      "shortlink": "https://example.com/s/AbC123xYz",
      "html": "<a href=\"https://example.com/s/AbC123xYz\">Open</a>"
    }
  ]
}
```

Error response shape:

```json
{
  "status": "error",
  "message": [
    {
      "text": "Error text"
    }
  ]
}
```

## Link List

`POST /api/admin/links/list` returns published links visible to the current
user. Link items include `short_url` and, when `image` is present, `preview_url`:

```json
{
  "publication_id": "pub1",
  "token": "redirect-1",
  "short_id": "AbC123xYz",
  "short_url": "https://example.com/s/AbC123xYz",
  "image": "cover.png",
  "preview_url": "https://example.com/assets-public/pub1/redirect-1/cover.png"
}
```

## Upload

Files are uploaded before publishing:

```text
PUT /upload/<publication_id>/<token>/<file>
```

nginx writes them to:

```text
/data/files/inbox/<publication_id>/<token>/<file>
```

## Admin Utility Endpoints

Expected maintenance endpoints:

```text
POST /api/admin/admin/increase-click
POST /api/admin/admin/decrease-click
POST /api/admin/admin/set-clicks
POST /api/admin/admin/set-freshness
POST /api/admin/admin/set-status
POST /api/admin/admin/set-sticky
POST /api/admin/admin/set-password
POST /api/admin/admin/unpublish
```

They operate by `publication_id` and `token`.

`set-status` accepts `status: "active" | "hold"`. `hold` disables runtime
availability because the njs runtime serves only empty/`active` publications.

`set-sticky` accepts a boolean-like `sticky` value and updates the stored meta
flag. Runtime same-device enforcement is tracked separately in `runtime/TODO.md`.

`set-password` accepts `password`, `password_hint`, and `password_ttl_sec`.
Empty `password` clears the existing password fields from the publication meta.

The double `admin/admin` is intentional in the current nginx+shhoook routing:
nginx strips `/api/admin/`, then proxies the remaining path to shhoook, where
the endpoint URI starts with `/admin/...`.

## User Token Rotation

Token administration is protected by `X-Admin-Key`.

```text
POST /api/admin/tokens/rotate
```

Request body:

```json
{
  "token": "<old-token>",
  "new_token": ""
}
```

`new_token` is optional. If it is empty, the server generates a new token.

Successful response includes:

```json
{
  "status": "success",
  "message": [
    {
      "text": "token rotated",
      "old_token": "<old-token>",
      "new_token": "<new-token>",
      "user_id": "<stable-user-id>"
    }
  ]
}
```

Rotation creates a new active token with the same `user_id` and marks the old
token as `revoked`. Existing publications, dictionaries, link indexes and event
indexes stay attached to `user_id`, so they do not need to be rewritten for a
normal token compromise response.

Rotating an already `revoked` token is rejected and returns the current
`rotated_to` value when it is known. This prevents duplicate active tokens for
the same rotation source.

## User Token Self Edit

When the admin token is not available, the current authenticated user can still
read and update the safe part of their own token record:

```text
GET /api/admin/tokens/self
POST /api/admin/tokens/self
```

These endpoints are authenticated by `X-User-Token` through the normal
`/api/admin/` user route. They never accept an arbitrary token id. `POST` may
update only the visible user name and `active_clients`; status, scope, tags,
`user_id`, rotation fields and `known_clients` are preserved server-side.

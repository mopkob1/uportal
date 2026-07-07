# API Contract

This document describes the public HTTP contract exposed by the nginx UPORTAL
runtime. It intentionally describes the external client view, not the internal
shhoook script arguments.

## Base Rules

Admin and user API endpoints are exposed under:

```text
/api/admin/...
```

Use JSON request bodies unless the endpoint is explicitly a file upload.

```http
Content-Type: application/json
X-User-Token: <user-token>
X-UPortal-Client-Uid: <web-or-plugin-client-uid>
X-UPortal-Client-Type: web | plugin
```

`X-User-Token` is the normal user authentication header. nginx validates the
token file and forwards the request to shhoook with the internal admin secret.

`X-UPortal-Client-Uid` and `X-UPortal-Client-Type` are required for publish
endpoints. nginx maps these headers to internal shhoook query fields
`client_uid` and `client_type`; external clients must still send them as
headers.

Administrative token management uses:

```http
X-Admin-Key: <admin-token>
```

Response envelopes use one of these shapes:

```json
{
  "status": "success",
  "message": [
    {}
  ]
}
```

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

## Common Types

| Field | Type | Notes |
| --- | --- | --- |
| `publication_id` | string | Required for link operations. Safe id, usually `pub-...` or `mail-...`. |
| `token` | string | Required link token inside a publication. |
| `short` | string | Optional. Empty string generates a short id. Non-empty value must match `^[A-Za-z0-9]{9}$`. |
| `subj` | string | Required publication subject. |
| `mails` | array of strings | Required for publish endpoints. Public clients should send a JSON array, not the string `"[]"`. Runtime also normalizes string/CSV values for compatibility. |
| `pre` | string | Text before anchor. |
| `link` | string | Anchor text. Required for redirect, page and download. |
| `post` | string | Text after anchor. |
| `status` | string | `active` or `hold`; publish defaults to `active`. |
| `fresh_until` | string | ISO datetime string or `"-1"` for no freshness limit. Empty/null is normalized to `"-1"`. |
| `remaining_clicks` | integer or numeric string | `-1` means unlimited. Invalid or negative values normalize to `-1`. |
| `fallback_url` | string | Empty value uses configured runtime fallback URL. |
| `sticky` | boolean-like string | `1`, `true`, `yes` enable sticky mode; empty/false disable it. |
| `lang` | string | `en`, `ru` or `es`; other values normalize to `en`. |
| `image` | string | File name previously uploaded to `/upload/<publication_id>/<token>/<file>`. |
| `title` | string | Preview/title metadata. |
| `description` | string | Preview/description metadata. |
| `password` | string | Plain password on write. Runtime stores only `password_hash`. Empty clears/omits password. |
| `password_hint` | string | Optional password hint. |
| `password_ttl_sec` | integer or numeric string | Password gate TTL in seconds. Default `1800`. |

## Publish Redirect

```http
POST /api/admin/publish/redirect
```

Required headers:

```http
X-User-Token: <user-token>
X-UPortal-Client-Uid: <client-uid>
X-UPortal-Client-Type: web | plugin
```

Body:

```json
{
  "type": "redirect",
  "status": "active",
  "publication_id": "pub-mrael53y",
  "token": "redirect-5xydh3",
  "short": "",
  "subj": "Подтверждение email",
  "mails": ["@test"],
  "pre": "Для завершения подтверждения ",
  "link": "перейдите по ссылке",
  "post": ". Ссылка одноразовая.",
  "target_url": "https://example.com/confirm?t=...",
  "delay": "15",
  "template": "redirect",
  "stat_ttl_sec": "15",
  "title": "",
  "description": "",
  "image": "confirm-og.jpg",
  "fresh_until": "2026-07-07T10:43:00.000Z",
  "remaining_clicks": "1",
  "fallback_url": "",
  "password": "",
  "password_hint": "",
  "password_ttl_sec": "1800",
  "sticky": "",
  "lang": "ru"
}
```

Fields:

| Field | Required | Type | Default | Notes |
| --- | --- | --- | --- | --- |
| `type` | no | string | `redirect` | Stored as `redirect`. |
| `status` | no | string | `active` | `active` or `hold`. |
| `publication_id` | yes | string |  | Publication id. |
| `token` | yes | string |  | Link token. |
| `short` | no | string | generated | Empty generates a 9-character short id. |
| `subj` | yes | string |  | Publication subject. |
| `mails` | yes | array of strings |  | Must be a JSON array. |
| `pre` | no | string | empty | Text before anchor. |
| `link` | yes | string |  | Anchor text. |
| `post` | no | string | empty | Text after anchor. |
| `target_url` | yes | string |  | Redirect destination. |
| `delay` | no | integer/string | `0` | Delay before redirect, seconds. |
| `template` | no | string | `redirect` | Runtime template name. |
| `stat_ttl_sec` | no | integer/string | `15` | Signed tracking URL TTL. |
| `title` | no | string | empty | Preview metadata. |
| `description` | no | string | empty | Preview metadata. |
| `image` | no | string | empty | Uploaded image filename. |
| `fresh_until` | no | string | `-1` | ISO datetime or `-1`. |
| `remaining_clicks` | no | integer/string | `-1` | `-1` means unlimited. |
| `fallback_url` | no | string | runtime fallback | Empty uses configured fallback. |
| `password` | no | string | empty | Empty means no password. |
| `password_hint` | no | string | empty | Stored only when password is set. |
| `password_ttl_sec` | no | integer/string | `1800` | Password session TTL. |
| `sticky` | no | boolean-like string | empty | `1`/`true`/`yes` enable sticky. |
| `lang` | no | string | `en` | `en`, `ru`, `es`. |

Do not rely on `entry_md`, `file` or `filename` for redirects. They are ignored
by the redirect script.

Successful response:

```json
{
  "status": "success",
  "message": [
    {
      "type": "redirect",
      "status": "active",
      "publication_id": "pub-mrael53y",
      "token": "redirect-5xydh3",
      "short_id": "AbC123xYz",
      "short": "AbC123xYz",
      "short_url": "https://u.example/s/AbC123xYz",
      "shortlink": "https://u.example/s/AbC123xYz",
      "subj": "Подтверждение email",
      "mails": ["@test"],
      "pre": "Для завершения подтверждения ",
      "link": "перейдите по ссылке",
      "post": ". Ссылка одноразовая.",
      "sticky": false,
      "fresh_until": "2026-07-07T10:43:00.000Z",
      "remaining_clicks": 1,
      "fallback_url": "https://u.example/link-fallback",
      "title": "",
      "description": "",
      "image": "confirm-og.jpg",
      "target_url": "https://example.com/confirm?t=...",
      "delay": "15",
      "template": "redirect",
      "stat_ttl_sec": "15",
      "lang": "ru",
      "html": "<a href=\"https://u.example/s/AbC123xYz\">перейдите по ссылке</a>"
    }
  ]
}
```

## Publish Page

```http
POST /api/admin/publish/page
```

Required headers are the same as for redirect.

Before publishing, upload page files to:

```text
PUT /upload/<publication_id>/<token>/<file>
```

Body:

```json
{
  "type": "page",
  "status": "active",
  "publication_id": "pub-1",
  "token": "page-1",
  "short": "",
  "subj": "Publication subject",
  "mails": ["user@example.com"],
  "pre": "",
  "link": "Open page",
  "post": "",
  "entry_md": "page.md",
  "image": "cover.jpg",
  "title": "",
  "description": "",
  "page_ttl_sec": "1800",
  "fresh_until": "-1",
  "remaining_clicks": "-1",
  "fallback_url": "",
  "password": "",
  "password_hint": "",
  "password_ttl_sec": "1800",
  "sticky": "",
  "lang": "en"
}
```

Required fields: `publication_id`, `token`, `subj`, `mails`, `link`,
`entry_md`.

`entry_md` must exist in the upload inbox. The script copies all uploaded files
from the inbox into runtime page storage.

## Publish Download

```http
POST /api/admin/publish/download
```

Required headers are the same as for redirect.

Before publishing, upload the downloadable file to:

```text
PUT /upload/<publication_id>/<token>/<file>
```

Body:

```json
{
  "type": "download",
  "status": "active",
  "publication_id": "pub-1",
  "token": "download-1",
  "short": "",
  "subj": "Publication subject",
  "mails": ["user@example.com"],
  "pre": "",
  "link": "Download file",
  "post": "",
  "file": "payload.pdf",
  "filename": "Document.pdf",
  "image": "cover.jpg",
  "delay": "0",
  "template": "download",
  "download_ttl_sec": "60",
  "stat_ttl_sec": "15",
  "title": "",
  "description": "",
  "fresh_until": "-1",
  "remaining_clicks": "-1",
  "fallback_url": "",
  "password": "",
  "password_hint": "",
  "password_ttl_sec": "1800",
  "sticky": "",
  "lang": "en"
}
```

Required fields: `publication_id`, `token`, `subj`, `mails`, `link`, `file`.

`file` must be present in the upload inbox. `filename` is the browser download
name; if empty, the sanitized uploaded file name is used.

## Publish Pixel

```http
POST /api/admin/publish/pixel
```

Required headers are the same as for redirect.

Body:

```json
{
  "type": "pixel",
  "status": "active",
  "publication_id": "pub-1",
  "token": "mail-pixel-1",
  "short": "",
  "subj": "Publication subject",
  "mails": ["user@example.com"],
  "fresh_until": "-1",
  "remaining_clicks": "-1",
  "fallback_url": "",
  "sticky": "",
  "lang": "en"
}
```

Required fields: `publication_id`, `token`, `subj`, `mails`.

The short URL for a pixel returns a 1x1 image response. The `html` field in the
response contains an `<img>` tag.

## Upload

```http
PUT /upload/<publication_id>/<token>/<file>
```

Headers:

```http
X-User-Token: <user-token>
X-UPortal-Client-Uid: <client-uid>
X-UPortal-Client-Type: web | plugin
Content-Type: <file-content-type>
```

The body is raw file bytes. nginx writes the file to:

```text
/data/files/inbox/<publication_id>/<token>/<file>
```

The upload is later consumed by page, download or redirect preview-image
publish scripts.

## Link List

```http
POST /api/admin/links/list
```

Headers:

```http
X-User-Token: <user-token>
```

Body:

```json
{
  "publication_id": "",
  "type": "",
  "status": "",
  "limit": "100",
  "offset": "0",
  "query": "",
  "from": "",
  "to": "",
  "mode": ""
}
```

Fields:

| Field | Type | Notes |
| --- | --- | --- |
| `publication_id` | string | Exact publication filter. |
| `type` | string | `redirect`, `page`, `download`, `pixel` or empty. |
| `status` | string | `active`, `hold` or empty. |
| `limit` | integer/string | Page size. |
| `offset` | integer/string | Offset from the newest matched row. |
| `query` | string | Text search over indexed fields. |
| `from` | string | Inclusive ISO date lower bound. |
| `to` | string | Inclusive ISO date upper bound. |
| `mode` | string | Empty for flat links, `campaigns` for grouped publication rows. |

Flat response contains `message` as an array of link rows and `meta` with
pagination. Campaign response contains grouped rows with `links`.

Link item shape:

```json
{
  "publication_id": "pub1",
  "token": "redirect-1",
  "type": "redirect",
  "status": "active",
  "short_id": "AbC123xYz",
  "short_url": "https://u.example/s/AbC123xYz",
  "image": "cover.png",
  "preview_url": "https://u.example/assets-public/pub1/redirect-1/cover.png",
  "subj": "Publication subject",
  "mails": ["user@example.com"],
  "pre": "",
  "link": "Open",
  "post": "",
  "target_url": "https://example.com",
  "sticky": false,
  "password_protected": false,
  "fresh_until": -1,
  "remaining_clicks": -1,
  "delay": 0,
  "fallback_url": "https://u.example/link-fallback",
  "date": "2026-07-07T10:00:00Z"
}
```

## Activity List

```http
POST /api/admin/activity/list
```

Headers:

```http
X-User-Token: <user-token>
```

Body:

```json
{
  "type": "",
  "publication_id": "",
  "publication": "",
  "token": "",
  "event": "",
  "uid": "",
  "page": 1,
  "limit": 50,
  "from": "",
  "to": "",
  "sort_order": "desc"
}
```

Fields:

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | Link type filter. Supports comma-separated values internally. |
| `publication_id` | string | Publication id filter. |
| `publication` | string | Alias for `publication_id`. |
| `token` | string | Link token filter. Supports comma-separated values internally. |
| `event` | string | `open`, `click`, `page_view`, `content`, `pixel`, `download` or comma-separated list. |
| `uid` | string | Visitor uid filter. |
| `page` | integer | 1-based page. |
| `limit` | integer | Max 500. |
| `from` | string | Inclusive ISO date lower bound. |
| `to` | string | Inclusive ISO date upper bound. |
| `sort_order` | string | `asc`, `ascend`, `desc`, `descend`. |

Response:

```json
{
  "status": "success",
  "message": [
    {
      "page": 1,
      "limit": 50,
      "total": 10,
      "has_next": false,
      "items": []
    }
  ]
}
```

## Admin Link Utility Endpoints

All endpoints in this section use:

```http
X-User-Token: <user-token>
Content-Type: application/json
```

The body must include `publication_id` and `token` unless stated otherwise.

### Set Clicks

```http
POST /api/admin/admin/set-clicks
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1",
  "remaining_clicks": "10"
}
```

`remaining_clicks` must be an integer. Negative values normalize to `-1`.

### Increase / Decrease Clicks

```http
POST /api/admin/admin/increase-click
POST /api/admin/admin/decrease-click
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1",
  "amount": "1"
}
```

### Set Freshness

```http
POST /api/admin/admin/set-freshness
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1",
  "fresh_until": "2026-07-07T10:43:00.000Z"
}
```

Empty `fresh_until` means no freshness limit.

### Set Status

```http
POST /api/admin/admin/set-status
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1",
  "status": "active"
}
```

`status` accepts `active` or `hold`. `disabled` and `inactive` are normalized to
`hold`.

### Set Sticky

```http
POST /api/admin/admin/set-sticky
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1",
  "sticky": "1"
}
```

`sticky` accepts `1`, `true`, `yes`, `on`, `0`, `false`, `no`, `off` or empty.

### Set Password

```http
POST /api/admin/admin/set-password
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1",
  "password": "secret",
  "password_hint": "hint",
  "password_ttl_sec": "1800"
}
```

Empty `password` clears password protection.

### Unpublish

```http
POST /api/admin/admin/unpublish
```

```json
{
  "publication_id": "pub-1",
  "token": "redirect-1"
}
```

Deletes meta, short mapping, storage, inbox files and sticky state for the link.

The double `admin/admin` is intentional in the current nginx+shhoook routing:
nginx strips `/api/admin/`, then proxies the remaining path to shhoook, where
the endpoint URI starts with `/admin/...`.

## Dictionary

```http
GET /api/admin/dictionary
POST /api/admin/dictionary
DELETE /api/admin/dictionary
```

Headers:

```http
X-User-Token: <user-token>
```

`POST` body:

```json
{
  "id": "",
  "pre": "",
  "post": "",
  "url": "https://example.com",
  "anchor": "Open",
  "type": "redirect",
  "tags": "tag1,tag2"
}
```

Fields:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Empty creates a new item. Non-empty updates this id. |
| `pre` | string | Text before anchor. |
| `post` | string | Text after anchor. |
| `url` | string | Required for `redirect`. |
| `anchor` | string | Required. |
| `type` | string | Current backend accepts `redirect` or `pixel`; UI dictionary currently creates redirect items. |
| `tags` | string | Free-form tags string. |

`DELETE` body:

```json
{
  "id": "item-id"
}
```

## User Tokens

Token administration is protected by `X-Admin-Key`.

```http
GET /api/admin/tokens
POST /api/admin/tokens
DELETE /api/admin/tokens
POST /api/admin/tokens/rotate
```

### List Tokens

```http
GET /api/admin/tokens?page=1&limit=10&query=
```

### Create Or Update Token

```http
POST /api/admin/tokens
```

Body:

```json
{
  "token": "",
  "payload_b64": "eyJ1c2VyIjoiZGVtbyJ9"
}
```

`token` may be empty; the server then generates a token. `payload_b64` is a
base64-encoded JSON object.

Decoded payload example:

```json
{
  "user": "demo",
  "scope": ["admin", "upload", "activity", "dictionary"],
  "status": "active",
  "tags": [],
  "active_clients": {
    "web": "",
    "plugin": ""
  },
  "known_clients": {
    "web": [],
    "plugin": []
  }
}
```

`scope` and `tags` may be arrays or comma-separated strings; the server stores
arrays. `active_clients.web` and `active_clients.plugin` may be strings, CSV
strings or arrays in newer commercial/site contexts. Community runtime accepts
string and CSV-compatible values for the client gate.

### Delete Token

```http
DELETE /api/admin/tokens
```

Body:

```json
{
  "token": "<token>"
}
```

### Rotate Token

```http
POST /api/admin/tokens/rotate
```

Body:

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
indexes stay attached to `user_id`.

## User Token Self Edit

```http
GET /api/admin/tokens/self
POST /api/admin/tokens/self
```

Headers:

```http
X-User-Token: <user-token>
```

`POST` body:

```json
{
  "payload_b64": "eyJ1c2VyIjoiZGVtbyIsImFjdGl2ZV9jbGllbnRzIjp7IndlYiI6IndlYi0xIn19"
}
```

Decoded payload may update only:

```json
{
  "user": "demo",
  "active_clients": {
    "web": "web-1",
    "plugin": "plugin-1"
  }
}
```

Status, scope, tags, `user_id`, rotation fields and `known_clients` are
preserved server-side.

## Tracking Endpoint

```http
POST /api/admin/track/event
```

Normally this endpoint is called by nginx internal mirrors, not by browser UI.
It records event files and updates activity indexes. Runtime public tracking
also exists through signed `/api/track/<event>/<publication>/<token>` URLs.

## Public Runtime Endpoints

These endpoints do not use `/api/admin/` authentication:

```text
GET /s/<short-id>
GET /link-fallback
GET /o/<publication_id>/<token>.(gif|png)
GET /p/<publication_id>/<token>/
GET /api/page-content/<publication_id>/<token>
GET /assets/<publication_id>/<token>/<file>
GET /assets-public/<publication_id>/<token>/<file>
GET /f/<publication_id>/<token>/<file>?st=...&e=...
GET /api/sign/<publication_id>/<token>
GET /api/auth/<publication_id>/<token>
GET /api/track/<event>/<publication_id>/<token>?md5=...&e=...
```

`/s/<short-id>` dispatches according to the stored publication type:
redirect, page, download or pixel.

# Meta Contract

Publication meta files live at:

```text
/data/files/uportal/meta/<publication_id>/<token>.json
```

Short lookup files live at:

```text
/data/files/uportal/short/<short>.json
```

Short file format:

```json
{
  "publication_id": "demo-pub",
  "token": "demo-token"
}
```

## Common Meta Fields

```json
{
  "type": "page",
  "status": "active",
  "publication_id": "demo-pub",
  "token": "demo-token",
  "short_id": "AbC123xYz",
  "short": "https://example.com/s/AbC123xYz",
  "subj": "Subject",
  "mails": ["user@example.com"],
  "link": "Open",
  "fresh_until": -1,
  "remaining_clicks": -1,
  "fallback_url": "https://example.com/link-fallback",
  "title": "Title",
  "description": "Description",
  "image": "cover.png",
  "actions": []
}
```

## Types

- `redirect` - uses `target_url`, optional `delay`, `template`, `stat_ttl_sec`.
- `page` - uses `entry_md`, `page_ttl_sec`.
- `download` - uses `file`, `filename`, optional `delay`, `template`,
  `download_ttl_sec`, `stat_ttl_sec`.
- `pixel` - no password/preview/click decrement.

## Availability

A publication is available when:

1. `status` is empty or `active`.
2. `fresh_until` is empty, `-1`, or not expired.
3. `remaining_clicks` is empty, `-1`, or a number greater than `0`.

Meta and short JSON files must be readable by nginx/njs, normally `644`.

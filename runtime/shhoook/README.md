# Shhoook Endpoints

Endpoint configs for the external `shhoook` service:

```text
https://github.com/mopkob1/shhoook
```

The configs use the real shhoook schema:

```json
{
  "uri": "/publish/redirect",
  "method": "POST",
  "auth": "X-Token:CHANGE_ME_UPORTAL_ADMIN_SECRET",
  "ttl": "15s",
  "error": 500,
  "body": {},
  "query": {},
  "script": ["bash", "/usr/local/bin/script.sh", "{field}"]
}
```

Request fields are passed to scripts through placeholders from path, query and
body values.

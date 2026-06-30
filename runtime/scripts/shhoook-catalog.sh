#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="${CONFIG_DIR:-/etc/shhoook}"
SELF_BASENAME="_catalog.json"

python3 - <<'PY'
import os, json, glob

conf_dir = os.environ.get("CONFIG_DIR", "/etc/shhoook")
self_name = os.environ.get("CATALOG_SELF", "_catalog.json")

items = []
for path in sorted(glob.glob(os.path.join(conf_dir, "*.json"))):
    if os.path.basename(path) == self_name:
        continue
    try:
        with open(path, "r", encoding="utf-8") as f:
            ep = json.load(f)
    except Exception:
        # skip broken json
        continue

    # Optional human description field (you can add it to any endpoint config)
    about = ep.get("about") or ep.get("desc") or ep.get("description") or ""

    auth = ep.get("auth", "")
    auth_header = auth.split(":", 1)[0].strip() if ":" in auth else ""

    items.append({
#        "file": os.path.basename(path),
        "uri": ep.get("uri", ""),
        "method": ep.get("method", ""),
        "ttl": ep.get("ttl", ""),
        "error": ep.get("error", 0),
#        "auth_header": auth_header,
        "about": about,
    })

out = {
    "service": "shhoook",
    "config_dir": conf_dir,
    "count": len(items),
    "endpoints": items,
}
print(json.dumps(out, ensure_ascii=False, indent=2))
PY

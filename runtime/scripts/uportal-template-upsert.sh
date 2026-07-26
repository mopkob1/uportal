#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_SET="${1:-}"
FILES_B64="${2:-}"
ROOT="${UPORTAL_TEMPLATE_ROOT:-/data/files/uportal/templates}"

json_error() {
  jq -cn --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

[ -n "$TEMPLATE_SET" ] || json_error "template_set is required"
[ -n "$FILES_B64" ] || json_error "files_b64 is required"
printf '%s' "$TEMPLATE_SET" | grep -Eq '^[A-Za-z0-9._-]{1,64}$' \
  || json_error "template_set must match ^[A-Za-z0-9._-]{1,64}$"

FILES_JSON="$(printf '%s' "$FILES_B64" | base64 -d 2>/dev/null || true)"
[ -n "$FILES_JSON" ] || json_error "files_b64 is not valid base64"
printf '%s' "$FILES_JSON" | jq -e 'type == "object" and length > 0' >/dev/null 2>&1 \
  || json_error "decoded files_b64 must be a non-empty JSON object"

mkdir -p "$ROOT/default" "$ROOT/$TEMPLATE_SET"

tmp_json="$(mktemp)"
trap 'rm -f "$tmp_json"' EXIT
printf '%s' "$FILES_JSON" > "$tmp_json"

python3 - "$ROOT" "$TEMPLATE_SET" "$tmp_json" <<'PY'
import base64
import json
import os
import re
import sys

root, template_set, json_path = sys.argv[1:4]
with open(json_path, "r", encoding="utf-8") as fh:
    files = json.load(fh)

target_root = os.path.abspath(os.path.join(root, template_set))
os.makedirs(target_root, exist_ok=True)

written = []
safe_name_re = re.compile(r"^[A-Za-z0-9._/-]{1,200}$")
for rel, encoded in files.items():
    rel = str(rel or "").strip().replace("\\", "/")
    if not rel or rel.startswith("/") or ".." in rel.split("/") or not safe_name_re.match(rel):
        raise SystemExit(f"unsafe template file name: {rel}")
    file_path = os.path.abspath(os.path.join(target_root, rel))
    if not file_path.startswith(target_root + os.sep) and file_path != target_root:
        raise SystemExit(f"unsafe template path: {rel}")
    try:
        data = base64.b64decode(str(encoded), validate=True)
    except Exception as exc:
        raise SystemExit(f"bad base64 for {rel}: {exc}")
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    tmp = file_path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, file_path)
    os.chmod(file_path, 0o644)
    written.append({"name": rel, "size": len(data)})

print(json.dumps({
    "status": "success",
    "message": [{
        "template_set": template_set,
        "files": written,
    }],
}, ensure_ascii=False, indent=2))
PY

rm -f "$tmp_json"
trap - EXIT

#!/usr/bin/env bash
set -euo pipefail

ROOT="${UPORTAL_TEMPLATE_ROOT:-/data/files/uportal/templates}"

mkdir -p "$ROOT/default"

python3 - "$ROOT" <<'PY'
import hashlib
import json
import os
import sys

root = os.path.abspath(sys.argv[1])

def safe_rel(base, path):
    rel = os.path.relpath(path, base)
    return rel.replace(os.sep, "/")

sets = []
for name in sorted(os.listdir(root)):
    path = os.path.join(root, name)
    if not os.path.isdir(path):
        continue
    files = []
    for dirpath, _dirnames, filenames in os.walk(path):
        for filename in sorted(filenames):
            file_path = os.path.join(dirpath, filename)
            try:
                with open(file_path, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            files.append({
                "name": safe_rel(path, file_path),
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            })
    sets.append({
        "name": name,
        "default": name == "default",
        "files": files,
    })

print(json.dumps({
    "status": "success",
    "message": [{
        "template_root": root,
        "sets": sets,
    }],
}, ensure_ascii=False, indent=2))
PY

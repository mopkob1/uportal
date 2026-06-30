#!/usr/bin/env bash
set -euo pipefail

ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
META_ROOT="$ROOT/meta"
INDEX_ROOT="$ROOT/index/links/by-user"
UPSERTER="${UPORTAL_LINKS_INDEX_UPSERT:-/usr/local/bin/uportal-links-index-upsert.sh}"

mkdir -p "$INDEX_ROOT"
find "$INDEX_ROOT" -maxdepth 1 -type f -name "*.jsonl" -delete 2>/dev/null || true

SCANNED=0
INDEXED=0

while IFS= read -r meta_file; do
  [ -f "$meta_file" ] || continue
  SCANNED=$((SCANNED + 1))

  publication_id="$(jq -r '.publication_id // ""' "$meta_file" 2>/dev/null || echo "")"
  token="$(jq -r '.token // ""' "$meta_file" 2>/dev/null || echo "")"

  if [ -z "$publication_id" ] || [ -z "$token" ]; then
    continue
  fi

  if UPORTAL_ROOT="$ROOT" "$UPSERTER" upsert "$publication_id" "$token" >/dev/null; then
    INDEXED=$((INDEXED + 1))
  fi
done < <(find "$META_ROOT" -type f -name "*.json" 2>/dev/null | sort)

jq -cn \
  --arg index_root "$INDEX_ROOT" \
  --argjson scanned "$SCANNED" \
  --argjson indexed "$INDEXED" \
  '{status:"success",message:[{scanned:$scanned,indexed:$indexed,index_root:$index_root}]}'

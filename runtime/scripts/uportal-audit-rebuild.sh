#!/usr/bin/env bash
set -euo pipefail

ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
META_ROOT="$ROOT/meta"
AUDIT_DIR="$ROOT/audit"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
AUDIT_FILE="$AUDIT_DIR/rebuild-$STAMP.jsonl"

mkdir -p "$AUDIT_DIR"

SCANNED=0
WRITTEN=0

while IFS= read -r meta_file; do
  [ -f "$meta_file" ] || continue
  SCANNED=$((SCANNED + 1))

  tmp="$(mktemp)"
  if ! jq -c \
    --arg source_meta "$meta_file" '
    (.publication_id // "") as $publication_id
    | (.token // "") as $token
    | (.actions // [])
    | map(select(type == "object"))
    | .[]
    | {
        ts: (.date // ""),
        scope: "link",
        type: (.type // ""),
        actor: (.actor // ""),
        publication_id: $publication_id,
        token: $token,
        short_id: (.short_id // ""),
        rebuilt: true,
        source_meta: $source_meta
      }
      +
      (
        if ((.details // {}) | type) == "object" and ((.details // {}) | length) > 0 then
          {details: (.details // {})}
        else
          {}
        end
      )
  ' "$meta_file" > "$tmp"; then
    rm -f "$tmp"
    continue
  fi

  count="$(
    wc -l < "$tmp" | tr -d ' '
  )"
  if [ "$count" -gt 0 ]; then
    cat "$tmp" >> "$AUDIT_FILE"
  fi
  rm -f "$tmp"

  WRITTEN=$((WRITTEN + count))
done < <(find "$META_ROOT" -type f -name "*.json" 2>/dev/null | sort)

chmod 644 "$AUDIT_FILE" 2>/dev/null || true

jq -cn \
  --arg audit_file "$AUDIT_FILE" \
  --argjson scanned "$SCANNED" \
  --argjson written "$WRITTEN" \
  '{status:"success",message:[{scanned:$scanned,written:$written,audit_file:$audit_file}]}'

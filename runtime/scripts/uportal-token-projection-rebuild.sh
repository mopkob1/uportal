#!/usr/bin/env bash
set -euo pipefail

if [ -f /usr/local/bin/uportal-token-projection.sh ]; then
  source /usr/local/bin/uportal-token-projection.sh
else
  source "$(dirname "$0")/uportal-token-projection.sh"
fi

mkdir -p "$UPORTAL_TOKEN_ROOT" "$UPORTAL_TOKEN_ENABLED_ROOT"

scanned=0
enabled=0

find "$UPORTAL_TOKEN_ENABLED_ROOT" -maxdepth 1 -type l -name '*.json' -delete

while IFS= read -r file; do
  [ -f "$file" ] || continue
  token="$(basename "$file" .json)"
  scanned=$((scanned + 1))

  if uportal_token_sync_projection "$token" && [ -e "$UPORTAL_TOKEN_ENABLED_ROOT/$token.json" ]; then
    enabled=$((enabled + 1))
  fi
done < <(find "$UPORTAL_TOKEN_ROOT" -maxdepth 1 -type f -name '*.json' | sort)

jq -cn \
  --argjson scanned "$scanned" \
  --argjson enabled "$enabled" \
  '{
    status: "success",
    message: [
      {
        operation: "token_projection_rebuild",
        scanned: $scanned,
        enabled: $enabled
      }
    ]
  }'

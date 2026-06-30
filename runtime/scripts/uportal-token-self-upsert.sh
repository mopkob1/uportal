#!/usr/bin/env bash
set -euo pipefail

TOKEN="${1:-}"
PAYLOAD_B64="${2:-}"

if [ -f /usr/local/bin/uportal-token-projection.sh ]; then
  source /usr/local/bin/uportal-token-projection.sh
else
  source "$(dirname "$0")/uportal-token-projection.sh"
fi

ROOT="${UPORTAL_TOKEN_ROOT:-/data/files/uportal/user-tokens}"
FILE="$ROOT/$TOKEN.json"

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

[[ "$TOKEN" =~ ^[A-Za-z0-9._-]{16,128}$ ]] || json_error "bad token"
[ -f "$FILE" ] || json_error "token not found"
[ -n "$PAYLOAD_B64" ] || json_error "payload_b64 is required"

if jq -e '(.status // "active") == "revoked"' "$FILE" >/dev/null 2>&1; then
  json_error "revoked token cannot be edited"
fi

PAYLOAD="$(printf '%s' "$PAYLOAD_B64" | base64 -d 2>/dev/null || true)"
[ -n "$PAYLOAD" ] || json_error "bad payload_b64"
echo "$PAYLOAD" | jq empty >/dev/null 2>&1 || json_error "payload is not valid json"

TMP="$(mktemp)"
jq \
  --argjson patch "$PAYLOAD" '
  .user = ($patch.user // .user // "")
  | .active_clients = (
      if (($patch.active_clients // null) | type) == "object" then
        {
          web: ($patch.active_clients.web // ""),
          plugin: ($patch.active_clients.plugin // "")
        }
      elif ((.active_clients // null) | type) == "object" then
        {
          web: (.active_clients.web // ""),
          plugin: (.active_clients.plugin // "")
        }
      else
        {web: "", plugin: ""}
      end
    )
' "$FILE" > "$TMP"

mv "$TMP" "$FILE"
chmod 644 "$FILE"
uportal_token_sync_projection "$TOKEN"

jq -cn \
  --arg token "$TOKEN" \
  --slurpfile payload "$FILE" '
  {
    status:"success",
    message:[
      {
        text:"token saved",
        token:$token,
        payload:$payload[0]
      }
    ]
  }'

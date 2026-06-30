#!/usr/bin/env bash
set -euo pipefail

TOKEN="${1:-}"
PAYLOAD_B64="${2:-}"

if [ -f /usr/local/bin/uportal-token-projection.sh ]; then
  source /usr/local/bin/uportal-token-projection.sh
else
  source "$(dirname "$0")/uportal-token-projection.sh"
fi
if [ -f /usr/local/bin/uportal-user-identity.sh ]; then
  source /usr/local/bin/uportal-user-identity.sh
else
  source "$(dirname "$0")/uportal-user-identity.sh"
fi
ROOT="$UPORTAL_TOKEN_ROOT"
mkdir -p "$ROOT"

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

safe_token_re='^[A-Za-z0-9._-]{16,128}$'

if [ -z "$TOKEN" ]; then
  TOKEN="$(openssl rand -hex 24)"
fi


[[ "$TOKEN" =~ $safe_token_re ]] || json_error "bad token"
[ -n "$PAYLOAD_B64" ] || json_error "payload_b64 is required"

PAYLOAD="$(printf '%s' "$PAYLOAD_B64" | base64 -d 2>/dev/null || true)"
[ -n "$PAYLOAD" ] || json_error "bad payload_b64"

echo "$PAYLOAD" | jq empty >/dev/null 2>&1 || json_error "payload is not valid json"

TMP="$(mktemp)"
FILE="$ROOT/$TOKEN.json"
EXISTING_FILE="$(mktemp)"
EXISTING_USER_ID=""
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if [ -f "$FILE" ]; then
  cp "$FILE" "$EXISTING_FILE"
  if jq -e '(.status // "active") == "revoked"' "$FILE" >/dev/null 2>&1; then
    rm -f "$EXISTING_FILE" "$TMP"
    json_error "revoked token cannot be edited"
  fi
  EXISTING_USER_ID="$(jq -r '.user_id // ""' "$FILE" 2>/dev/null || echo "")"
else
  printf '{}\n' > "$EXISTING_FILE"
fi

echo "$PAYLOAD" | jq \
  --arg token "$TOKEN" \
  --slurpfile existing "$EXISTING_FILE" \
  --arg now "$NOW" \
  --arg existing_user_id "$EXISTING_USER_ID" '
  (($existing[0] // {}) + .)
  |
  .status = (.status // "active")
  | .created_at = (.created_at // $now)
  | .user_id = (
      (.user_id // "") as $user_id
      | if ($user_id | test("^[A-Za-z0-9._-]{1,128}$")) then $user_id
        elif ($existing_user_id | test("^[A-Za-z0-9._-]{1,128}$")) then $existing_user_id
        else $token
        end
    )
  | .scope = (
      if (.scope | type) == "array" then .scope
      elif (.scope | type) == "string" then (.scope | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")))
      else []
      end
    )
  | .tags = (
      if (.tags | type) == "array" then .tags
      elif (.tags | type) == "string" then (.tags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")))
      else []
      end
    )
  | .known_clients = (
      if (.known_clients | type) == "object" then .known_clients
      elif (($existing[0].known_clients // null) | type) == "object" then $existing[0].known_clients
      else {}
      end
    )
  | .active_clients = (
      if (.active_clients | type) == "object" then
        {
          web: (.active_clients.web // ""),
          plugin: (.active_clients.plugin // "")
        }
      elif (($existing[0].active_clients // null) | type) == "object" then
        {
          web: ($existing[0].active_clients.web // ""),
          plugin: ($existing[0].active_clients.plugin // "")
        }
      else
        {web: "", plugin: ""}
      end
    )
' > "$TMP"

mv "$TMP" "$FILE"
rm -f "$EXISTING_FILE"
chmod 644 "$FILE"
uportal_token_sync_projection "$TOKEN"

jq -cn \
  --arg token "$TOKEN" \
  --slurpfile payload "$FILE" \
  '{
    status:"success",
    message:[
      {
        text:"token saved",
        token:$token,
        payload:$payload[0]
      }
    ]
  }'

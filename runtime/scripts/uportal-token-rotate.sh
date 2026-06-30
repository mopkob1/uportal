#!/usr/bin/env bash
set -euo pipefail

OLD_TOKEN="${1:-}"
NEW_TOKEN="${2:-}"

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

[[ "$OLD_TOKEN" =~ $safe_token_re ]] || json_error "bad old token"

if [ -z "$NEW_TOKEN" ]; then
  NEW_TOKEN="$(openssl rand -hex 24)"
fi

[[ "$NEW_TOKEN" =~ $safe_token_re ]] || json_error "bad new token"
[ "$OLD_TOKEN" != "$NEW_TOKEN" ] || json_error "new token must differ from old token"

OLD_FILE="$ROOT/$OLD_TOKEN.json"
NEW_FILE="$ROOT/$NEW_TOKEN.json"

[ -f "$OLD_FILE" ] || json_error "old token not found"
[ ! -e "$NEW_FILE" ] || json_error "new token already exists"

OLD_STATUS="$(jq -r '.status // "active"' "$OLD_FILE" 2>/dev/null || echo "active")"
if [ "$OLD_STATUS" = "revoked" ]; then
  ROTATED_TO="$(jq -r '.rotated_to // ""' "$OLD_FILE" 2>/dev/null || echo "")"
  if [ -n "$ROTATED_TO" ]; then
    jq -cn \
      --arg msg "old token already revoked" \
      --arg rotated_to "$ROTATED_TO" \
      '{status:"error",message:[{text:$msg,rotated_to:$rotated_to}]}'
  else
    jq -cn --arg msg "old token already revoked" '{status:"error",message:[{text:$msg}]}'
  fi
  exit 0
fi

USER_ID="$(uportal_resolve_user_id "$OLD_TOKEN")"
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

TMP_NEW="$(mktemp)"
TMP_OLD="$(mktemp)"

jq \
  --arg user_id "$USER_ID" \
  --arg old_token "$OLD_TOKEN" \
  --arg now "$NOW" '
  .user_id = $user_id
  | .status = "active"
  | .rotated_from = $old_token
  | .rotated_at = $now
' "$OLD_FILE" > "$TMP_NEW"

jq \
  --arg user_id "$USER_ID" \
  --arg new_token "$NEW_TOKEN" \
  --arg now "$NOW" '
  .user_id = $user_id
  | .status = "revoked"
  | .rotated_to = $new_token
  | .revoked_at = $now
' "$OLD_FILE" > "$TMP_OLD"

mv "$TMP_NEW" "$NEW_FILE"
chmod 644 "$NEW_FILE"
mv "$TMP_OLD" "$OLD_FILE"
chmod 644 "$OLD_FILE"

uportal_token_sync_projection "$NEW_TOKEN"
uportal_token_sync_projection "$OLD_TOKEN"

jq -cn \
  --arg old_token "$OLD_TOKEN" \
  --arg new_token "$NEW_TOKEN" \
  --arg user_id "$USER_ID" \
  --slurpfile payload "$NEW_FILE" \
  '{
    status:"success",
    message:[
      {
        text:"token rotated",
        old_token:$old_token,
        new_token:$new_token,
        user_id:$user_id,
        payload:$payload[0]
      }
    ]
  }'

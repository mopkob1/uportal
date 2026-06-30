#!/usr/bin/env bash
set -euo pipefail

USER_TOKEN="${1:-}"
ID="${2:-}"

ROOT="/data/files/uportal"
DICT_ROOT="$ROOT/dictionaries"

if [ -f /usr/local/bin/uportal-user-identity.sh ]; then
  source /usr/local/bin/uportal-user-identity.sh
else
  source "$(dirname "$0")/uportal-user-identity.sh"
fi

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

safe_token_re='^[A-Za-z0-9._-]{16,128}$'
safe_id_re='^[A-Za-z0-9._-]{1,128}$'

[[ "$USER_TOKEN" =~ $safe_token_re ]] || json_error "bad or missing user token"
[[ "$ID" =~ $safe_id_re ]] || json_error "bad or missing id"

USER_ID="$(uportal_resolve_user_id "$USER_TOKEN")"
DICT_FILE="$DICT_ROOT/$USER_ID.json"
LOCK_FILE="$DICT_ROOT/$USER_ID.lock"

if [ ! -f "$DICT_FILE" ]; then
  jq -cn --arg id "$ID" '{status:"success",message:[{text:"dictionary item deleted",id:$id,deleted:false}]}'
  exit 0
fi

TMP="$(mktemp)"

BEFORE="$(jq 'length' "$DICT_FILE")"

(
  flock -x 200

  jq --arg id "$ID" '
    map(select(.id != $id))
  ' "$DICT_FILE" > "$TMP"

  mv "$TMP" "$DICT_FILE"
  chmod 600 "$DICT_FILE"
) 200>"$LOCK_FILE"

AFTER="$(jq 'length' "$DICT_FILE")"

DELETED=false
if [ "$AFTER" -lt "$BEFORE" ]; then
  DELETED=true
fi

jq -cn \
  --arg id "$ID" \
  --argjson deleted "$DELETED" \
  '{
    status:"success",
    message:[
      {
        text:"dictionary item deleted",
        id:$id,
        deleted:$deleted
      }
    ]
  }'

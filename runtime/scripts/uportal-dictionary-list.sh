#!/usr/bin/env bash
set -euo pipefail

USER_TOKEN="${1:-}"

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
[[ "$USER_TOKEN" =~ $safe_token_re ]] || json_error "bad or missing user token"

USER_ID="$(uportal_resolve_user_id "$USER_TOKEN")"
DICT_FILE="$DICT_ROOT/$USER_ID.json"

if [ ! -f "$DICT_FILE" ]; then
  jq -cn '{status:"success",message:[{items:[],total:0}]}'
  exit 0
fi

jq -c '
  if type != "array" then
    {status:"error",message:[{text:"dictionary file is corrupted"}]}
  else
    {status:"success",message:[{items:.,total:length}]}
  end
' "$DICT_FILE"

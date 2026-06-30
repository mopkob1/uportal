#!/usr/bin/env bash
set -euo pipefail

TOKEN="${1:-}"

if [ -f /usr/local/bin/uportal-token-projection.sh ]; then
  source /usr/local/bin/uportal-token-projection.sh
else
  source "$(dirname "$0")/uportal-token-projection.sh"
fi
ROOT="$UPORTAL_TOKEN_ROOT"

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

safe_token_re='^[A-Za-z0-9._-]{16,128}$'

[[ "$TOKEN" =~ $safe_token_re ]] || json_error "bad token"

FILE="$ROOT/$TOKEN.json"

if [ -f "$FILE" ]; then
  rm -f "$FILE"
fi
uportal_token_remove_projection "$TOKEN"

jq -cn \
  --arg token "$TOKEN" \
  '{
    status:"success",
    message:[
      {
        text:"token deleted",
        token:$token
      }
    ]
  }'

#!/usr/bin/env bash

set -euo pipefail

token="${1:-}"

if [ -f /usr/local/bin/uportal-token-projection.sh ]; then
  source /usr/local/bin/uportal-token-projection.sh
else
  source "$(dirname "$0")/uportal-token-projection.sh"
fi
BASE="$UPORTAL_TOKEN_ROOT"
FILE="$BASE/$token.json"

json_error() {
  jq -n --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

[ -n "$token" ] || json_error "missing required field: token"

printf '%s' "$token" | grep -Eq '^[A-Za-z0-9._-]{16,128}$' \
  || json_error "invalid token format"

[ -f "$FILE" ] || json_error "token not found"

rm -f "$FILE"
uportal_token_remove_projection "$token"

jq -n \
  --arg token "$token" '
  {
    status: "success",
    message: [
      {
        operation: "token_revoke",
        token: $token,
        revoked: true
      }
    ]
  }
'

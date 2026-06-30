#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"
password="${3:-}"
password_hint="${4:-}"
password_ttl_sec="${5:-1800}"
actor="${6:-system}"

BASE="/data/files/uportal"
META_FILE="$BASE/meta/$publication_id/$token.json"

json_error() {
  jq -n --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

require_nonempty() {
  [ -n "$2" ] || json_error "missing required field: $1"
}

require_nonempty "publication_id" "$publication_id"
require_nonempty "token" "$token"

[ -f "$META_FILE" ] || json_error "meta not found: $META_FILE"
printf '%s' "$password_ttl_sec" | grep -Eq '^[0-9]+$' || json_error "password_ttl_sec must be a non-negative integer"
load_actions "$META_FILE"

tmp="$(mktemp)"

if [ -n "$password" ]; then
  password_hash="$(printf '%s' "$password" | sha256sum | awk '{print $1}')"

  jq \
    --arg password_hash "$password_hash" \
    --arg password_hint "$password_hint" \
    --arg password_ttl_sec "$password_ttl_sec" '
    .password_hash = $password_hash
    | .password_hint = $password_hint
    | .password_ttl_sec = $password_ttl_sec
  ' "$META_FILE" > "$tmp"
else
  jq '
    del(.password_hash, .password_hint, .password_ttl_sec)
  ' "$META_FILE" > "$tmp"
fi

mv "$tmp" "$META_FILE"

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
append_action "$META_FILE" "set_password" "$actor" "$short_id"
refresh_link_index "$publication_id" "$token"

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --argjson password_set "$(if [ -n "$password" ]; then echo true; else echo false; fi)" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        operation: "set_password",
        password_set: $password_set,
        meta: $meta[0]
      }
    ]
  }
'

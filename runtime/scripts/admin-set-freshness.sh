#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"
fresh_until="${3:-}"
actor="${4:-system}"


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
load_actions "$META_FILE"

if [ -z "$fresh_until" ] || [ "$fresh_until" = "null" ]; then
  fresh_until="$(date -u -d '1 second ago' +"%Y-%m-%dT%H:%M:%SZ")"
fi

tmp="$(mktemp)"

jq --arg fresh_until "$fresh_until" '
  .fresh_until = $fresh_until
' "$META_FILE" > "$tmp"

mv "$tmp" "$META_FILE"

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
append_action "$META_FILE" "freshness" "$actor" "$short_id"
refresh_link_index "$publication_id" "$token"

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg fresh_until "$fresh_until" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        operation: "set_freshness",
        fresh_until: $fresh_until,
        meta: $meta[0]
      }
    ]
  }
'

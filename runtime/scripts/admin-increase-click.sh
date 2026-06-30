#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"
amount="${3:-1}"
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
printf '%s' "$amount" | grep -Eq '^[0-9]+$' || json_error "amount must be a non-negative integer"
load_actions "$META_FILE"

tmp="$(mktemp)"

jq --argjson amount "$amount" '
  .remaining_clicks =
    (
      if (.remaining_clicks == -1 or .remaining_clicks == "-1") then
        -1
      else
        ((.remaining_clicks | tonumber) + $amount)
      end
    )
' "$META_FILE" > "$tmp"

mv "$tmp" "$META_FILE"

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
append_action "$META_FILE" "increase" "$actor" "$short_id"
refresh_link_index "$publication_id" "$token"

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --argjson amount "$amount" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        operation: "increase_click",
        amount: $amount,
        meta: $meta[0]
      }
    ]
  }
'

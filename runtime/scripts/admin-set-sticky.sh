#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"
sticky="${3:-}"
actor="${4:-system}"

BASE="/data/files/uportal"
META_FILE="$BASE/meta/$publication_id/$token.json"
STICKY_FILE="$BASE/sticky/$publication_id/$token.json"

json_error() {
  jq -n --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

require_nonempty() {
  [ -n "$2" ] || json_error "missing required field: $1"
}

require_nonempty "publication_id" "$publication_id"
require_nonempty "token" "$token"

case "$sticky" in
  1|true|yes|on) sticky="true" ;;
  0|false|no|off|"") sticky="false" ;;
  *) json_error "sticky must be boolean" ;;
esac

[ -f "$META_FILE" ] || json_error "meta not found: $META_FILE"
load_actions "$META_FILE"

tmp="$(mktemp)"

jq --arg sticky "$sticky" '
  .sticky = ($sticky == "true")
' "$META_FILE" > "$tmp"

mv "$tmp" "$META_FILE"

if [ "$sticky" = "false" ]; then
  rm -f "$STICKY_FILE"
fi

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
append_action "$META_FILE" "set_sticky" "$actor" "$short_id"
refresh_link_index "$publication_id" "$token"

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg sticky "$sticky" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        operation: "set_sticky",
        sticky: ($sticky == "true"),
        meta: $meta[0]
      }
    ]
  }
'

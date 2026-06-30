#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"
status="${3:-active}"
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

case "$status" in
  active|hold) ;;
  disabled|inactive) status="hold" ;;
  *) json_error "status must be active or hold" ;;
esac

[ -f "$META_FILE" ] || json_error "meta not found: $META_FILE"
load_actions "$META_FILE"

tmp="$(mktemp)"

jq --arg status "$status" '
  .status = $status
' "$META_FILE" > "$tmp"

mv "$tmp" "$META_FILE"

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
append_action "$META_FILE" "set_status" "$actor" "$short_id"
refresh_link_index "$publication_id" "$token"

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg status "$status" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        operation: "set_status",
        link_status: $status,
        meta: $meta[0]
      }
    ]
  }
'

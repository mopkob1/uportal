#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"
telegram_notify="${3:-}"
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

case "$telegram_notify" in
  1|true|yes|on) telegram_notify="true" ;;
  0|false|no|off|"") telegram_notify="false" ;;
  *) json_error "telegram_notify must be boolean" ;;
esac

[ -f "$META_FILE" ] || json_error "meta not found: $META_FILE"
load_actions "$META_FILE"

tmp="$(mktemp)"

if [ "$telegram_notify" = "true" ]; then
  jq '.telegram_notify = true' "$META_FILE" > "$tmp"
else
  jq 'del(.telegram_notify)' "$META_FILE" > "$tmp"
fi

mv "$tmp" "$META_FILE"
chmod 644 "$META_FILE"

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
append_action "$META_FILE" "set_telegram_notify" "$actor" "$short_id"
refresh_link_index "$publication_id" "$token"

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg telegram_notify "$telegram_notify" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        operation: "set_telegram_notify",
        telegram_notify: ($telegram_notify == "true"),
        meta: $meta[0]
      }
    ]
  }
'

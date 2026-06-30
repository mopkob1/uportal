#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$(dirname "$0")/uportal-config.sh"
fi
if [ -f /usr/local/bin/uportal-client-gate.sh ]; then
  source /usr/local/bin/uportal-client-gate.sh
else
  source "$(dirname "$0")/uportal-client-gate.sh"
fi

type="${1:-pixel}"
status="${2:-active}"

publication_id="${3:-}"
token="${4:-}"
short="${5:-}"

subj="${6:-}"
mails="${7:-[]}"

fresh_until="${8:--1}"
remaining_clicks="${9:--1}"
if [[ "$remaining_clicks" =~ ^-?[0-9]+$ ]] && [ "$remaining_clicks" -lt 0 ]; then
  remaining_clicks="-1"
fi
fallback_url="${10:-}"

actor="${11:-system}"
sticky="${12:-}"
client_uid="${13:-}"
client_type="${14:-}"
lang="${15:-en}"

BASE="/data/files/uportal"
META_DIR="$BASE/meta/$publication_id"
SHORT_DIR="$BASE/short"

mkdir -p "$META_DIR" "$SHORT_DIR"

json_error() {
  jq -n --arg text "$1" '
    {
      status: "error",
      message: [
        { text: $text }
      ]
    }
  '
  exit 1
}

require_nonempty() {
  local name="$1"
  local value="$2"
  [ -n "$value" ] || json_error "missing required field: $name"
}

gen_short() {
  while true; do
    local v
    v="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 9)"
    [ ${#v} -eq 9 ] || continue
    [ ! -e "$SHORT_DIR/$v.json" ] || continue
    printf '%s' "$v"
    return
  done
}

write_short() {
  local short_id="$1"
  jq -n \
    --arg publication_id "$publication_id" \
    --arg token "$token" \
    '{
      publication_id: $publication_id,
      token: $token
    }' > "$SHORT_DIR/$short_id.json"
}

# ===== validation =====

require_nonempty "publication_id" "$publication_id"
require_nonempty "token" "$token"
require_nonempty "subj" "$subj"
require_nonempty "mails" "$mails"

printf '%s' "$mails" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || json_error "mails must be a JSON array"

uportal_require_publish_client "$actor" "$client_type" "$client_uid" || exit 0

case "${lang,,}" in
  ru|en|es) ;;
  *) lang="en" ;;
esac

# ===== short =====

if [ -z "$short" ]; then
  short="$(gen_short)"
fi

printf '%s' "$short" | grep -Eq '^[A-Za-z0-9]{9}$' \
  || json_error "short must match ^[A-Za-z0-9]{9}$"

write_short "$short"

META_FILE="$META_DIR/$token.json"

BASE_URL="$(uportal_public_base_url)"
[ -n "$fallback_url" ] || fallback_url="$(uportal_fallback_url)"
HTML="<img src=\"$BASE_URL/s/$short\" width=\"1\" height=\"1\" alt=\"\" />"
load_actions "$META_FILE"

# ===== meta =====

jq -n \
  --arg type "pixel" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$BASE_URL/s/$short" \
  --arg base_url "$BASE_URL" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --argjson fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg lang "$lang" '
  {
    type: $type,
    status: $status,

    publication_id: $publication_id,
    token: $token,
    short_id: $short_id,
    short: ($base_url + "/s/" + $short),
    short_url: $short_url,
    shortlink: $short_url,

    subj: $subj,
    mails: $mails,
    sticky: ($sticky == "1" or $sticky == "true" or $sticky == "yes"),

    fresh_until: $fresh_until,
    remaining_clicks: $remaining_clicks,
    fallback_url: $fallback_url,
    lang: $lang
  }
' > "$META_FILE"

append_action "$META_FILE" "pixel" "$actor" "$short"

if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
fi

# ===== response =====

jq -n \
  --arg type "pixel" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$BASE_URL/s/$short" \
  --arg base_url "$BASE_URL" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --argjson fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg lang "$lang" \
  --arg html "$HTML" '
  {
    status: "success",
    message: [
      {
        type: $type,
        status: $status,

        publication_id: $publication_id,
        token: $token,
        short_id: $short_id,
        short: ($base_url + "/s/" + $short),
        short_url: $short_url,
        shortlink: $short_url,

        subj: $subj,
        mails: $mails,
        sticky: ($sticky == "1" or $sticky == "true" or $sticky == "yes"),

        fresh_until: $fresh_until,
        remaining_clicks: $remaining_clicks,
        fallback_url: $fallback_url,
        lang: $lang,

        html: $html
      }
    ]
  }
'

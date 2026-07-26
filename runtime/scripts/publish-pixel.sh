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
if [ -z "$fresh_until" ] || [ "$fresh_until" = "null" ]; then
  fresh_until="-1"
fi
if ! [[ "$remaining_clicks" =~ ^-?[0-9]+$ ]]; then
  remaining_clicks="-1"
elif [ "$remaining_clicks" -lt 0 ]; then
  remaining_clicks="-1"
fi
fallback_url="${10:-}"

actor="${11:-system}"
sticky="${12:-}"
client_uid="${13:-}"
client_type="${14:-}"
lang="${15:-en}"
template_set="${16:-default}"

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

mails="$(uportal_normalize_json_array_arg "$mails")"

uportal_require_publish_client "$actor" "$client_type" "$client_uid" || exit 0

case "${lang,,}" in
  auto|ru|en|es) ;;
  *) lang="en" ;;
esac
printf '%s' "$template_set" | grep -Eq '^[A-Za-z0-9._-]{1,64}$' || template_set="default"

# ===== short =====

if [ -z "$short" ]; then
  short="$(gen_short)"
fi

printf '%s' "$short" | grep -Eq '^[A-Za-z0-9]{9}$' \
  || json_error "short must match ^[A-Za-z0-9]{9}$"

write_short "$short"

META_FILE="$META_DIR/$token.json"

SHORT_BASE_URL="$(uportal_short_base_url)"
[ -n "$fallback_url" ] || fallback_url="$(uportal_fallback_url)"
HTML="<img src=\"$SHORT_BASE_URL/s/$short\" width=\"1\" height=\"1\" alt=\"\" />"
load_actions "$META_FILE"
STATUS_HISTORY_JSON="$(jq -c 'if (.status_history | type) == "array" then .status_history else [] end' "$META_FILE" 2>/dev/null || printf '[]')"

# ===== meta =====

jq -n \
  --arg type "pixel" \
  --arg status "$status" \
  --argjson status_history "$STATUS_HISTORY_JSON" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$SHORT_BASE_URL/s/$short" \
  --arg base_url "$SHORT_BASE_URL" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --arg fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg lang "$lang" \
  --arg template_set "$template_set" '
  {
    type: $type,
    status: $status,
    status_history: $status_history,

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
    template_set: $template_set
  }
' > "$META_FILE"

append_status_history "$META_FILE" "$status" "user" "published"

append_action "$META_FILE" "pixel" "$actor" "$short"

if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
fi

quota_reconcile_enqueue_script="$(command -v uportal-quota-reconcile-enqueue.sh 2>/dev/null || true)"
if [ -z "$quota_reconcile_enqueue_script" ] && [ -x "$(dirname "$0")/uportal-quota-reconcile-enqueue.sh" ]; then
  quota_reconcile_enqueue_script="$(dirname "$0")/uportal-quota-reconcile-enqueue.sh"
fi
if [ -z "$quota_reconcile_enqueue_script" ] && [ -x /opt/uportal/runtime/scripts/uportal-quota-reconcile-enqueue.sh ]; then
  quota_reconcile_enqueue_script="/opt/uportal/runtime/scripts/uportal-quota-reconcile-enqueue.sh"
fi
if [ -n "$quota_reconcile_enqueue_script" ]; then
  "$quota_reconcile_enqueue_script" "$publication_id" "$token" "pixel_published" >/dev/null 2>&1 || true
fi

# ===== response =====

jq -n \
  --arg type "pixel" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$SHORT_BASE_URL/s/$short" \
  --arg base_url "$SHORT_BASE_URL" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --arg fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg lang "$lang" \
  --arg template_set "$template_set" \
  --arg html "$HTML" \
  --slurpfile meta "$META_FILE" '
  {
    status: "success",
    message: [
      {
        type: $type,
        status: $status,
        status_history: ($meta[0].status_history // []),

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
        template_set: $template_set,

        html: $html
      }
    ]
  }
'

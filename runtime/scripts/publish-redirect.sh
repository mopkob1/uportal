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

type="${1:-redirect}"
status="${2:-active}"

publication_id="${3:-}"
token="${4:-}"
short="${5:-}"

subj="${6:-}"
mails="${7:-[]}"
link="${8:-}"

target_url="${9:-}"
delay="${10:-0}"
template="${11:-redirect}"
stat_ttl_sec="${12:-15}"

title="${13:-}"
description="${14:-}"
image="${15:-}"

fresh_until="${16:--1}"
remaining_clicks="${17:--1}"
if [ -z "$fresh_until" ] || [ "$fresh_until" = "null" ]; then
  fresh_until="-1"
fi
if ! [[ "$remaining_clicks" =~ ^-?[0-9]+$ ]]; then
  remaining_clicks="-1"
elif [ "$remaining_clicks" -lt 0 ]; then
  remaining_clicks="-1"
fi
fallback_url="${18:-}"

password="${19:-}"
password_hint="${20:-}"
password_ttl_sec="${21:-1800}"

actor="${22:-system}"
pre="${23:-}"
post="${24:-}"
sticky="${25:-}"
client_uid="${26:-}"
client_type="${27:-}"
lang="${28:-en}"

# Compatibility with endpoint variants where pre/post were inserted before actor.
if [ -n "${25:-}" ] && [ -z "${26:-}" ] && [ "${25:-}" != "1" ] && [ "${25:-}" != "true" ] && [ "${25:-}" != "yes" ] && [ "${25:-}" != "0" ] && [ "${25:-}" != "false" ] && [ "${25:-}" != "no" ]; then
  pre="${22:-}"
  post="${23:-}"
  sticky="${24:-}"
  actor="${25:-system}"
fi

BASE="/data/files/uportal"
META_DIR="$BASE/meta/$publication_id"
SHORT_DIR="$BASE/short"
STORAGE_DIR="$BASE/storage/$publication_id/$token"
PAYLOAD_DIR="$STORAGE_DIR/payload"
INBOX_DIR="/data/files/inbox/$publication_id/$token"

mkdir -p "$META_DIR" "$SHORT_DIR" "$PAYLOAD_DIR"

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

safe_file_seg() {
  local s="$1"
  s="$(printf '%s' "$s" | sed 's/[^A-Za-z0-9._-]/_/g')"
  s="${s:0:200}"
  printf '%s' "${s:-file.bin}"
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

require_nonempty "publication_id" "$publication_id"
require_nonempty "token" "$token"
require_nonempty "subj" "$subj"
require_nonempty "mails" "$mails"
require_nonempty "link" "$link"
require_nonempty "target_url" "$target_url"

printf '%s' "$mails" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || json_error "mails must be a JSON array"

uportal_require_publish_client "$actor" "$client_type" "$client_uid" || exit 0

if [ -z "$short" ]; then
  short="$(gen_short)"
fi

printf '%s' "$short" | grep -Eq '^[A-Za-z0-9]{9}$' \
  || json_error "short must match ^[A-Za-z0-9]{9}$"

write_short "$short"

safe_image=""
if [ -n "$image" ]; then
  safe_image="$(safe_file_seg "$image")"
  if [ -f "$INBOX_DIR/$image" ]; then
    cp -f "$INBOX_DIR/$image" "$PAYLOAD_DIR/$safe_image"
  elif [ -f "$INBOX_DIR/$safe_image" ]; then
    cp -f "$INBOX_DIR/$safe_image" "$PAYLOAD_DIR/$safe_image"
  fi
fi

password_hash=""
if [ -n "$password" ]; then
  password_hash="$(printf '%s' "$password" | sha256sum | awk '{print $1}')"
fi

case "${lang,,}" in
  ru|en|es) ;;
  *) lang="en" ;;
esac

META_FILE="$META_DIR/$token.json"
BASE_URL="$(uportal_public_base_url)"
[ -n "$fallback_url" ] || fallback_url="$(uportal_fallback_url)"
HTML="<a href=\"$BASE_URL/s/$short\">$link</a>"
load_actions "$META_FILE"

jq -n \
  --arg type "redirect" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$BASE_URL/s/$short" \
  --arg pre "$pre" \
  --arg post "$post" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --arg link "$link" \
  --arg fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg title "$title" \
  --arg description "$description" \
  --arg image "$safe_image" \
  --arg target_url "$target_url" \
  --arg delay "$delay" \
  --arg template "$template" \
  --arg stat_ttl_sec "$stat_ttl_sec" \
  --arg password_hash "$password_hash" \
  --arg password_hint "$password_hint" \
  --arg password_ttl_sec "$password_ttl_sec" \
  --arg lang "$lang" '
  {
    type: $type,
    status: $status,

    publication_id: $publication_id,
    token: $token,
    short_id: $short_id,
    short: $short,

    subj: $subj,
    mails: $mails,
    pre: $pre,
    link: $link,
    post: $post,
    sticky: ($sticky == "1" or $sticky == "true" or $sticky == "yes"),

    fresh_until: $fresh_until,
    remaining_clicks: $remaining_clicks,
    fallback_url: $fallback_url,

    title: $title,
    description: $description,
    image: $image,

    target_url: $target_url,
    delay: $delay,
    template: $template,
    stat_ttl_sec: $stat_ttl_sec,
    lang: $lang
  }
  +
  (
    if $password_hash != "" then
      {
        password_hash: $password_hash,
        password_hint: $password_hint,
        password_ttl_sec: $password_ttl_sec
      }
    else
      {}
    end
  )
' > "$META_FILE"

append_action \
  "$META_FILE" \
  "redirect" \
  "$actor" \
  "$short" \
  "pre=$pre" \
  "post=$post" \
  "link=$link" \
  "target_url=$target_url"

if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
fi

jq -n \
  --arg type "redirect" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$BASE_URL/s/$short" \
  --arg pre "$pre" \
  --arg post "$post" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --arg link "$link" \
  --arg fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg title "$title" \
  --arg description "$description" \
  --arg image "$safe_image" \
  --arg target_url "$target_url" \
  --arg delay "$delay" \
  --arg template "$template" \
  --arg stat_ttl_sec "$stat_ttl_sec" \
  --arg password_hash "$password_hash" \
  --arg password_hint "$password_hint" \
  --arg password_ttl_sec "$password_ttl_sec" \
  --arg lang "$lang" \
  --arg html "$HTML" '
  {
    status: "success",
    message: [
      (
        {
          type: $type,
          status: $status,

          publication_id: $publication_id,
          token: $token,
          short_id: $short_id,
          short: $short,
          short_url: $short_url,
          shortlink: $short_url,

          subj: $subj,
          mails: $mails,
          pre: $pre,
          link: $link,
          post: $post,
          sticky: ($sticky == "1" or $sticky == "true" or $sticky == "yes"),

          fresh_until: $fresh_until,
          remaining_clicks: $remaining_clicks,
          fallback_url: $fallback_url,

          title: $title,
          description: $description,
          image: $image,

          target_url: $target_url,
          delay: $delay,
          template: $template,
          stat_ttl_sec: $stat_ttl_sec,
          lang: $lang,

          html: $html
        }
        +
        (
          if $password_hash != "" then
            {
              password_hash: $password_hash,
              password_hint: $password_hint,
              password_ttl_sec: $password_ttl_sec
            }
          else
            {}
          end
        )
      )
    ]
  }
'

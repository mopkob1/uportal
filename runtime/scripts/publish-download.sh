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

type="${1:-download}"
status="${2:-active}"

publication_id="${3:-}"
token="${4:-}"
short="${5:-}"

subj="${6:-}"
mails="${7:-[]}"
link="${8:-}"

file="${9:-}"
filename="${10:-}"
image="${11:-}"

delay="${12:-0}"
template="${13:-download}"
download_ttl_sec="${14:-60}"
stat_ttl_sec="${15:-15}"

title="${16:-}"
description="${17:-}"

fresh_until="${18:--1}"
remaining_clicks="${19:--1}"
if [ -z "$fresh_until" ] || [ "$fresh_until" = "null" ]; then
  fresh_until="-1"
fi
if ! [[ "$remaining_clicks" =~ ^-?[0-9]+$ ]]; then
  remaining_clicks="-1"
elif [ "$remaining_clicks" -lt 0 ]; then
  remaining_clicks="-1"
fi
fallback_url="${20:-}"

password="${21:-}"
password_hint="${22:-}"
password_ttl_sec="${23:-1800}"
actor="${24:-system}"
pre="${25:-}"
post="${26:-}"
sticky="${27:-}"
client_uid="${28:-}"
client_type="${29:-}"
lang="${30:-en}"

BASE="/data/files/uportal"
INBOX_BASE="/data/files/inbox"

META_DIR="$BASE/meta/$publication_id"
SHORT_DIR="$BASE/short"
PAYLOAD_DIR="$BASE/storage/$publication_id/$token/payload"
INBOX_DIR="$INBOX_BASE/$publication_id/$token"

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

cleanup_inbox_after_publish() {
  case "$INBOX_DIR" in
    /data/files/inbox/"$publication_id"/"$token")
      rm -rf -- "$INBOX_DIR"
      ;;
  esac
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
require_nonempty "file" "$file"

mails="$(uportal_normalize_json_array_arg "$mails")"

uportal_require_publish_client "$actor" "$client_type" "$client_uid" || exit 0

if [ -z "$short" ]; then
  short="$(gen_short)"
fi

printf '%s' "$short" | grep -Eq '^[A-Za-z0-9]{9}$' \
  || json_error "short must match ^[A-Za-z0-9]{9}$"

write_short "$short"

password_hash=""
if [ -n "$password" ]; then
  password_hash="$(printf '%s' "$password" | sha256sum | awk '{print $1}')"
fi

case "${lang,,}" in
  auto|ru|en|es) ;;
  *) lang="en" ;;
esac

src_file="$INBOX_DIR/$file"
[ -f "$src_file" ] || json_error "source file not found in inbox: $src_file"

safe_file="$(safe_file_seg "$file")"
cp -f "$src_file" "$PAYLOAD_DIR/$safe_file"

safe_image=""
if [ -n "$image" ]; then
  safe_image="$(safe_file_seg "$image")"
  if [ -f "$INBOX_DIR/$image" ]; then
    cp -f "$INBOX_DIR/$image" "$PAYLOAD_DIR/$safe_image"
  fi
fi

if [ -z "$filename" ]; then
  filename="$safe_file"
fi

META_FILE="$META_DIR/$token.json"
BASE_URL="$(uportal_public_base_url)"
[ -n "$fallback_url" ] || fallback_url="$(uportal_fallback_url)"
HTML="<a href=\"$BASE_URL/s/$short\">$link</a>"
load_actions "$META_FILE"


jq -n \
  --arg type "download" \
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
  --arg file "$safe_file" \
  --arg filename "$filename" \
  --arg delay "$delay" \
  --arg template "$template" \
  --arg download_ttl_sec "$download_ttl_sec" \
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

    file: $file,
    filename: $filename,
    delay: $delay,
    template: $template,
    download_ttl_sec: $download_ttl_sec,
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

append_action "$META_FILE" "download" "$actor" "$short"

if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
fi

cleanup_inbox_after_publish

quota_reconcile_enqueue_script="$(command -v uportal-quota-reconcile-enqueue.sh 2>/dev/null || true)"
if [ -z "$quota_reconcile_enqueue_script" ] && [ -x "$(dirname "$0")/uportal-quota-reconcile-enqueue.sh" ]; then
  quota_reconcile_enqueue_script="$(dirname "$0")/uportal-quota-reconcile-enqueue.sh"
fi
if [ -z "$quota_reconcile_enqueue_script" ] && [ -x /opt/uportal/runtime/scripts/uportal-quota-reconcile-enqueue.sh ]; then
  quota_reconcile_enqueue_script="/opt/uportal/runtime/scripts/uportal-quota-reconcile-enqueue.sh"
fi
if [ -n "$quota_reconcile_enqueue_script" ]; then
  "$quota_reconcile_enqueue_script" "$publication_id" "$token" "download_published" >/dev/null 2>&1 || true
fi

jq -n \
  --arg type "download" \
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
  --arg file "$safe_file" \
  --arg filename "$filename" \
  --arg delay "$delay" \
  --arg template "$template" \
  --arg download_ttl_sec "$download_ttl_sec" \
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

          file: $file,
          filename: $filename,
          delay: $delay,
          template: $template,
          download_ttl_sec: $download_ttl_sec,
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

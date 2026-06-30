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

type="${1:-page}"
status="${2:-active}"

publication_id="${3:-}"
token="${4:-}"
short="${5:-}"

subj="${6:-}"
mails="${7:-[]}"
link="${8:-}"

entry_md="${9:-}"
image="${10:-}"

title="${11:-}"
description="${12:-}"
page_ttl_sec="${13:-1800}"

fresh_until="${14:--1}"
remaining_clicks="${15:--1}"
if [[ "$remaining_clicks" =~ ^-?[0-9]+$ ]] && [ "$remaining_clicks" -lt 0 ]; then
  remaining_clicks="-1"
fi
fallback_url="${16:-}"

password="${17:-}"
password_hint="${18:-}"
password_ttl_sec="${19:-1800}"
actor="${20:-system}"
pre="${21:-}"
post="${22:-}"
sticky="${23:-}"
client_uid="${24:-}"
client_type="${25:-}"
lang="${26:-en}"


BASE="/data/files/uportal"
INBOX_BASE="/data/files/inbox"

META_DIR="$BASE/meta/$publication_id"
SHORT_DIR="$BASE/short"
PAGE_DIR="$BASE/storage/$publication_id/$token/page"
PAYLOAD_DIR="$BASE/storage/$publication_id/$token/payload"
INBOX_DIR="$INBOX_BASE/$publication_id/$token"

mkdir -p "$META_DIR" "$SHORT_DIR" "$PAGE_DIR" "$PAYLOAD_DIR"

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
require_nonempty "entry_md" "$entry_md"

printf '%s' "$mails" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || json_error "mails must be a JSON array"

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
  ru|en|es) ;;
  *) lang="en" ;;
esac

safe_entry_md="$(safe_file_seg "$entry_md")"
[ -d "$INBOX_DIR" ] || json_error "inbox not found: $INBOX_DIR"
[ -f "$INBOX_DIR/$entry_md" ] || [ -f "$INBOX_DIR/$safe_entry_md" ] || json_error "entry_md not found in inbox"

rm -rf "$PAGE_DIR"
mkdir -p "$PAGE_DIR"
mkdir -p "$PAYLOAD_DIR"

cp -a "$INBOX_DIR"/. "$PAGE_DIR"/

if [ -f "$PAGE_DIR/$entry_md" ] && [ "$entry_md" != "$safe_entry_md" ]; then
  mv -f "$PAGE_DIR/$entry_md" "$PAGE_DIR/$safe_entry_md"
fi

safe_image=""
if [ -n "$image" ]; then
  safe_image="$(safe_file_seg "$image")"

  if [ -f "$PAGE_DIR/$image" ] && [ "$image" != "$safe_image" ]; then
    mv -f "$PAGE_DIR/$image" "$PAGE_DIR/$safe_image"
  fi

  if [ -f "$PAGE_DIR/$safe_image" ]; then
    cp -f "$PAGE_DIR/$safe_image" "$PAYLOAD_DIR/$safe_image"
  elif [ -f "$INBOX_DIR/$image" ]; then
    cp -f "$INBOX_DIR/$image" "$PAYLOAD_DIR/$safe_image"
  elif [ -f "$INBOX_DIR/$safe_image" ]; then
    cp -f "$INBOX_DIR/$safe_image" "$PAYLOAD_DIR/$safe_image"
  fi
fi

[ -f "$PAGE_DIR/$safe_entry_md" ] || json_error "normalized entry_md not found: $safe_entry_md"

if command -v pandoc >/dev/null 2>&1; then
  pandoc \
    "$PAGE_DIR/$safe_entry_md" \
    -f markdown \
    -t html5 \
    --wrap=none \
    -o "$PAGE_DIR/content.html" \
    || json_error "pandoc conversion failed"
else
  docker run --rm \
    -v "$PAGE_DIR:/data" \
    pandoc/core \
    "/data/$safe_entry_md" \
    -f markdown \
    -t html5 \
    --wrap=none \
    -o "/data/content.html" \
    || json_error "pandoc conversion failed"
fi

[ -f "$PAGE_DIR/content.html" ] || json_error "content.html was not created"

META_FILE="$META_DIR/$token.json"
BASE_URL="$(uportal_public_base_url)"
[ -n "$fallback_url" ] || fallback_url="$(uportal_fallback_url)"
HTML="<a href=\"$BASE_URL/s/$short\">$link</a>"

load_actions "$META_FILE"

jq -n \
  --arg type "page" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg pre "$pre" \
  --arg post "$post" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --arg link "$link" \
  --argjson fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg title "$title" \
  --arg description "$description" \
  --arg image "$safe_image" \
  --arg entry_md "$safe_entry_md" \
  --arg page_ttl_sec "$page_ttl_sec" \
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
    lang: $lang,

    entry_md: $entry_md,
    page_ttl_sec: $page_ttl_sec
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

append_action "$META_FILE" "page" "$actor" "$short"

if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
fi

jq -n \
  --arg type "page" \
  --arg status "$status" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short" \
  --arg short "$short" \
  --arg short_url "$BASE_URL/s/$short" \
  --arg base_url "$BASE_URL" \
  --arg pre "$pre" \
  --arg post "$post" \
  --arg sticky "$sticky" \
  --arg subj "$subj" \
  --argjson mails "$mails" \
  --arg link "$link" \
  --argjson fresh_until "$fresh_until" \
  --argjson remaining_clicks "$remaining_clicks" \
  --arg fallback_url "$fallback_url" \
  --arg title "$title" \
  --arg description "$description" \
  --arg image "$safe_image" \
  --arg entry_md "$safe_entry_md" \
  --arg page_ttl_sec "$page_ttl_sec" \
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
          short: ($base_url + "/s/" + $short),
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
          lang: $lang,

          entry_md: $entry_md,
          page_ttl_sec: $page_ttl_sec,

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

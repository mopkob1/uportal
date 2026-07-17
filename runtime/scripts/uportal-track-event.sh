#!/usr/bin/env bash
set -euo pipefail

EVENT="${1:-}"
PUB="${2:-}"
TOKEN="${3:-}"
ORIGINAL_URI="${4:-}"
IP="${5:-}"
XFF="${6:-}"
PROTO="${7:-}"
HOST="${8:-}"
UA="${9:-}"
REFERER="${10:-}"
ACCEPT_LANGUAGE="${11:-}"
RAW_UID="${12:-}"
PAGE_COOKIE="${13:-}"
PW_COOKIE="${14:-}"
UA_B64="${15:-}"
REFERER_B64="${16:-}"
ACCEPT_LANGUAGE_B64="${17:-}"

UPORTAL_ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
ROOT="$UPORTAL_ROOT/events"
RAW_DIR="$ROOT/raw"
META_ROOT="$UPORTAL_ROOT/meta"
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$(dirname "$0")/uportal-config.sh"
fi
PUBLIC_BASE_URL="$(uportal_public_base_url)"

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

decode_b64url_arg() {
  local value="${1:-}"
  local len
  [ -n "$value" ] || return 0
  value="${value//-/+}"
  value="${value//_//}"
  len=$(( ${#value} % 4 ))
  if [ "$len" -eq 2 ]; then
    value="${value}=="
  elif [ "$len" -eq 3 ]; then
    value="${value}="
  elif [ "$len" -ne 0 ]; then
    return 0
  fi
  printf '%s' "$value" | base64 -d 2>/dev/null || true
}

if [ -n "$UA_B64" ]; then
  UA="$(decode_b64url_arg "$UA_B64")"
fi
if [ -n "$REFERER_B64" ]; then
  REFERER="$(decode_b64url_arg "$REFERER_B64")"
fi
if [ -n "$ACCEPT_LANGUAGE_B64" ]; then
  ACCEPT_LANGUAGE="$(decode_b64url_arg "$ACCEPT_LANGUAGE_B64")"
fi

UP_UID="$(printf '%s' "$RAW_UID" | cut -d'|' -f1)"
UP_UID="$(printf '%s' "$UP_UID" | sed 's/[^A-Za-z0-9._-]/_/g')"
[ -n "$UP_UID" ] || UP_UID="nouid"

normalize_device_text() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

normalize_ip_prefix() {
  local ip="$1"

  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s' "$ip" | awk -F. '{print $1 "." $2 "." $3 ".0/24"}'
    return
  fi

  if [[ "$ip" == *:* ]]; then
    printf '%s' "$ip" | awk -F: '{
      out = ""
      for (i = 1; i <= 4 && i <= NF; i++) {
        if (i > 1) out = out ":"
        out = out $i
      }
      print out "::/64"
    }'
    return
  fi

  printf '%s' "$ip"
}

first_forwarded_ip() {
  printf '%s' "$1" | cut -d',' -f1 | sed -E 's/[[:space:]]//g'
}

REQUEST_IP="$(first_forwarded_ip "$XFF")"
[ -n "$REQUEST_IP" ] || REQUEST_IP="$IP"
IP_PREFIX="$(normalize_ip_prefix "$REQUEST_IP")"
UA_NORMALIZED="$(normalize_device_text "$UA")"
LANG_NORMALIZED="$(normalize_device_text "$ACCEPT_LANGUAGE")"
DEVICE_GUESS_SOURCE="weak"
DEVICE_GUESS_CONFIDENCE="low"
DEVICE_GUESS_HAS_UID="false"
DEVICE_GUESS_HINT="IP prefix + User-Agent + language"

if [ "$UP_UID" != "nouid" ]; then
  DEVICE_GUESS_SOURCE="cookie"
  DEVICE_GUESS_CONFIDENCE="high"
  DEVICE_GUESS_HAS_UID="true"
  DEVICE_GUESS_HINT="UID cookie + IP prefix + User-Agent + language"
fi

if [ -z "$UA_NORMALIZED" ] && [ -z "$IP_PREFIX" ]; then
  DEVICE_GUESS_SOURCE="missing"
  DEVICE_GUESS_CONFIDENCE="unknown"
  DEVICE_GUESS_HINT="not enough request data"
fi

DEVICE_GUESS_KEY_SOURCE="$PUB|$TOKEN|$UP_UID|$UA_NORMALIZED|$LANG_NORMALIZED"
if [ "$UP_UID" = "nouid" ] && [ -z "$UA_NORMALIZED" ] && [ -z "$LANG_NORMALIZED" ]; then
  DEVICE_GUESS_KEY_SOURCE="$DEVICE_GUESS_KEY_SOURCE|$IP_PREFIX"
fi

DEVICE_GUESS_KEY="$(
  printf '%s' "$DEVICE_GUESS_KEY_SOURCE" \
    | sha256sum \
    | awk '{print $1}'
)"

DEVICE_GUESS_NETWORK_KEY="$(
  printf '%s' "$PUB|$TOKEN|$UP_UID|$IP_PREFIX|$UA_NORMALIZED|$LANG_NORMALIZED" \
    | sha256sum \
    | awk '{print $1}'
)"

if [[ ! "$EVENT" =~ ^(open|click|page_view|content|pixel|download)$ ]]; then
  jq -n --arg event "$EVENT" '{status:"error",message:[{text:"invalid event",event:$event}]}'
  exit 1
fi

if [[ ! "$PUB" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
  jq -n '{status:"error",message:[{text:"invalid publication"}]}'
  exit 1
fi

if [[ ! "$TOKEN" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
  jq -n '{status:"error",message:[{text:"invalid token"}]}'
  exit 1
fi

mkdir -p \
  "$RAW_DIR" \
  "$ROOT/by-pub" \
  "$ROOT/by-event" \
  "$ROOT/by-link" \
  "$ROOT/by-uid" \
  "$ROOT/by-user" \
  "$ROOT/.locks" \
  "$ROOT/.seq"

LOCK_FILE="$ROOT/.locks/$UP_UID.lock"
SEQ_FILE="$ROOT/.seq/$UP_UID.seq"

exec 9>"$LOCK_FILE"
flock 9

N="0"
[ -f "$SEQ_FILE" ] && N="$(cat "$SEQ_FILE" 2>/dev/null || echo 0)"
[[ "$N" =~ ^[0-9]+$ ]] || N="0"

N=$((N + 1))
printf '%s' "$N" > "$SEQ_FILE"

RAW_NAME="${UP_UID}_${N}.json"
RAW_FILE="$RAW_DIR/$RAW_NAME"

flock -u 9

META_FILE="$META_ROOT/$PUB/$TOKEN.json"

TYPE=""
SHORT_ID=""
SUBJ=""
LINK=""
TITLE=""
DESCRIPTION=""
IMAGE=""
PRE=""
POST=""
MAILS="[]"
ACTOR=""
OWNER=""
CREATED_BY=""
PUBLISHED_AT=""

if [ -f "$META_FILE" ]; then
  TYPE="$(jq -r '.type // ""' "$META_FILE" 2>/dev/null || echo "")"
  SHORT_ID="$(jq -r '.short_id // .short // ""' "$META_FILE" 2>/dev/null || echo "")"
  SUBJ="$(jq -r '.subj // ""' "$META_FILE" 2>/dev/null || echo "")"
  LINK="$(jq -r '.link // ""' "$META_FILE" 2>/dev/null || echo "")"
  TITLE="$(jq -r '.title // ""' "$META_FILE" 2>/dev/null || echo "")"
  DESCRIPTION="$(jq -r '.description // ""' "$META_FILE" 2>/dev/null || echo "")"
  IMAGE="$(jq -r '.image // ""' "$META_FILE" 2>/dev/null || echo "")"
  PRE="$(jq -r '.pre // ""' "$META_FILE" 2>/dev/null || echo "")"
  POST="$(jq -r '.post // ""' "$META_FILE" 2>/dev/null || echo "")"
  MAILS="$(jq -c 'if (.mails | type) == "array" then .mails else [] end' "$META_FILE" 2>/dev/null || echo '[]')"

  ACTOR="$(jq -r '(.actions // [] | map(select(.actor != null and .actor != "")) | last | .actor) // ""' "$META_FILE" 2>/dev/null || echo "")"
  OWNER="$(jq -r '.owner // ""' "$META_FILE" 2>/dev/null || echo "")"
  CREATED_BY="$(jq -r --arg actor "$ACTOR" '(.created_by // "") as $v | if $v == "" then $actor else $v end' "$META_FILE" 2>/dev/null || echo "$ACTOR")"
  PUBLISHED_AT="$(jq -r '(.created_at // "") as $created | if $created != "" then $created else ((.actions // [] | map(.date // empty) | first) // "") end' "$META_FILE" 2>/dev/null || echo "")"
fi

SHOULD_DECREMENT=0
if [ "$EVENT" = "click" ] && [ "$TYPE" = "redirect" ]; then SHOULD_DECREMENT=1; fi
if [ "$EVENT" = "download" ] && [ "$TYPE" = "download" ]; then SHOULD_DECREMENT=1; fi
if [ "$EVENT" = "content" ] && [ "$TYPE" = "page" ]; then SHOULD_DECREMENT=1; fi
if [ "$EVENT" = "pixel" ] && [ "$TYPE" = "pixel" ]; then SHOULD_DECREMENT=1; fi

DECREMENTED=0
REMAINING_BEFORE=""
REMAINING_AFTER=""

jq -n \
  --arg ts "$TS" \
  --arg event "$EVENT" \
  --arg publication "$PUB" \
  --arg token "$TOKEN" \
  --arg uid "$UP_UID" \
  --argjson seq "$N" \
  --arg filename "$RAW_NAME" \
  --arg original_uri "$ORIGINAL_URI" \
  --arg ip "$IP" \
  --arg xff "$XFF" \
  --arg proto "$PROTO" \
  --arg host "$HOST" \
  --arg ua "$UA" \
  --arg referer "$REFERER" \
  --arg accept_language "$ACCEPT_LANGUAGE" \
  --arg ip_prefix "$IP_PREFIX" \
  --arg ua_normalized "$UA_NORMALIZED" \
  --arg language_normalized "$LANG_NORMALIZED" \
  --arg device_guess_key "$DEVICE_GUESS_KEY" \
  --arg device_guess_network_key "$DEVICE_GUESS_NETWORK_KEY" \
  --arg device_guess_source "$DEVICE_GUESS_SOURCE" \
  --arg device_guess_confidence "$DEVICE_GUESS_CONFIDENCE" \
  --arg device_guess_hint "$DEVICE_GUESS_HINT" \
  --argjson device_guess_has_uid "$DEVICE_GUESS_HAS_UID" \
  --arg page_cookie "$PAGE_COOKIE" \
  --arg pw_cookie "$PW_COOKIE" \
  --arg type "$TYPE" \
  --arg short_id "$SHORT_ID" \
  --arg subj "$SUBJ" \
  --arg link "$LINK" \
  --arg title "$TITLE" \
  --arg description "$DESCRIPTION" \
  --arg image "$IMAGE" \
  --arg pre "$PRE" \
  --arg post "$POST" \
  --arg actor "$ACTOR" \
  --arg owner "$OWNER" \
  --arg created_by "$CREATED_BY" \
  --arg published_at "$PUBLISHED_AT" \
  --arg public_base_url "$PUBLIC_BASE_URL" \
  --argjson mails "$MAILS" \
  '{
    ts: $ts,
    event: $event,

    file: {
      seq: $seq,
      name: $filename
    },

    publication: $publication,
    token: $token,
    uid: $uid,

    request: {
      original_uri: $original_uri,
      ip: $ip,
      xff: $xff,
      ip_prefix: $ip_prefix,
      proto: $proto,
      host: $host,
      ua: $ua,
      ua_normalized: $ua_normalized,
      referer: $referer,
      accept_language: $accept_language,
      language_normalized: $language_normalized
    },

    device_guess: {
      key: $device_guess_key,
      network_key: $device_guess_network_key,
      source: $device_guess_source,
      confidence: $device_guess_confidence,
      has_uid: $device_guess_has_uid,
      ip_prefix: $ip_prefix,
      ua: $ua_normalized,
      language: $language_normalized,
      hint: $device_guess_hint
    },

    cookies: {
      has_uid: ($uid != "nouid"),
      has_page: ($page_cookie != ""),
      has_pw: ($pw_cookie != "")
    },

    meta: {
      type: $type,
      short_id: $short_id,
      subj: $subj,
      mails: $mails,
      pre: $pre,
      link: $link,
      post: $post,
      title: $title,
      description: $description,
      image: $image,
      preview_url: (
        if ($image != "" and $publication != "" and $token != "")
        then ($public_base_url + "/assets-public/" + $publication + "/" + $token + "/" + $image)
        else ""
        end
      ),
      actor: $actor,
      owner: $owner,
      created_by: $created_by,
      published_at: $published_at
    },

    counter: {
      decremented: false,
      remaining_before: "",
      remaining_after: ""
    }
  }' > "$RAW_FILE"

chmod 644 "$RAW_FILE"

REL="../raw/$RAW_NAME"

ln -sf "$REL" "$ROOT/by-uid/${UP_UID}_${N}.json"
ln -sf "$REL" "$ROOT/by-pub/${PUB}_${UP_UID}_${N}.json"
ln -sf "$REL" "$ROOT/by-event/${EVENT}_${UP_UID}_${N}.json"
ln -sf "$REL" "$ROOT/by-link/${PUB}_${TOKEN}_${UP_UID}_${N}.json"

if [[ "$ACTOR" =~ ^[A-Za-z0-9._-]{16,128}$ ]]; then
  ln -sf "$REL" "$ROOT/by-user/${ACTOR}_${UP_UID}_${N}.json"
fi

if [[ "$CREATED_BY" =~ ^[A-Za-z0-9._-]{16,128}$ && "$CREATED_BY" != "$ACTOR" ]]; then
  ln -sf "$REL" "$ROOT/by-user/${CREATED_BY}_${UP_UID}_${N}.json"
fi

if [ "$SHOULD_DECREMENT" = "1" ] && [ -f "$META_FILE" ]; then
  META_LOCK="$ROOT/.locks/meta_${PUB}_${TOKEN}.lock"

  exec 8>"$META_LOCK"
  flock 8

  CUR="$(jq -r '.remaining_clicks // -1' "$META_FILE" 2>/dev/null || echo -1)"
  REMAINING_BEFORE="$CUR"

  if [[ "$CUR" =~ ^-?[0-9]+$ ]] && [ "$CUR" -gt 0 ]; then
    NEW=$((CUR - 1))
    TMP_META="$(mktemp)"

    jq --argjson v "$NEW" '.remaining_clicks = $v' "$META_FILE" > "$TMP_META"
    mv "$TMP_META" "$META_FILE"
    chmod 644 "$META_FILE"

    DECREMENTED=1
    REMAINING_AFTER="$NEW"
  else
    REMAINING_AFTER="$CUR"
  fi

  flock -u 8
fi

TMP_RAW="$(mktemp)"

jq \
  --argjson decremented "$DECREMENTED" \
  --arg remaining_before "$REMAINING_BEFORE" \
  --arg remaining_after "$REMAINING_AFTER" \
  '.counter = {
    decremented: ($decremented == 1),
    remaining_before: $remaining_before,
    remaining_after: $remaining_after
  }' "$RAW_FILE" > "$TMP_RAW"

mv "$TMP_RAW" "$RAW_FILE"
chmod 644 "$RAW_FILE"

if [ "$DECREMENTED" = "1" ] && command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh upsert "$PUB" "$TOKEN" >/dev/null || true
fi

if command -v uportal-activity-index-upsert.sh >/dev/null 2>&1; then
  uportal-activity-index-upsert.sh "$RAW_FILE" >/dev/null || true
fi

if command -v uportal-telegram-notify-event.sh >/dev/null 2>&1; then
  (
    UPORTAL_ROOT="$UPORTAL_ROOT" \
      UPORTAL_TOKEN_ROOT="${UPORTAL_TOKEN_ROOT:-$UPORTAL_ROOT/user-tokens}" \
      uportal-telegram-notify-event.sh \
        "$EVENT" \
        "$PUB" \
        "$TOKEN" \
        "$ORIGINAL_URI" \
        "$IP" \
        "$XFF" \
        "$PROTO" \
        "$HOST" \
        "$UA" \
        "$REFERER" \
        "$ACCEPT_LANGUAGE" \
        "$RAW_UID" \
        "$PAGE_COOKIE" \
        "$PW_COOKIE" \
        "$UA_B64" \
        "$REFERER_B64" \
        "$ACCEPT_LANGUAGE_B64"
  ) >/dev/null 2>&1 </dev/null &
fi

jq -n \
  --arg file "$RAW_NAME" \
  --arg uid "$UP_UID" \
  --argjson seq "$N" \
  --argjson decremented "$DECREMENTED" \
  '{status:"success",message:[{file:$file,uid:$uid,seq:$seq,decremented:($decremented == 1)}]}'

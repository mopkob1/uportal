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

UPORTAL_ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
META_ROOT="$UPORTAL_ROOT/meta"
TOKEN_ROOT="${UPORTAL_TOKEN_ROOT:-$UPORTAL_ROOT/user-tokens}"
NOTIFY_CONFIG="$UPORTAL_ROOT/config/telegram-notify.json"
META_FILE="$META_ROOT/$PUB/$TOKEN.json"

json_skip() {
  jq -cn --arg reason "$1" '{status:"success",message:[{sent:false,reason:$reason}]}'
  exit 0
}

json_error() {
  jq -cn --arg reason "$1" '{status:"error",message:[{sent:false,reason:$reason}]}'
  exit 1
}

[[ "$EVENT" =~ ^(open|click|page_view|content|pixel|download)$ ]] || json_skip "unsupported_event"
[[ "$PUB" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || json_skip "bad_publication"
[[ "$TOKEN" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || json_skip "bad_token"
[ -f "$META_FILE" ] || json_skip "meta_not_found"

if ! jq -e '(.telegram_notify == true)' "$META_FILE" >/dev/null 2>&1; then
  json_skip "telegram_notify_disabled"
fi

[ -f "$NOTIFY_CONFIG" ] || json_skip "telegram_notify_config_not_found"
notify_url="$(jq -r '.url // empty' "$NOTIFY_CONFIG" 2>/dev/null || true)"
[ -n "$notify_url" ] || json_skip "telegram_notify_url_not_configured"

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
UP_UID="$(printf '%s' "$RAW_UID" | cut -d'|' -f1 | sed 's/[^A-Za-z0-9._-]/_/g')"
[ -n "$UP_UID" ] || UP_UID="nouid"

actor="$(jq -r '(.actions // [] | map(select(.actor != null and .actor != "")) | last | .actor) // .created_by // .owner // ""' "$META_FILE" 2>/dev/null || echo "")"
owner_file=""
if [ -n "$actor" ] && [ -d "$TOKEN_ROOT" ]; then
  while IFS= read -r -d '' candidate; do
    if jq -e --arg actor "$actor" '
      (.user_id // "") == $actor or
      (.site.account.id // "") == $actor or
      (.user // "") == $actor
    ' "$candidate" >/dev/null 2>&1; then
      owner_file="$candidate"
      break
    fi
  done < <(find "$TOKEN_ROOT" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
fi

owner_json="$(mktemp)"
if [ -n "$owner_file" ] && [ -f "$owner_file" ]; then
  jq '{
    user: (.user // ""),
    user_id: (.user_id // ""),
    email: (.site.account.email // .site.email.address // .email // ""),
    telegram: (.site.account.telegram // .site.telegram // null),
    bindings: (.site.bindings // {})
  }' "$owner_file" > "$owner_json" 2>/dev/null || jq -n '{}' > "$owner_json"
else
  jq -n '{}' > "$owner_json"
fi

payload_file="$(mktemp)"
jq -n \
  --arg type "telegram_link_event_notify" \
  --arg ts "$TS" \
  --arg event "$EVENT" \
  --arg publication "$PUB" \
  --arg token "$TOKEN" \
  --arg uid "$UP_UID" \
  --arg original_uri "$ORIGINAL_URI" \
  --arg ip "$IP" \
  --arg xff "$XFF" \
  --arg proto "$PROTO" \
  --arg host "$HOST" \
  --arg ua "$UA" \
  --arg referer "$REFERER" \
  --arg accept_language "$ACCEPT_LANGUAGE" \
  --slurpfile meta "$META_FILE" \
  --slurpfile owner "$owner_json" '
  {
    type: $type,
    ts: $ts,
    event: $event,
    publication: $publication,
    token: $token,
    uid: $uid,
    request: {
      original_uri: $original_uri,
      ip: $ip,
      xff: $xff,
      proto: $proto,
      host: $host,
      ua: $ua,
      referer: $referer,
      accept_language: $accept_language
    },
    link: {
      publication_id: ($meta[0].publication_id // $publication),
      token: ($meta[0].token // $token),
      type: ($meta[0].type // ""),
      short_id: ($meta[0].short_id // $meta[0].short // ""),
      subject: ($meta[0].subj // ""),
      title: ($meta[0].title // ""),
      description: ($meta[0].description // ""),
      link: ($meta[0].link // ""),
      telegram_notify: ($meta[0].telegram_notify == true)
    },
    owner: ($owner[0] // {})
  }' > "$payload_file"

headers=(-H "Content-Type: application/json")
auth_token="$(jq -r '.auth.token // empty' "$NOTIFY_CONFIG" 2>/dev/null || true)"
auth_header="$(jq -r '.auth.header // "X-UPORTAL-TELEGRAM-NOTIFY-SECRET"' "$NOTIFY_CONFIG" 2>/dev/null || echo "X-UPORTAL-TELEGRAM-NOTIFY-SECRET")"
auth_type="$(jq -r '.auth.type // "raw"' "$NOTIFY_CONFIG" 2>/dev/null || echo "raw")"

if [ -n "$auth_token" ]; then
  case "${auth_type,,}" in
    bearer) headers+=(-H "$auth_header: Bearer $auth_token") ;;
    token) headers+=(-H "$auth_header: token $auth_token") ;;
    *) headers+=(-H "$auth_header: $auth_token") ;;
  esac
fi

response_file="$(mktemp)"
status="$(
  curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST \
    "${headers[@]}" \
    --data-binary "@$payload_file" \
    "$notify_url" || true
)"

rm -f "$payload_file" "$owner_json"

case "$status" in
  2*) jq -cn --arg status "$status" '{status:"success",message:[{sent:true,http_status:$status}]}' ;;
  *) reason="$(head -c 500 "$response_file" 2>/dev/null || true)"; rm -f "$response_file"; json_error "telegram_notify_failed ${status} ${reason}" ;;
esac

rm -f "$response_file"

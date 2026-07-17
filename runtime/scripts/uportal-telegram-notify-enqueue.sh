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
META_FILE="$UPORTAL_ROOT/meta/$PUB/$TOKEN.json"
QUEUE_DIR="$UPORTAL_ROOT/telegram-notify-queue"

json_skip() {
  jq -cn --arg reason "$1" '{status:"success",message:[{queued:false,reason:$reason}]}'
  exit 0
}

[[ "$EVENT" =~ ^(open|click|page_view|content|pixel|download)$ ]] || json_skip "unsupported_event"
[[ "$PUB" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || json_skip "bad_publication"
[[ "$TOKEN" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || json_skip "bad_token"
[ -f "$META_FILE" ] || json_skip "meta_not_found"

if ! jq -e '(.telegram_notify == true)' "$META_FILE" >/dev/null 2>&1; then
  json_skip "telegram_notify_disabled"
fi

mkdir -p "$QUEUE_DIR"

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
UP_UID="$(printf '%s' "$RAW_UID" | cut -d'|' -f1 | sed 's/[^A-Za-z0-9._-]/_/g')"
[ -n "$UP_UID" ] || UP_UID="nouid"

name_ts="$(date -u +"%Y%m%dT%H%M%S")"
rand="$(dd if=/dev/urandom bs=8 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
tmp="$(mktemp "$QUEUE_DIR/.telegram-notify.XXXXXX.tmp")"
final="$QUEUE_DIR/${name_ts}_${PUB}_${TOKEN}_${UP_UID}_${rand}.json"

jq -n \
  --arg task "telegram_notify" \
  --arg config "telegram-notify" \
  --arg ts "$TS" \
  --arg event "$EVENT" \
  --arg publication "$PUB" \
  --arg token "$TOKEN" \
  --arg uid "$RAW_UID" \
  --arg page_cookie "$PAGE_COOKIE" \
  --arg pw_cookie "$PW_COOKIE" \
  --arg original_uri "$ORIGINAL_URI" \
  --arg ip "$IP" \
  --arg xff "$XFF" \
  --arg proto "$PROTO" \
  --arg host "$HOST" \
  --arg ua "$UA" \
  --arg referer "$REFERER" \
  --arg accept_language "$ACCEPT_LANGUAGE" \
  '{
    task: $task,
    webhook: {config: $config},
    created_at: $ts,
    event: $event,
    publication: $publication,
    token: $token,
    uid: $uid,
    page_cookie: $page_cookie,
    pw_cookie: $pw_cookie,
    request: {
      original_uri: $original_uri,
      ip: $ip,
      xff: $xff,
      proto: $proto,
      host: $host,
      ua: $ua,
      referer: $referer,
      accept_language: $accept_language
    }
  }' > "$tmp"

mv "$tmp" "$final"
chmod 644 "$final"

jq -cn --arg file "$(basename "$final")" '{status:"success",message:[{queued:true,file:$file}]}'

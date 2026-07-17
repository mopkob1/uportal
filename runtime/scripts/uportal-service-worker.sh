#!/usr/bin/env bash
set -euo pipefail

UPORTAL_ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
QUEUE_DIR="${UPORTAL_TELEGRAM_NOTIFY_QUEUE_DIR:-$UPORTAL_ROOT/telegram-notify-queue}"
GRANT_DIR="${UPORTAL_UPLOAD_GRANT_DIR:-$UPORTAL_ROOT/upload-grants}"
POLL_SECONDS="${UPORTAL_SERVICE_WORKER_POLL_SECONDS:-60}"

mkdir -p "$QUEUE_DIR" "$GRANT_DIR"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

json_value() {
  local file="$1"
  local filter="$2"
  jq -r "$filter // \"\"" "$file" 2>/dev/null || true
}

process_notify_file() {
  local file="$1"
  local task
  local output
  local status

  [ -f "$file" ] || return 0
  case "$file" in
    *.json) ;;
    *) return 0 ;;
  esac

  task="$(json_value "$file" '.task')"
  if [ "$task" != "telegram_notify" ]; then
    log "telegram-notify skipped file=$(basename "$file") reason=unsupported_task task=$task"
    rm -f "$file"
    return 0
  fi

  if [ "$(json_value "$file" '.webhook.config')" != "telegram-notify" ]; then
    log "telegram-notify skipped file=$(basename "$file") reason=no_webhook_config"
    rm -f "$file"
    return 0
  fi

  set +e
  output="$(
    uportal-telegram-notify-event.sh \
      "$(json_value "$file" '.event')" \
      "$(json_value "$file" '.publication')" \
      "$(json_value "$file" '.token')" \
      "$(json_value "$file" '.request.original_uri')" \
      "$(json_value "$file" '.request.ip')" \
      "$(json_value "$file" '.request.xff')" \
      "$(json_value "$file" '.request.proto')" \
      "$(json_value "$file" '.request.host')" \
      "$(json_value "$file" '.request.ua')" \
      "$(json_value "$file" '.request.referer')" \
      "$(json_value "$file" '.request.accept_language')" \
      "$(json_value "$file" '.uid')" \
      "$(json_value "$file" '.page_cookie')" \
      "$(json_value "$file" '.pw_cookie')" \
      "" \
      "" \
      "" 2>&1
  )"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    log "telegram-notify processed file=$(basename "$file") result=$output"
  else
    log "telegram-notify failed file=$(basename "$file") status=$status result=$output"
  fi

  rm -f "$file"
}

process_notify_queue() {
  local file
  find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      process_notify_file "$file"
    done

  find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.tmp' -mmin +10 -delete 2>/dev/null || true
}

cleanup_upload_grants() {
  local file
  local expires
  local expires_epoch
  local now

  now="$(date +%s)"
  find "$GRANT_DIR" -maxdepth 1 -type f -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      case "$file" in
        *.tmp)
          find "$GRANT_DIR" -maxdepth 1 -type f -name '*.tmp' -mmin +10 -delete 2>/dev/null || true
          continue
          ;;
      esac

      expires="$(json_value "$file" '.expires_at')"
      if [ -z "$expires" ]; then
        log "upload-grant removed file=$(basename "$file") reason=missing_expires_at"
        rm -f "$file"
        continue
      fi

      expires_epoch="$(date -d "$expires" +%s 2>/dev/null || true)"
      if [ -z "$expires_epoch" ] || [ "$expires_epoch" -le "$now" ]; then
        log "upload-grant expired file=$(basename "$file") expires_at=$expires"
        rm -f "$file"
      fi
    done
}

tick() {
  process_notify_queue
  cleanup_upload_grants
}

log "uportal service worker started queue=$QUEUE_DIR grants=$GRANT_DIR"

while true; do
  tick

  if command -v inotifywait >/dev/null 2>&1; then
    inotifywait -q -e close_write,moved_to,create -t "$POLL_SECONDS" "$QUEUE_DIR" "$GRANT_DIR" >/dev/null 2>&1 || true
  else
    sleep "$POLL_SECONDS"
  fi
done

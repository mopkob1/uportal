#!/usr/bin/env bash
set -euo pipefail

UPORTAL_ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
QUEUE_DIR="${UPORTAL_TELEGRAM_NOTIFY_QUEUE_DIR:-$UPORTAL_ROOT/telegram-notify-queue}"
QUOTA_QUEUE_DIR="${UPORTAL_QUOTA_RECONCILE_QUEUE_DIR:-$UPORTAL_ROOT/quota-reconcile-queue}"
GRANT_DIR="${UPORTAL_UPLOAD_GRANT_DIR:-$UPORTAL_ROOT/upload-grants}"
RESERVATION_DIR="${UPORTAL_QUOTA_RESERVATION_DIR:-$UPORTAL_ROOT/site/quota/reservations}"
ACCOUNT_QUOTA_DIR="${UPORTAL_QUOTA_ACCOUNT_DIR:-$UPORTAL_ROOT/site/quota/accounts}"
TOKEN_DIR="${UPORTAL_TOKEN_ROOT:-$UPORTAL_ROOT/user-tokens}"
META_DIR="${UPORTAL_META_DIR:-$UPORTAL_ROOT/meta}"
STORAGE_DIR="${UPORTAL_STORAGE_DIR:-$UPORTAL_ROOT/storage}"
POLL_SECONDS="${UPORTAL_SERVICE_WORKER_POLL_SECONDS:-60}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_EVENT_SCRIPT="${UPORTAL_TELEGRAM_NOTIFY_EVENT_SCRIPT:-$SCRIPT_DIR/uportal-telegram-notify-event.sh}"

mkdir -p "$QUEUE_DIR" "$QUOTA_QUEUE_DIR" "$GRANT_DIR" "$RESERVATION_DIR" "$ACCOUNT_QUOTA_DIR"

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
    "$NOTIFY_EVENT_SCRIPT" \
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

is_safe_part() {
  case "$1" in
    ""|*".."*|*"/"*|*"\\"*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._-]{1,160}$'
}

quota_account_hash() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

bytes_to_mb() {
  awk -v bytes="${1:-0}" 'BEGIN { printf "%.1f", bytes / 1024 / 1024 }'
}

mb_to_bytes() {
  awk -v mb="${1:-0}" 'BEGIN { if (mb <= 0) print 0; else printf "%.0f\n", mb * 1024 * 1024 }'
}

file_size_sum() {
  local dir="$1"
  [ -d "$dir" ] || {
    printf '0'
    return 0
  }
  find "$dir" -type f -printf '%s\n' 2>/dev/null | awk '{sum += $1} END {printf "%.0f", sum}'
}

owner_ids_for_publication() {
  local publication_id="$1"
  local token="$2"
  local meta_file="$META_DIR/$publication_id/$token.json"

  [ -f "$meta_file" ] || {
    printf '[]'
    return 0
  }

  jq -c '
    [
      (.created_by // empty),
      (.owner // empty),
      (.actions // [] | .[]? | .actor // empty)
    ]
    | map(select(. != null and . != ""))
    | unique
  ' "$meta_file" 2>/dev/null || printf '[]'
}

find_token_file_for_owner() {
  local owner_key="$1"
  local owner_ids_json="$2"
  local token_file

  find "$TOKEN_DIR" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null |
    while IFS= read -r -d '' token_file; do
      if jq -e --arg owner_key "$owner_key" --argjson owner_ids "$owner_ids_json" '
        [
          (.user_id // empty),
          (.site.account.id // empty),
          (.user // empty),
          (.site.account.displayName // empty)
        ]
        | map(tostring)
        | unique
        | any(. as $id | $id == $owner_key or ($owner_ids | index($id)))
      ' "$token_file" >/dev/null 2>&1; then
        printf '%s' "$token_file"
        return 0
      fi
    done
}

meta_owned_by() {
  local meta_file="$1"
  local owner_ids_json="$2"

  jq -e --argjson owner_ids "$owner_ids_json" '
    [
      (.created_by // empty),
      (.owner // empty),
      (.actions // [] | .[]? | .actor // empty)
    ]
    | map(tostring)
    | any(. as $id | ($owner_ids | index($id)))
  ' "$meta_file" >/dev/null 2>&1
}

recalculate_owner_quota() {
  local token_file="$1"
  local owner_key="$2"
  local owner_ids_json="$3"
  local reason="${4:-quota_recalculate}"
  local storage_mb
  local storage_limit_bytes
  local used_bytes=0
  local reserved_bytes=0
  local links=0
  local publications
  local pub_file
  local meta_file
  local pub
  local link_token
  local payload_dir
  local reservation
  local snapshot_file
  local tmp_pubs
  local tmp
  local now

  if [ -z "$owner_key" ]; then
    owner_key="$(jq -r '.user_id // .site.account.id // .user // ""' "$token_file" 2>/dev/null || true)"
  fi
  if [ -z "$owner_key" ]; then
    log "quota-recalculate skipped reason=empty_owner token_file=$(basename "$token_file")"
    return 0
  fi

  if [ "$owner_ids_json" = "[]" ] || [ -z "$owner_ids_json" ]; then
    owner_ids_json="$(jq -c '[.user_id, .site.account.id, .user, .site.account.displayName] | map(select(. != null and . != "")) | unique' "$token_file" 2>/dev/null || printf '[]')"
  fi

  storage_mb="$(jq -r '.site.limits.storage_mb // .limits.storage_mb // 0' "$token_file" 2>/dev/null || printf '0')"
  storage_limit_bytes="$(mb_to_bytes "$storage_mb")"
  tmp_pubs="$(mktemp)"

  while IFS= read -r -d '' meta_file; do
    meta_owned_by "$meta_file" "$owner_ids_json" || continue
    pub="$(jq -r '.publication_id // ""' "$meta_file" 2>/dev/null || true)"
    link_token="$(jq -r '.token // ""' "$meta_file" 2>/dev/null || true)"
    is_safe_part "$pub" || continue
    is_safe_part "$link_token" || continue

    printf '%s\n' "$pub" >> "$tmp_pubs"
    links=$((links + 1))
    payload_dir="$STORAGE_DIR/$pub/$link_token"
    used_bytes=$((used_bytes + $(file_size_sum "$payload_dir")))
  done < <(find "$META_DIR" -mindepth 2 -maxdepth 2 -type f -name '*.json' -print0 2>/dev/null)

  publications="$(sort -u "$tmp_pubs" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  rm -f "$tmp_pubs"

  while IFS= read -r -d '' reservation; do
    if [ "$(json_value "$reservation" '.ownerKey')" = "$owner_key" ]; then
      reserved_bytes=$((reserved_bytes + $(jq -r '.bytes // 0' "$reservation" 2>/dev/null || printf '0')))
    fi
  done < <(find "$RESERVATION_DIR" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)

  snapshot_file="$ACCOUNT_QUOTA_DIR/$(quota_account_hash "$owner_key").json"
  tmp="$(mktemp)"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -n \
    --arg ownerKey "$owner_key" \
    --argjson ownerIds "$owner_ids_json" \
    --arg ownerHash "$(quota_account_hash "$owner_key")" \
    --arg reason "$reason" \
    --arg updatedAt "$now" \
    --argjson storageLimitBytes "$storage_limit_bytes" \
    --argjson storageUsedBytes "$used_bytes" \
    --argjson storageReservedBytes "$reserved_bytes" \
    --argjson publications "$publications" \
    --argjson links "$links" '
    ($storageLimitBytes - $storageUsedBytes - $storageReservedBytes) as $remaining
    | {
        version: 1,
        ownerKey: $ownerKey,
        ownerIds: $ownerIds,
        ownerHash: $ownerHash,
        reason: $reason,
        storageLimitBytes: $storageLimitBytes,
        storageUsedBytes: $storageUsedBytes,
        storageReservedBytes: $storageReservedBytes,
        storageRemainingBytes: (if $remaining > 0 then $remaining else 0 end),
        storageUsedMb: (($storageUsedBytes / 1024 / 1024 * 10 | round) / 10),
        storageReservedMb: (($storageReservedBytes / 1024 / 1024 * 10 | round) / 10),
        storageRemainingMb: (((if $remaining > 0 then $remaining else 0 end) / 1024 / 1024 * 10 | round) / 10),
        publications: $publications,
        links: $links,
        updatedAt: $updatedAt
      }
  ' > "$tmp"
  mv -f "$tmp" "$snapshot_file"
  chmod 644 "$snapshot_file"

  log "quota-recalculate processed owner=$owner_key used=$used_bytes reserved=$reserved_bytes publications=$publications links=$links reason=$reason"
}

process_quota_file() {
  local file="$1"
  local task
  local publication_id
  local token
  local reservation
  local reservation_pub
  local reservation_token
  local grant
  local grant_pub
  local grant_token
  local owner_key
  local owner_ids_json
  local token_file
  local removed=0
  local grants_removed=0

  [ -f "$file" ] || return 0
  case "$file" in
    *.json) ;;
    *) return 0 ;;
  esac

  task="$(json_value "$file" '.task')"
  if [ "$task" != "quota_reconcile" ] && [ "$task" != "quota_recalculate" ]; then
    log "quota-reconcile skipped file=$(basename "$file") reason=unsupported_task task=$task"
    rm -f "$file"
    return 0
  fi

  publication_id="$(json_value "$file" '.publication_id')"
  token="$(json_value "$file" '.token')"
  owner_key="$(json_value "$file" '.ownerKey')"
  owner_ids_json="$(jq -c '.ownerIds // []' "$file" 2>/dev/null || printf '[]')"

  if [ "$task" = "quota_recalculate" ]; then
    token_file="$(find_token_file_for_owner "$owner_key" "$owner_ids_json")"
    if [ -z "$token_file" ]; then
      log "quota-recalculate skipped file=$(basename "$file") reason=owner_token_not_found owner=$owner_key"
      rm -f "$file"
      return 0
    fi
    recalculate_owner_quota "$token_file" "$owner_key" "$owner_ids_json" "$(json_value "$file" '.reason')"
    rm -f "$file"
    return 0
  fi

  if ! is_safe_part "$publication_id" || ! is_safe_part "$token"; then
    log "quota-reconcile skipped file=$(basename "$file") reason=bad_publication_or_token publication=$publication_id token=$token"
    rm -f "$file"
    return 0
  fi

  while IFS= read -r -d '' reservation; do
    reservation_pub="$(json_value "$reservation" '.publicationId')"
    reservation_token="$(json_value "$reservation" '.linkToken')"
    if [ "$reservation_pub" = "$publication_id" ] && [ "$reservation_token" = "$token" ]; then
      rm -f "$reservation"
      removed=$((removed + 1))
    fi
  done < <(find "$RESERVATION_DIR" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)

  while IFS= read -r -d '' grant; do
    grant_pub="$(json_value "$grant" '.publication_id')"
    grant_token="$(json_value "$grant" '.token_link')"
    if [ "$grant_pub" = "$publication_id" ] && [ "$grant_token" = "$token" ]; then
      rm -f "$grant"
      grants_removed=$((grants_removed + 1))
    fi
  done < <(find "$GRANT_DIR" -maxdepth 1 -type f ! -name '*.tmp' -print0 2>/dev/null)

  if [ -z "$owner_key" ] || [ "$owner_ids_json" = "[]" ]; then
    owner_ids_json="$(owner_ids_for_publication "$publication_id" "$token")"
    owner_key="$(printf '%s' "$owner_ids_json" | jq -r '.[0] // ""' 2>/dev/null || true)"
  fi
  token_file="$(find_token_file_for_owner "$owner_key" "$owner_ids_json")"
  if [ -n "$token_file" ]; then
    recalculate_owner_quota "$token_file" "$owner_key" "$owner_ids_json" "$(json_value "$file" '.reason')"
  else
    log "quota-reconcile owner snapshot skipped publication=$publication_id token=$token reason=owner_token_not_found owner=$owner_key"
  fi

  log "quota-reconcile processed file=$(basename "$file") publication=$publication_id token=$token reservations_removed=$removed grants_removed=$grants_removed"
  rm -f "$file"
}

process_quota_queue() {
  local file
  find "$QUOTA_QUEUE_DIR" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      process_quota_file "$file"
    done

  find "$QUOTA_QUEUE_DIR" -maxdepth 1 -type f -name '*.tmp' -mmin +10 -delete 2>/dev/null || true
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
  process_quota_queue
  cleanup_upload_grants
}

log "uportal service worker started telegram_queue=$QUEUE_DIR quota_queue=$QUOTA_QUEUE_DIR grants=$GRANT_DIR"

while true; do
  tick

  if command -v inotifywait >/dev/null 2>&1; then
    inotifywait -q -e close_write,moved_to,create -t "$POLL_SECONDS" "$QUEUE_DIR" "$QUOTA_QUEUE_DIR" "$GRANT_DIR" >/dev/null 2>&1 || true
  else
    sleep "$POLL_SECONDS"
  fi
done

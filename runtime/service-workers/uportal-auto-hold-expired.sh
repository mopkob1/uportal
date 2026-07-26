#!/usr/bin/env bash
set -euo pipefail

UPORTAL_ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
META_DIR="${UPORTAL_META_DIR:-$UPORTAL_ROOT/meta}"
LOCK_DIR="$UPORTAL_ROOT/.locks/auto-hold"
HOOK_DIR="${UPORTAL_AUTO_HOLD_HOOK_DIR:-$UPORTAL_ROOT/auto-hold-hooks}"
DRY_RUN=0

if [ -f /usr/local/bin/uportal-actions.sh ]; then
  source /usr/local/bin/uportal-actions.sh
else
  source "$(cd "$(dirname "$0")/.." && pwd)/scripts/uportal-actions.sh"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    *) ;;
  esac
  shift
done

mkdir -p "$LOCK_DIR" "$HOOK_DIR"

json_error() {
  jq -cn --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

safe_part() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._-]{1,160}$'
}

reason_for_meta() {
  local meta_file="$1"
  local status
  local fresh_until
  local fresh_epoch
  local clicks
  local now_epoch

  status="$(jq -r '.status // "active"' "$meta_file" 2>/dev/null || true)"
  [ "$status" = "active" ] || return 0

  now_epoch="$(date +%s)"
  fresh_until="$(jq -r '.fresh_until // "-1"' "$meta_file" 2>/dev/null || printf -- '-1')"
  case "$fresh_until" in
    ""|"-1"|"null") ;;
    *)
      fresh_epoch="$(date -d "$fresh_until" +%s 2>/dev/null || true)"
      if [ -n "$fresh_epoch" ] && [ "$fresh_epoch" -le "$now_epoch" ]; then
        printf 'freshness_expired'
        return 0
      fi
      ;;
  esac

  clicks="$(jq -r '.remaining_clicks // -1' "$meta_file" 2>/dev/null || printf -- '-1')"
  if [[ "$clicks" =~ ^-?[0-9]+$ ]] && [ "$clicks" -eq 0 ]; then
    printf 'clicks_exhausted'
  fi
}

run_hook_scripts() {
  local meta_file="$1"
  local worker_file="$2"
  local results_file="$3"
  local hook
  local name
  local output
  local status

  find "$HOOK_DIR" -maxdepth 1 -type f -perm /111 -print0 2>/dev/null |
    sort -z |
    while IFS= read -r -d '' hook; do
      name="$(basename "$hook")"
      set +e
      output="$("$hook" "$meta_file" "$worker_file" 2>&1)"
      status=$?
      set -e

      jq -cn \
        --arg name "$name" \
        --arg path "$hook" \
        --arg output "$output" \
        --argjson exit_code "$status" \
        '{
          name: $name,
          path: $path,
          exit_code: $exit_code,
          ok: ($exit_code == 0)
        }
        + (if $output != "" then {output: $output} else {} end)' >> "$results_file"
    done
}

scanned=0
updated=0
dry_run_matches=0
skipped=0
hooks_file="$(mktemp)"
updated_file="$(mktemp)"
trap 'rm -f "$updated_file" "$hooks_file"' EXIT

[ -d "$META_DIR" ] || json_error "meta directory not found: $META_DIR"

while IFS= read -r -d '' meta_file; do
  scanned=$((scanned + 1))
  reason="$(reason_for_meta "$meta_file")"
  [ -n "$reason" ] || continue

  publication_id="$(jq -r '.publication_id // ""' "$meta_file" 2>/dev/null || true)"
  token="$(jq -r '.token // ""' "$meta_file" 2>/dev/null || true)"
  if ! safe_part "$publication_id" || ! safe_part "$token"; then
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" = "1" ]; then
    dry_run_matches=$((dry_run_matches + 1))
    jq -cn \
      --arg publication_id "$publication_id" \
      --arg token "$token" \
      --arg reason "$reason" \
      '{publication_id:$publication_id,token:$token,reason:$reason}' >> "$updated_file"
    continue
  fi

  lock_file="$LOCK_DIR/${publication_id}_${token}.lock"
  worker_file="$(mktemp)"
  (
    flock 7
    reason="$(reason_for_meta "$meta_file")"
    [ -n "$reason" ] || exit 0
    detected_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    jq -cn \
      --arg worker "uportal-auto-hold-expired" \
      --arg date "$detected_at" \
      --arg publication_id "$publication_id" \
      --arg token "$token" \
      --arg reason "$reason" \
      --arg hook_dir "$HOOK_DIR" \
      '{
        worker: $worker,
        date: $date,
        event: "auto_hold",
        publication_id: $publication_id,
        token: $token,
        status_before: "active",
        status_after: "hold",
        reason: $reason,
        hook_dir: $hook_dir
      }' > "$worker_file"
    load_actions "$meta_file"
    set_link_status_with_history "$meta_file" "hold" "system" "$reason"
    short_id="$(jq -r '.short_id // .short // ""' "$meta_file" 2>/dev/null || true)"
    append_action "$meta_file" "auto_hold" "system" "$short_id"
    refresh_link_index "$publication_id" "$token"
    run_hook_scripts "$meta_file" "$worker_file" "$hooks_file"
  ) 7>"$lock_file"
  rm -f "$worker_file"

  updated=$((updated + 1))
  jq -cn \
    --arg publication_id "$publication_id" \
    --arg token "$token" \
    --arg reason "$reason" \
    '{publication_id:$publication_id,token:$token,reason:$reason}' >> "$updated_file"
done < <(find "$META_DIR" -mindepth 2 -maxdepth 2 -type f -name '*.json' -print0 2>/dev/null)

jq -cn \
  --argjson scanned "$scanned" \
  --argjson updated "$updated" \
  --argjson dry_run "$DRY_RUN" \
  --argjson dry_run_matches "$dry_run_matches" \
  --argjson skipped "$skipped" \
  --slurpfile hooks "$hooks_file" \
  --slurpfile links "$updated_file" '
  {
    status: "success",
    message: [
      {
        scanned: $scanned,
        updated: $updated,
        dry_run: ($dry_run == 1),
        dry_run_matches: $dry_run_matches,
        skipped: $skipped,
        hooks: $hooks,
        links: $links
      }
    ]
  }
'

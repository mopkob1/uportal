#!/usr/bin/env bash

ACTIONS_JSON='[]'

if [ -f /usr/local/bin/uportal-user-identity.sh ]; then
  source /usr/local/bin/uportal-user-identity.sh
else
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uportal-user-identity.sh"
fi

write_audit_action() {
  local scope="$1"
  local action_type="$2"
  local actor
  actor="$(uportal_resolve_user_id "${3:-}")"
  local publication_id="$4"
  local token="$5"
  local short_id="$6"
  local details_file="$7"
  local now="$8"

  local base="${UPORTAL_BASE:-/data/files/uportal}"
  local audit_dir="$base/audit"
  local audit_file
  local tmp

  audit_file="$audit_dir/$(date -u +"%Y-%m").jsonl"
  mkdir -p "$audit_dir"
  tmp="$(mktemp)"

  jq -c -n \
    --arg ts "$now" \
    --arg scope "$scope" \
    --arg type "$action_type" \
    --arg actor "$actor" \
    --arg publication_id "$publication_id" \
    --arg token "$token" \
    --arg short_id "$short_id" \
    --slurpfile details "$details_file" '
    {
      ts: $ts,
      scope: $scope,
      type: $type,
      actor: $actor,
      publication_id: $publication_id,
      token: $token,
      short_id: $short_id
    }
    +
    (
      if (($details[0] // {}) | type) == "object" and (($details[0] // {}) | length) > 0 then
        { details: ($details[0] // {}) }
      else
        {}
      end
    )
  ' > "$tmp"

  if command -v flock >/dev/null 2>&1; then
    {
      flock 200
      cat "$tmp" >> "$audit_file"
      chmod 644 "$audit_file"
    } 200>"$audit_dir/.audit.lock"
  else
    cat "$tmp" >> "$audit_file"
    chmod 644 "$audit_file"
  fi
  rm -f "$tmp"
}

# Read old actions into memory before overwriting meta.
load_actions() {
  local meta_file="$1"

  if [ ! -f "$meta_file" ]; then
    ACTIONS_JSON='[]'
    return 0
  fi

  ACTIONS_JSON="$(jq -c '
    if (.actions | type) == "array" then .actions else [] end
  ' "$meta_file" 2>/dev/null || echo '[]')"
}

# Add the new action to the already loaded old array.
append_action() {
  local meta_file="$1"
  local action_type="$2"
  local actor
  actor="$(uportal_resolve_user_id "${3:-}")"
  local short_id="$4"
  shift 4

  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local old_actions_file
  local new_action_file
  local details_file
  local detail_pair
  local detail_key
  local detail_value
  local tmp

  old_actions_file="$(mktemp)"
  new_action_file="$(mktemp)"
  details_file="$(mktemp)"
  tmp="$(mktemp)"

  printf '%s' "$ACTIONS_JSON" > "$old_actions_file"

  jq -n '{}' > "$details_file"

  for detail_pair in "$@"; do
    detail_key="${detail_pair%%=*}"
    detail_value="${detail_pair#*=}"

    case "$detail_key" in
      pre|post|link|target_url)
        tmp_details="$(mktemp)"
        jq --arg key "$detail_key" --arg value "$detail_value" '
          .[$key] = $value
        ' "$details_file" > "$tmp_details"
        mv "$tmp_details" "$details_file"
        ;;
    esac
  done

  jq -n \
    --arg type "$action_type" \
    --arg date "$now" \
    --arg actor "$actor" \
    --arg short_id "$short_id" \
    --slurpfile details "$details_file" '
    {
      type: $type,
      date: $date,
      actor: $actor,
      short_id: $short_id
    }
    +
    (
      if (($details[0] // {}) | type) == "object" then
        { details: ($details[0] // {}) }
      else
        {}
      end
    )
  ' > "$new_action_file"

  publication_id="$(jq -r '.publication_id // ""' "$meta_file" 2>/dev/null || echo "")"
  token="$(jq -r '.token // ""' "$meta_file" 2>/dev/null || echo "")"
  write_audit_action "link" "$action_type" "$actor" "$publication_id" "$token" "$short_id" "$details_file" "$now"

  if [ -f "$meta_file" ]; then
    jq \
      --slurpfile old "$old_actions_file" \
      --slurpfile new "$new_action_file" '
      .actions = (($old[0] // []) + [$new[0]])
    ' "$meta_file" > "$tmp"
  else
    jq -n \
      --slurpfile old "$old_actions_file" \
      --slurpfile new "$new_action_file" '
      {
        actions: (($old[0] // []) + [$new[0]])
      }
    ' > "$tmp"
  fi

  mv "$tmp" "$meta_file"
  chmod 644 "$meta_file"
  rm -f "$old_actions_file" "$new_action_file" "$details_file"
}

refresh_link_index() {
  local publication_id="$1"
  local token="$2"
  local upserter=""

  if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
    upserter="uportal-links-index-upsert.sh"
  elif [ -x "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uportal-links-index-upsert.sh" ]; then
    upserter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uportal-links-index-upsert.sh"
  fi

  if [ -n "$upserter" ]; then
    "$upserter" upsert "$publication_id" "$token" >/dev/null || true
  fi
}

apply_publish_telegram_notify_policy() {
  local meta_file="$1"
  local token_root="${UPORTAL_TOKEN_ROOT:-${UPORTAL_BASE:-/data/files/uportal}/user-tokens}"
  local policy_file="${UPORTAL_FREE_TELEGRAM_NOTIFY_POLICY_FILE:-${UPORTAL_SERVICE_WORKER_CONFIG_DIR:-${UPORTAL_BASE:-/data/files/uportal}/site/service-worker-config}/free-telegram-notify-policy.json}"
  local owner_ids_json
  local token_file=""
  local candidate
  local token_name
  local plan
  local published_at
  local published_epoch
  local disable_seconds
  local disable_at
  local now
  local tmp

  [ -f "$meta_file" ] || return 0
  [ -f "$policy_file" ] || return 0
  jq -e '(.enabled // true) == true' "$policy_file" >/dev/null 2>&1 || return 0
  jq -e '(.commercial_free_telegram | type) == "object"' "$meta_file" >/dev/null 2>&1 && return 0
  jq -e '.telegram_notify == true' "$meta_file" >/dev/null 2>&1 && return 0

  owner_ids_json="$(jq -c '
    [
      (.created_by // empty),
      (.owner // empty),
      (.actions // [] | .[]? | .actor // empty)
    ]
    | map(tostring)
    | map(select(. != ""))
    | unique
  ' "$meta_file" 2>/dev/null || printf '[]')"

  [ "$(printf '%s' "$owner_ids_json" | jq 'length' 2>/dev/null || printf 0)" -gt 0 ] || return 0
  [ -d "$token_root" ] || return 0

  while IFS= read -r -d '' candidate; do
    token_name="$(basename "$candidate" .json)"
    if jq -e --arg token_name "$token_name" --argjson owner_ids "$owner_ids_json" '
      [
        $token_name,
        (.user_id // empty),
        (.site.account.id // empty),
        (.user // empty),
        (.site.account.displayName // empty)
      ]
      | map(tostring)
      | any(. as $id | ($owner_ids | index($id)))
    ' "$candidate" >/dev/null 2>&1; then
      token_file="$candidate"
      break
    fi
  done < <(find "$token_root" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)

  [ -n "$token_file" ] || return 0

  plan="$(jq -r '
    .site.subscription.plan
    // .site.plan
    // .plan
    // .tariff
    // "free"
    | tostring
    | ascii_downcase
  ' "$token_file" 2>/dev/null || printf 'free')"

  jq -e --arg plan "$plan" '
    (.plans // ["free"])
    | map(tostring | ascii_downcase)
    | index($plan) != null
  ' "$policy_file" >/dev/null 2>&1 || return 0

  jq -e '
    (.site.bindings.telegram == true)
    or ((.site.account.telegram // .site.telegram // .telegram // {}) as $tg
      | (($tg.chat_id // "") != "")
        or (($tg.user_id // "") != "")
        or (($tg.username // "") != ""))
  ' "$token_file" >/dev/null 2>&1 || return 0

  published_at="$(jq -r '
    (.actions // [])
    | map(select((.type // "") == "redirect" or (.type // "") == "page" or (.type // "") == "download" or (.type // "") == "pixel"))
    | .[0].date // empty
  ' "$meta_file" 2>/dev/null || true)"
  [ -n "$published_at" ] || published_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  published_epoch="$(date -d "$published_at" +%s 2>/dev/null || date +%s)"
  disable_seconds="$(jq -r --arg plan "$plan" '
    ($plan | tostring | ascii_downcase) as $p
    | ((.disable_after_by_plan_hours // {})[$p] // null) as $plan_hours
    | (
        (.disable_after_by_plan_seconds // {})[$p]
        // (if $plan_hours == null then null else ($plan_hours * 3600) end)
        // .disable_after_seconds
        // ((.disable_after_hours // 24) * 3600)
      )
    | tonumber
    | if . < 1 then 86400 else floor end
  ' "$policy_file" 2>/dev/null || printf '86400')"
  disable_at="$(date -u -d "@$((published_epoch + disable_seconds))" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp)"

  jq \
    --arg date "$now" \
    --arg plan "$plan" \
    --arg published_at "$published_at" \
    --arg disable_at "$disable_at" \
    --arg reason "${plan}_publish_telegram_enabled" '
    .telegram_notify = true
    | .commercial_free_telegram = {
        first_published_at: $published_at,
        disable_at: $disable_at,
        evaluated_at: $date,
        plan: $plan,
        telegram_bound: true,
        auto_enabled: true,
        reason: $reason
      }
  ' "$meta_file" > "$tmp"

  mv "$tmp" "$meta_file"
  chmod 644 "$meta_file"

  load_actions "$meta_file"
  append_action "$meta_file" "free_telegram_notify_auto_enable" "system" "$(jq -r '.short_id // .short // ""' "$meta_file")"
}

append_status_history() {
  local meta_file="$1"
  local status="$2"
  local src="${3:-system}"
  local reason="${4:-}"
  local now
  local tmp

  [ -f "$meta_file" ] || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp)"

  jq \
    --arg status "$status" \
    --arg src "$src" \
    --arg reason "$reason" \
    --arg date "$now" '
    def clean_history:
      if (.status_history | type) == "array" then .status_history else [] end;

    .status = $status
    | .status_history = (
        clean_history as $history
        | ($history | last) as $last
        | if
            ($last != null)
            and (($last.status // "") == $status)
            and (($last.src // "") == $src)
            and (($last.reason // "") == $reason)
          then
            $history
          else
            $history + [
              {
                date: $date,
                status: $status,
                src: $src
              }
              + (if $reason != "" then {reason: $reason} else {} end)
            ]
          end
      )
  ' "$meta_file" > "$tmp"

  mv "$tmp" "$meta_file"
  chmod 644 "$meta_file"
}

set_link_status_with_history() {
  local meta_file="$1"
  local status="$2"
  local src="${3:-system}"
  local reason="${4:-}"
  local now
  local tmp

  [ -f "$meta_file" ] || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp)"

  jq \
    --arg status "$status" \
    --arg src "$src" \
    --arg reason "$reason" \
    --arg date "$now" '
    def clean_history:
      if (.status_history | type) == "array" then .status_history else [] end;

    (.status // "active") as $old_status
    | clean_history as $history
    | (
        {
          date: (
            .published_at
            // .created_at
            // .created
            // .date
            // .ts
            // .updated_at
            // ((.actions // [] | map(.date // empty) | first) // $date)
          ),
          status: $old_status,
          src: "system",
          reason: "initial_state"
        }
      ) as $initial
    | (
        {
          date: $date,
          status: $status,
          src: $src
        }
        + (if $reason != "" then {reason: $reason} else {} end)
      ) as $entry
    | .status = $status
    | .status_history = (
        if ($history | length) == 0 then
          if $old_status == $status then [$entry] else [$initial, $entry] end
        else
          ($history | last) as $last
          | if
              ($last != null)
              and (($last.status // "") == $status)
              and (($last.src // "") == $src)
              and (($last.reason // "") == $reason)
            then
              $history
            else
              $history + [$entry]
            end
        end
      )
  ' "$meta_file" > "$tmp"

  mv "$tmp" "$meta_file"
  chmod 644 "$meta_file"
}

uportal_normalize_json_array_arg() {
  local value="${1:-}"

  if printf '%s' "$value" | jq -c -e 'type == "array"' >/dev/null 2>&1; then
    printf '%s' "$value" | jq -c '.'
    return 0
  fi

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf '[]'
    return 0
  fi

  jq -cn --arg value "$value" '
    $value
    | split(",")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(. != ""))
  '
}

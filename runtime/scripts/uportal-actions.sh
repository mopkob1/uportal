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

  if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
    uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
  fi
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

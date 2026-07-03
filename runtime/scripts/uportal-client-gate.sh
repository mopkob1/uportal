#!/usr/bin/env bash

UPORTAL_TOKEN_ROOT="${UPORTAL_TOKEN_ROOT:-/data/files/uportal/user-tokens}"

uportal_client_json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
}

uportal_require_publish_client() {
  local user_token="${1:-}"
  local client_type="${2:-}"
  local client_uid="${3:-}"
  local now
  local file
  local tmp
  local active
  local known_count

  [[ "$user_token" =~ ^[A-Za-z0-9._-]{16,128}$ ]] || {
    uportal_client_json_error "bad user token"
    return 1
  }

  [[ "$client_type" =~ ^(web|plugin)$ ]] || {
    uportal_client_json_error "bad client type"
    return 1
  }

  [[ "$client_uid" =~ ^[A-Za-z0-9._:-]{8,128}$ ]] || {
    uportal_client_json_error "bad client uid"
    return 1
  }

  file="$UPORTAL_TOKEN_ROOT/$user_token.json"
  [ -f "$file" ] || {
    uportal_client_json_error "user token not found"
    return 1
  }

  if jq -e '(.status // "active") != "active"' "$file" >/dev/null 2>&1; then
    uportal_client_json_error "user token is not active"
    return 1
  fi

  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp)"

  jq \
    --arg type "$client_type" \
    --arg uid "$client_uid" \
    --arg now "$now" '
    def normalize_client:
      if type == "string" then
        {uid: .}
      elif type == "object" then
        .
      else
        empty
      end;

    .known_clients = (
      if (.known_clients | type) == "object" then .known_clients else {} end
    )
    | .known_clients[$type] = (
      (.known_clients[$type] // [])
      | map(normalize_client)
      | map(select((.uid // "") != ""))
      | if any((.uid // "") == $uid) then
          map(if (.uid // "") == $uid then (.last_seen = $now) else . end)
        else
          . + [{uid: $uid, first_seen: $now, last_seen: $now}]
        end
    )
    | .active_clients = (
      if (.active_clients | type) == "object" then .active_clients else {} end
    )
    | if ((.active_clients[$type] // "") == "" and (.known_clients[$type] | length) == 1) then
        .active_clients[$type] = $uid
      else
        .
      end
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  chmod 644 "$file"

  active="$(jq -r --arg type "$client_type" '
    def active_list:
      if type == "array" then
        map(tostring | gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))
      elif type == "string" then
        split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))
      else
        []
      end;

    (.active_clients[$type] // []) | active_list | join(",")
  ' "$file" 2>/dev/null || echo "")"
  known_count="$(jq -r --arg type "$client_type" '(.known_clients[$type] // []) | length' "$file" 2>/dev/null || echo "0")"

  if [ -z "$active" ]; then
    jq -cn \
      --arg type "$client_type" \
      --arg count "$known_count" \
      '{status:"error",message:[{text:"active client is not selected",client_type:$type,known_clients:($count|tonumber)}]}'
    return 1
  fi

  if ! printf '%s\n' "$active" | tr ',' '\n' | grep -Fx -- "$client_uid" >/dev/null; then
    jq -cn \
      --arg type "$client_type" \
      --arg uid "$client_uid" \
      --arg active "$active" \
      '{status:"error",message:[{text:"client is not active for publishing",client_type:$type,client_uid:$uid,active_client_uid:$active}]}'
    return 1
  fi

  return 0
}

#!/usr/bin/env bash

UPORTAL_TOKEN_ROOT="${UPORTAL_TOKEN_ROOT:-/data/files/uportal/user-tokens}"
UPORTAL_TOKEN_ENABLED_ROOT="${UPORTAL_TOKEN_ENABLED_ROOT:-/data/files/uportal/user-tokens-enabled}"

uportal_token_safe_re='^[A-Za-z0-9._-]{16,128}$'

uportal_token_is_enabled() {
  local file="$1"

  [ -f "$file" ] || return 1

  jq -e '
    (.status // "active") == "active"
    and (
      (.expires_at // null) == null
      or (.expires_at == "")
      or (
        (.expires_at | fromdateiso8601?) != null
        and (.expires_at | fromdateiso8601) > now
      )
    )
  ' "$file" >/dev/null 2>&1
}

uportal_token_sync_projection() {
  local token="$1"
  local file="$UPORTAL_TOKEN_ROOT/$token.json"
  local enabled_file="$UPORTAL_TOKEN_ENABLED_ROOT/$token.json"

  [[ "$token" =~ $uportal_token_safe_re ]] || return 1

  mkdir -p "$UPORTAL_TOKEN_ENABLED_ROOT"

  if uportal_token_is_enabled "$file"; then
    ln -sfn "../user-tokens/$token.json" "$enabled_file"
    return 0
  fi

  rm -f "$enabled_file"
}

uportal_token_remove_projection() {
  local token="$1"

  [[ "$token" =~ $uportal_token_safe_re ]] || return 1
  rm -f "$UPORTAL_TOKEN_ENABLED_ROOT/$token.json"
}

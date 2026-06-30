#!/usr/bin/env bash

UPORTAL_TOKEN_ROOT="${UPORTAL_TOKEN_ROOT:-/data/files/uportal/user-tokens}"
UPORTAL_USER_ID_SAFE_RE='^[A-Za-z0-9._-]{1,128}$'
UPORTAL_TOKEN_SAFE_RE='^[A-Za-z0-9._-]{16,128}$'

uportal_resolve_user_id() {
  local token="${1:-}"
  local file
  local user_id

  if [[ ! "$token" =~ $UPORTAL_TOKEN_SAFE_RE ]]; then
    printf '%s' "$token"
    return 0
  fi

  file="$UPORTAL_TOKEN_ROOT/$token.json"
  if [ ! -f "$file" ]; then
    printf '%s' "$token"
    return 0
  fi

  user_id="$(jq -r '.user_id // ""' "$file" 2>/dev/null || echo "")"
  if [[ "$user_id" =~ $UPORTAL_USER_ID_SAFE_RE ]]; then
    printf '%s' "$user_id"
    return 0
  fi

  printf '%s' "$token"
}

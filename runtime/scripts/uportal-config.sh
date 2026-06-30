#!/usr/bin/env bash

uportal_source_config_file() {
  local file="$1"

  [ -f "$file" ] || return 0
  # shellcheck disable=SC1090
  . "$file"
}

uportal_load_config() {
  uportal_source_config_file "${UPORTAL_CONFIG_FILE:-}"
  uportal_source_config_file "/etc/uportal/uportal.env"
  uportal_source_config_file "/data/files/uportal/config/uportal.env"
}

uportal_public_base_url() {
  local value="${UPORTAL_PUBLIC_BASE_URL:-${UPORTAL_BASE_URL:-}}"
  value="${value%/}"
  printf '%s' "${value:-http://localhost:8080}"
}

uportal_fallback_url() {
  local value="${UPORTAL_FALLBACK_URL:-}"
  value="${value%/}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s/link-fallback' "$(uportal_public_base_url)"
}

uportal_load_config

#!/usr/bin/env bash
set -euo pipefail

TOKEN="${1:-}"
ROOT="${UPORTAL_TOKEN_ROOT:-/data/files/uportal/user-tokens}"
FILE="$ROOT/$TOKEN.json"

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

[[ "$TOKEN" =~ ^[A-Za-z0-9._-]{16,128}$ ]] || json_error "bad token"
[ -f "$FILE" ] || json_error "token not found"

FILE_CREATED_AT="$(date -u -d "@$(stat -c %Y "$FILE")" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"

jq -cn \
  --arg token "$TOKEN" \
  --arg file_created_at "$FILE_CREATED_AT" \
  --slurpfile payload "$FILE" '
  ($payload[0] // {}) as $p
  | {
      status: "success",
      message: [
        {
          items: [
            {
              token: $token,
              payload: $p,
              user_id: ($p.user_id // $token),
              user: ($p.user // ""),
              scope: ($p.scope // []),
              status: ($p.status // "active"),
              tags: ($p.tags // []),
              created_at: ($p.created_at // $file_created_at),
              known_clients: ($p.known_clients // {}),
              active_clients: ($p.active_clients // {})
            }
          ],
          page: 1,
          limit: 1,
          total: 1,
          has_next: false
        }
      ]
    }'

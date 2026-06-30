#!/usr/bin/env bash
set -euo pipefail

PAGE="${1:-1}"
LIMIT="${2:-50}"
QUERY="${3:-}"

ROOT="${UPORTAL_TOKEN_ROOT:-/data/files/uportal/user-tokens}"
mkdir -p "$ROOT"

[[ "$PAGE" =~ ^[0-9]+$ ]] || PAGE=1
[[ "$LIMIT" =~ ^[0-9]+$ ]] || LIMIT=50

[ "$PAGE" -lt 1 ] && PAGE=1
[ "$LIMIT" -lt 1 ] && LIMIT=50
[ "$LIMIT" -gt 200 ] && LIMIT=200

OFFSET=$(( (PAGE - 1) * LIMIT ))

ROWS="$(
find "$ROOT" -maxdepth 1 -type f -name '*.json' | sort | while read -r file; do
  token="$(basename "$file" .json)"
  file_created_at="$(date -u -d "@$(stat -c %Y "$file")" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"

  jq -c --arg token "$token" --arg file_created_at "$file_created_at" '
    select((.status // "active") != "revoked")
    |
    {
      token: $token,
      payload: .,
      user_id: (.user_id // $token),
      user: (.user // ""),
      scope: (.scope // []),
      status: (.status // "active"),
      tags: (.tags // []),
      created_at: (.created_at // $file_created_at),
      known_clients: (.known_clients // {}),
      active_clients: (.active_clients // {})
    }
  ' "$file" 2>/dev/null || true
done | jq -s .
)"

jq -cn \
  --argjson rows "$ROWS" \
  --arg query "$QUERY" \
  --argjson page "$PAGE" \
  --argjson limit "$LIMIT" \
  --argjson offset "$OFFSET" '
  (
    if ($query | length) > 0 then
      $rows
      | map(select(
          (.token // "" | ascii_downcase | contains($query | ascii_downcase))
          or (.user // "" | ascii_downcase | contains($query | ascii_downcase))
          or ((.scope // []) | join(",") | ascii_downcase | contains($query | ascii_downcase))
          or ((.tags // []) | join(",") | ascii_downcase | contains($query | ascii_downcase))
        ))
    else
      $rows
    end
  ) as $filtered

  | {
      status: "success",
      message: [
        {
          items: ($filtered | .[$offset:($offset + $limit)]),
          page: $page,
          limit: $limit,
          total: ($filtered | length),
          has_next: (($offset + $limit) < ($filtered | length))
        }
      ]
    }
'

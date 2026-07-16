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
    def free_site:
      {
        plan: "free",
        status: "active",
        scope: [
          "ui:access",
          "publications:read",
          "publish:redirect",
          "publish:pixel",
          "publish:page",
          "publish:download",
          "upload:files",
          "activity:read",
          "dictionary:read",
          "plugin:use",
          "clients:manage",
          "account:bind_email",
          "account:bind_telegram",
          "account:recover",
          "publication:freshness",
          "publication:limits",
          "publication:sticky",
          "redirect:rich_page"
        ],
        limits: {
          price_rub_month: 0,
          storage_mb: 10,
          max_upload_file_mb: 25,
          max_publication_files: 20,
          max_publication_payload_mb: 100,
          publication_ttl_days: 7,
          publication_ttl_mode: "fixed_days",
          statistics_ttl_mode: "until_token_revoked_or_deleted",
          fallback_page: true,
          fallback_advertising: "uportal_after_publication_expiration",
          branding: "uportal_locked"
        },
        account: {
          id: (.user_id // $token),
          displayName: (.user // "")
        },
        bindings: {
          email: false,
          telegram: false
        }
      };
    def normalized_site:
      if (.site | type) == "object" then
        free_site
        + .site
        | .limits = (free_site.limits + ((.limits // {}) | if type == "object" then . else {} end))
        | .account = (free_site.account + ((.account // {}) | if type == "object" then . else {} end))
        | .bindings = (free_site.bindings + ((.bindings // {}) | if type == "object" then . else {} end))
      else
        free_site
      end;
    {
      token: $token,
      payload: .,
      user_id: (.user_id // $token),
      user: (.user // ""),
      scope: (.scope // []),
      site: normalized_site,
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

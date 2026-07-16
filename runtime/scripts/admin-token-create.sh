#!/usr/bin/env bash

set -euo pipefail

token="${1:-}"
payload_b64="${2:-}"

if [ -f /usr/local/bin/uportal-token-projection.sh ]; then
  source /usr/local/bin/uportal-token-projection.sh
else
  source "$(dirname "$0")/uportal-token-projection.sh"
fi
BASE="$UPORTAL_TOKEN_ROOT"

json_error() {
  jq -n --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

gen_token() {
  while true; do
    local t
    t="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
    [ ${#t} -eq 32 ] || continue
    [ ! -e "$BASE/$t.json" ] || continue
    printf '%s' "$t"
    return
  done
}

mkdir -p "$BASE"

if [ -z "$token" ]; then
  token="$(gen_token)"
else
  printf '%s' "$token" | grep -Eq '^[A-Za-z0-9._-]{16,128}$' \
    || json_error "invalid token format"
fi

[ -n "$payload_b64" ] || json_error "missing required field: payload_b64"

payload_raw="$(printf '%s' "$payload_b64" | base64 -d 2>/dev/null || true)"
[ -n "$payload_raw" ] || json_error "payload_b64 is not valid base64"

printf '%s' "$payload_raw" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || json_error "decoded payload must be a JSON object"

tmp="$(mktemp)"
file="$BASE/$token.json"
now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

existing_user_id=""
if [ -f "$file" ]; then
  existing_user_id="$(jq -r '.user_id // ""' "$file" 2>/dev/null || echo "")"
fi

printf '%s' "$payload_raw" | jq -c \
  --arg token "$token" \
  --arg now "$now" \
  --arg existing_user_id "$existing_user_id" '
  .created_at = (.created_at // $now)
  |
  .user_id = (
    (.user_id // "") as $user_id
    | if ($user_id | test("^[A-Za-z0-9._-]{1,128}$")) then $user_id
      elif ($existing_user_id | test("^[A-Za-z0-9._-]{1,128}$")) then $existing_user_id
      else $token
      end
  )
  |
  .site = (
    if (.site | type) == "object" then
      .site
      | .plan = (.plan // "free")
      | .scope = (
          if (.scope | type) == "array" then .scope
          else [
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
          ]
          end
        )
      | .limits = ({
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
        } + ((.limits // {}) | if type == "object" then . else {} end))
      | .account = ({
          id: (.account.id // $token),
          displayName: (.account.displayName // "")
        } + ((.account // {}) | if type == "object" then . else {} end))
      | .bindings = ({
          email: false,
          telegram: false
        } + ((.bindings // {}) | if type == "object" then . else {} end))
    else
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
      }
    end
  )
' > "$tmp"
mv "$tmp" "$file"
chmod 644 "$file"
uportal_token_sync_projection "$token"

jq -n \
  --arg token "$token" \
  --slurpfile payload "$file" '
  {
    status: "success",
    message: [
      {
        operation: "token_create",
        token: $token,
        token_file: ("/data/files/uportal/user-tokens/" + $token + ".json"),
        payload: $payload[0]
      }
    ]
  }
'

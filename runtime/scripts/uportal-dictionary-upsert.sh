#!/usr/bin/env bash
set -euo pipefail

USER_TOKEN="${1:-}"
ID="${2:-}"
PRE="${3:-}"
POST="${4:-}"
URL="${5:-}"
ANCHOR="${6:-}"
TYPE="${7:-redirect}"
TAGS="${8:-}"

ROOT="/data/files/uportal"
DICT_ROOT="$ROOT/dictionaries"

if [ -f /usr/local/bin/uportal-user-identity.sh ]; then
  source /usr/local/bin/uportal-user-identity.sh
else
  source "$(dirname "$0")/uportal-user-identity.sh"
fi

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

safe_token_re='^[A-Za-z0-9._-]{16,128}$'
safe_id_re='^[A-Za-z0-9._-]{1,128}$'

[[ "$USER_TOKEN" =~ $safe_token_re ]] || json_error "bad or missing user token"
[[ "$TYPE" == "redirect" || "$TYPE" == "pixel" ]] || json_error "type must be redirect or pixel"
[[ -n "$ANCHOR" ]] || json_error "anchor is required"

if [[ "$TYPE" == "redirect" && -z "$URL" ]]; then
  json_error "url is required for redirect"
fi

if [[ -n "$ID" && ! "$ID" =~ $safe_id_re ]]; then
  json_error "bad id"
fi

mkdir -p "$DICT_ROOT"
chmod 700 "$DICT_ROOT"

USER_ID="$(uportal_resolve_user_id "$USER_TOKEN")"
DICT_FILE="$DICT_ROOT/$USER_ID.json"
LOCK_FILE="$DICT_ROOT/$USER_ID.lock"

if [ ! -f "$DICT_FILE" ]; then
  printf '[]\n' > "$DICT_FILE"
  chmod 600 "$DICT_FILE"
fi

jq -e 'type == "array"' "$DICT_FILE" >/dev/null 2>&1 || json_error "dictionary file is corrupted"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [ -z "$ID" ]; then
  ID="$(printf '%s:%s:%s:%s' "$USER_ID" "$URL" "$ANCHOR" "$NOW" | sha256sum | cut -c1-12)"
fi

TMP="$(mktemp)"

(
  flock -x 200

  jq \
    --arg id "$ID" \
    --arg pre "$PRE" \
    --arg post "$POST" \
    --arg url "$URL" \
    --arg anchor "$ANCHOR" \
    --arg type "$TYPE" \
    --arg tags "$TAGS" \
    --arg now "$NOW" '
      def new_item:
        {
          id: $id,
          pre: $pre,
          post: $post,
          url: $url,
          anchor: $anchor,
          type: $type,
          tags: $tags,
          updated_at: $now
        };

      if any(.[]; .id == $id) then
        map(
          if .id == $id then
            . + new_item + {created_at: (.created_at // $now)}
          else
            .
          end
        )
      else
        . + [new_item + {created_at: $now}]
      end
    ' "$DICT_FILE" > "$TMP"

  mv "$TMP" "$DICT_FILE"
  chmod 600 "$DICT_FILE"
) 200>"$LOCK_FILE"

jq -cn \
  --arg id "$ID" \
  '{
    status:"success",
    message:[
      {
        text:"dictionary item saved",
        id:$id
      }
    ]
  }'

#!/usr/bin/env bash
set -euo pipefail

OP="${1:-upsert}"
PUBLICATION_ID="${2:-}"
TOKEN="${3:-}"
ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
META_ROOT="$ROOT/meta"
INDEX_ROOT="$ROOT/index/links/by-user"
COMPACT_THRESHOLD="${UPORTAL_LINKS_INDEX_COMPACT_THRESHOLD:-5000}"
META_FILE="$META_ROOT/$PUBLICATION_ID/$TOKEN.json"
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$(dirname "$0")/uportal-config.sh"
fi

safe_user_id_re='^[A-Za-z0-9._-]{1,128}$'
safe_part_re='^[A-Za-z0-9._-]+$'

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

[[ "$OP" == "upsert" || "$OP" == "delete" ]] || json_error "bad op"
[[ "$PUBLICATION_ID" =~ $safe_part_re ]] || json_error "bad publication"
[[ "$TOKEN" =~ $safe_part_re ]] || json_error "bad token"

mkdir -p "$INDEX_ROOT" "$INDEX_ROOT/.locks"

compact_user_index() {
  local index_file="$1"
  local force="${2:-0}"
  local line_count
  local tmp

  [ -f "$index_file" ] || return 0
  [[ "$COMPACT_THRESHOLD" =~ ^[0-9]+$ ]] || return 0
  [ "$COMPACT_THRESHOLD" -gt 0 ] || return 0

  line_count="$(wc -l < "$index_file" 2>/dev/null | tr -d '[:space:]' || echo 0)"
  [[ "$line_count" =~ ^[0-9]+$ ]] || return 0
  if [ "$force" != "1" ] && [ "$line_count" -lt "$COMPACT_THRESHOLD" ]; then
    return 0
  fi

  tmp="$(mktemp "$INDEX_ROOT/.compact.XXXXXX")"
  if jq -s -c '
    map(select(type == "object"))
    | sort_by(.indexed_at // "")
    | reduce .[] as $row (
        {};
        ($row.publication_id // "") as $publication_id
        | ($row.token // "") as $token
        | if $publication_id == "" or $token == "" then
            .
          elif ($row.op // "upsert") == "delete" then
            del(.[$publication_id + ":" + $token])
          else
            .[$publication_id + ":" + $token] = $row
          end
      )
    | [.[]]
    | sort_by(.indexed_at // "")
    | .[]
  ' "$index_file" > "$tmp"; then
    mv "$tmp" "$index_file"
    chmod 644 "$index_file"
  else
    rm -f "$tmp"
  fi
}

append_for_user() {
  local user_id="$1"
  local line="$2"
  local index_file
  local lock_file
  local force_compact=0

  [[ "$user_id" =~ $safe_user_id_re ]] || return 0
  index_file="$INDEX_ROOT/$user_id.jsonl"
  lock_file="$INDEX_ROOT/.locks/$user_id.lock"
  if printf '%s' "$line" | jq -e '(.op // "") == "delete"' >/dev/null 2>&1; then
    force_compact=1
  fi

  (
    flock 7
    printf '%s\n' "$line" >> "$index_file"
    chmod 644 "$index_file"
    compact_user_index "$index_file" "$force_compact"
  ) 7>"$lock_file"
}

if [ "$OP" = "delete" ]; then
  TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [ -f "$META_FILE" ]; then
    jq -c \
      --arg op "delete" \
      --arg ts "$TS" \
      --arg publication_id "$PUBLICATION_ID" \
      --arg token "$TOKEN" '
      (.actions // [] | map(.actor // "") | unique | map(select(. != ""))) as $actors
      | {
          op: $op,
          indexed_at: $ts,
          publication_id: $publication_id,
          token: $token,
          actors: $actors
        }
    ' "$META_FILE" | while IFS= read -r line; do
      printf '%s' "$line" | jq -r '.actors[]?' | while IFS= read -r actor; do
        append_for_user "$actor" "$line"
      done
    done
  fi

  jq -cn --arg op "$OP" --arg publication_id "$PUBLICATION_ID" --arg token "$TOKEN" \
    '{status:"success",message:[{op:$op,publication_id:$publication_id,token:$token}]}'
  exit 0
fi

[ -f "$META_FILE" ] || json_error "meta not found"

BASE_URL="$(uportal_public_base_url)"
jq -c \
  --arg op "$OP" \
  --arg indexed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg base_url "$BASE_URL" '
  (.actions // [] | sort_by(.date // "")) as $actions
  | ($actions | last) as $last_action_any
  | ($actions | map(.date // empty) | first) as $first_action_date
  | ($actions | map(.actor // "") | unique | map(select(. != ""))) as $actors
  | (.created_at // .created // .date // .ts // .updated_at // ($last_action_any.date // "")) as $row_date
  | (.published_at // .created_at // .created // .date // .ts // $first_action_date // $row_date) as $published_at
  | {
      op: $op,
      indexed_at: $indexed_at,
      publication_id: (.publication_id // ""),
      token: (.token // ""),
      type: (.type // ""),
      status: (.status // "active"),
      short_id: (.short_id // .short // ""),
      short_url: (
        if ((.short_id // .short // "") != "")
        then ($base_url + "/s/" + (.short_id // .short))
        else ""
        end
      ),
      image: (.image // ""),
      title: (.title // ""),
      description: (.description // ""),
      subj: (.subj // ""),
      mails: (.mails // []),
      pre: (.pre // ""),
      link: (.link // ""),
      post: (.post // ""),
      target_url: (.target_url // ""),
      sticky: (.sticky // false),
      password_protected: ((.password_hash // "") != ""),
      fresh_until: (.fresh_until // -1),
      remaining_clicks: (.remaining_clicks // -1),
      delay: (
        (.delay // 0) as $delay
        | if ($delay | tostring | test("^-?[0-9]+$"))
          then (($delay | tonumber) | if . < 0 then 0 else . end)
          else 0
          end
      ),
      fallback_url: (.fallback_url // ""),
      date: $row_date,
      published_at: $published_at,
      last_action: $last_action_any,
      actors: $actors,
      search_text: (
        [
          .publication_id,
          .token,
          .type,
          .status,
          .short_id,
          .short,
          .subj,
          .title,
          .description,
          .pre,
          .link,
          .post,
          .target_url,
          .fallback_url
        ]
        + (.mails // [])
        | map(. // "" | tostring)
        | join(" ")
      )
    }
' "$META_FILE" | while IFS= read -r line; do
  printf '%s' "$line" | jq -r '.actors[]?' | while IFS= read -r actor; do
    append_for_user "$actor" "$line"
  done
done

jq -cn --arg op "$OP" --arg publication_id "$PUBLICATION_ID" --arg token "$TOKEN" \
  '{status:"success",message:[{op:$op,publication_id:$publication_id,token:$token}]}'

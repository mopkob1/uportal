#!/usr/bin/env bash
set -euo pipefail

USER_TOKEN="${1:-}"
PUB_FILTER="${2:-}"
TYPE_FILTER="${3:-}"
STATUS_FILTER="${4:-}"
LIMIT="${5:-100}"
OFFSET="${6:-0}"
QUERY="${7:-}"
FROM="${8:-}"
TO="${9:-}"
MODE="${10:-}"

ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
META_ROOT="$ROOT/meta"
STORAGE_ROOT="$ROOT/storage"
INBOX_ROOT="${UPORTAL_INBOX_ROOT:-/data/files/inbox}"
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$(dirname "$0")/uportal-config.sh"
fi
BASE_URL="$(uportal_public_base_url)"
RECENT_META_MINUTES="${UPORTAL_LINKS_RECENT_META_MINUTES:-1440}"

if [ -z "$USER_TOKEN" ]; then
  jq -n '{status:"error",message:["user_token is required"]}'
  exit 1
fi

if [ -f /usr/local/bin/uportal-user-identity.sh ]; then
  source /usr/local/bin/uportal-user-identity.sh
else
  source "$(dirname "$0")/uportal-user-identity.sh"
fi

USER_TOKEN="$(uportal_resolve_user_id "$USER_TOKEN")"
INDEX_FILE="$ROOT/index/links/by-user/$USER_TOKEN.jsonl"

case "$LIMIT" in
  ''|*[!0-9]*) LIMIT=100 ;;
esac

case "$OFFSET" in
  ''|*[!0-9]*) OFFSET=0 ;;
esac

TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT

if [ -f "$INDEX_FILE" ]; then
  jq -s -c \
    --arg type_filter "$TYPE_FILTER" \
    --arg status_filter "$STATUS_FILTER" \
    --arg pub_filter "$PUB_FILTER" \
    --arg query "$QUERY" \
    --arg from "$FROM" \
    --arg to "$TO" '
    def text_match($text; $query):
      $query == ""
      or ($text | contains($query))
      or ($text | ascii_downcase | contains($query | ascii_downcase));

    map(select(type == "object"))
    | sort_by(.indexed_at // "")
    | reduce .[] as $row (
        {};
        ($row.publication_id // "") as $pub
        | ($row.token // "") as $tok
        | if $pub == "" or $tok == "" then .
          elif ($row.op // "upsert") == "delete" then del(.[$pub + ":" + $tok])
          else .[$pub + ":" + $tok] = ($row + {created_by_user: true})
          end
      )
    | [.[]]
    | map(
        (.date // .last_action.date // "") as $row_date
        | select($pub_filter == "" or (.publication_id // "") == $pub_filter)
        | select($type_filter == "" or (.type // "") == $type_filter)
        | select($status_filter == "" or (.status // "active") == $status_filter)
        | select($from == "" or $row_date >= $from)
        | select($to == "" or $row_date <= $to)
        | select(text_match((.search_text // ""); $query))
        | del(.op, .indexed_at, .actors, .search_text)
      )
    | .[]
  ' "$INDEX_FILE" > "$TMP_LIST"

  if [ -d "$META_ROOT" ]; then
    if [[ "$RECENT_META_MINUTES" =~ ^[0-9]+$ ]] && [ "$RECENT_META_MINUTES" -gt 0 ]; then
      find "$META_ROOT" -type f -name '*.json' \( -newer "$INDEX_FILE" -o -mmin "-$RECENT_META_MINUTES" \) -print0 2>/dev/null
    else
      find "$META_ROOT" -type f -name '*.json' -newer "$INDEX_FILE" -print0 2>/dev/null
    fi \
    | while IFS= read -r -d '' file; do
        jq -c \
          --arg actor "$USER_TOKEN" \
          --arg base_url "$BASE_URL" '
          ([.actions[]? | select(.actor == $actor)] | sort_by(.date) | last) as $last_action
          | (.actions // [] | map(.date // empty) | first) as $first_action_date
          | select($last_action != null)
          | ($last_action.date // .created_at // .created // .date // .ts // .updated_at // "") as $row_date
          | (.published_at // .created_at // .created // .date // .ts // $first_action_date // $row_date) as $published_at
          | {
              publication_id,
              token,
              type,
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
              pre: (if (.pre // "") != "" then .pre else (([.actions[]? | select(.actor == $actor and (.details.pre // "") != "")] | sort_by(.date) | last | .details.pre) // "") end),
              link: (if (.link // "") != "" then .link else (([.actions[]? | select(.actor == $actor and (.details.link // "") != "")] | sort_by(.date) | last | .details.link) // "") end),
              post: (if (.post // "") != "" then .post else (([.actions[]? | select(.actor == $actor and (.details.post // "") != "")] | sort_by(.date) | last | .details.post) // "") end),
              target_url: (if (.target_url // "") != "" then .target_url else (([.actions[]? | select(.actor == $actor and (.details.target_url // "") != "")] | sort_by(.date) | last | .details.target_url) // "") end),
              sticky: (.sticky // false),
              telegram_notify: (.telegram_notify // false),
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
              created_by_user: true,
              last_action: $last_action
            }
        ' "$file" 2>/dev/null || true
      done >> "$TMP_LIST"
  fi

  if [ "$MODE" = "campaigns" ]; then
    jq -s \
      --argjson limit "$LIMIT" \
      --argjson offset "$OFFSET" '
      def campaign_key:
        [
          (.publication_id // ""),
          (.subj // ""),
          ((.mails // []) | sort | join(","))
        ] | @json;
      def link_key:
        [
          (.publication_id // ""),
          (.token // ""),
          (.short_id // .short // .short_url // "")
        ] | @json;
      def dedupe_links:
        map(select(type == "object"))
        | sort_by(.date // .last_action.date // "")
        | reduce .[] as $row (
            {};
            ($row | link_key) as $key
            | if $key == "[\"\",\"\",\"\"]" then . else .[$key] = $row end
          )
        | [.[]];

      dedupe_links
      | sort_by(campaign_key)
      | group_by(campaign_key)
      | map({
          key: (.[0] | campaign_key),
          publication_id: (.[0].publication_id // ""),
          subj: (.[0].subj // "Без темы"),
          mails: (.[0].mails // []),
          links: (sort_by(.published_at // .date // .last_action.date // "") | reverse),
          links_count: length,
          types: (map(.type // "") | map(select(. != "")) | unique),
          date: (map(.published_at // .date // .last_action.date // "") | map(select(. != "")) | sort | .[0] // "")
        })
      | sort_by(.date // "") | reverse
      | . as $all
      | {
          status: "success",
          message: ($all[$offset:($offset + $limit)]),
          meta: {
            mode: "campaigns",
            source: "index",
            limit: $limit,
            offset: $offset,
            count: ($all | length)
          }
        }
      ' "$TMP_LIST"
  else
    jq -s \
      --argjson limit "$LIMIT" \
      --argjson offset "$OFFSET" '
      def link_key:
        [
          (.publication_id // ""),
          (.token // ""),
          (.short_id // .short // .short_url // "")
        ] | @json;
      def dedupe_links:
        map(select(type == "object"))
        | sort_by(.date // .last_action.date // "")
        | reduce .[] as $row (
            {};
            ($row | link_key) as $key
            | if $key == "[\"\",\"\",\"\"]" then . else .[$key] = $row end
          )
        | [.[]];

      dedupe_links
      | sort_by(.last_action.date // .date // "") | reverse
      | . as $all
      | {
          status: "success",
          message: ($all[$offset:($offset + $limit)]),
          meta: {
            mode: "links",
            source: "index",
            limit: $limit,
            offset: $offset,
            count: ($all | length)
          }
        }
      ' "$TMP_LIST"
  fi
  exit 0
fi

if [ -n "$PUB_FILTER" ]; then
  SEARCH_ROOT="$META_ROOT/$PUB_FILTER"
else
  SEARCH_ROOT="$META_ROOT"
fi

if [ ! -d "$SEARCH_ROOT" ]; then
  jq -n \
    --argjson limit "$LIMIT" \
    --argjson offset "$OFFSET" \
    '{status:"success",message:[],meta:{limit:$limit,offset:$offset,count:0}}'
  exit 0
fi

find "$SEARCH_ROOT" -type f -name '*.json' -print0 \
| while IFS= read -r -d '' file; do
    publication_id="$(jq -r '.publication_id // ""' "$file" 2>/dev/null || echo "")"
    token="$(jq -r '.token // ""' "$file" 2>/dev/null || echo "")"
    image="$(jq -r '.image // ""' "$file" 2>/dev/null || echo "")"
    preview_url=""

    if [ -n "$publication_id" ] && [ -n "$token" ] && [ -n "$image" ]; then
      if [ -f "$STORAGE_ROOT/$publication_id/$token/payload/$image" ] || [ -f "$INBOX_ROOT/$publication_id/$token/$image" ]; then
        preview_url="$BASE_URL/assets-public/$publication_id/$token/$image"
      fi
    fi

    jq -c \
      --arg actor "$USER_TOKEN" \
      --arg type_filter "$TYPE_FILTER" \
      --arg status_filter "$STATUS_FILTER" \
      --arg query "$QUERY" \
      --arg from "$FROM" \
      --arg to "$TO" \
      --arg base_url "$BASE_URL" \
      --arg preview_url "$preview_url" '
      def text_match($text; $query):
        $query == ""
        or ($text | contains($query))
        or ($text | ascii_downcase | contains($query | ascii_downcase));

      select((.actions // [] | map(select(.actor == $actor)) | length) > 0)
      | select($type_filter == "" or .type == $type_filter)
      | select($status_filter == "" or (.status // "active") == $status_filter)
      | ([.actions[]? | select(.actor == $actor)] | sort_by(.date) | last) as $last_action
      | ($last_action.date // .created_at // .created // .date // .ts // .updated_at // "") as $row_date
      | select($from == "" or $row_date >= $from)
      | select($to == "" or $row_date <= $to)
      | (
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
          + [($last_action.details.pre // ""), ($last_action.details.link // ""), ($last_action.details.post // ""), ($last_action.details.target_url // "")]
          | map(. // "" | tostring)
          | join(" ")
        ) as $haystack
      | select(text_match($haystack; $query))
      | {
          publication_id,
          token,
          type,
          status: (.status // "active"),
          short_id: (.short_id // .short // ""),
          short_url: (
            if ((.short_id // .short // "") != "")
            then ($base_url + "/s/" + (.short_id // .short))
            else ""
            end
          ),
          preview_url: $preview_url,
          image: (.image // ""),
          title: (.title // ""),
          description: (.description // ""),
          subj: (.subj // ""),
          mails: (.mails // []),
          pre: (if (.pre // "") != "" then .pre else (([.actions[]? | select(.actor == $actor and (.details.pre // "") != "")] | sort_by(.date) | last | .details.pre) // "") end),
          link: (if (.link // "") != "" then .link else (([.actions[]? | select(.actor == $actor and (.details.link // "") != "")] | sort_by(.date) | last | .details.link) // "") end),
          post: (if (.post // "") != "" then .post else (([.actions[]? | select(.actor == $actor and (.details.post // "") != "")] | sort_by(.date) | last | .details.post) // "") end),
          target_url: (if (.target_url // "") != "" then .target_url else (([.actions[]? | select(.actor == $actor and (.details.target_url // "") != "")] | sort_by(.date) | last | .details.target_url) // "") end),
          sticky: (.sticky // false),
          telegram_notify: (.telegram_notify // false),
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
              published_at: (.published_at // .created_at // .created // .date // .ts // ((.actions // [] | map(.date // empty) | first) // ($last_action.date // ""))),
              date: $row_date,
          created_by_user: true,
          last_action: $last_action
        }
      ' "$file" 2>/dev/null || true
  done > "$TMP_LIST"

if [ "$MODE" = "campaigns" ]; then
  jq -s \
    --argjson limit "$LIMIT" \
    --argjson offset "$OFFSET" '
    def campaign_key:
      [
        (.publication_id // ""),
        (.subj // ""),
        ((.mails // []) | sort | join(","))
      ] | @json;
    def link_key:
      [
        (.publication_id // ""),
        (.token // ""),
        (.short_id // .short // .short_url // "")
      ] | @json;
    def dedupe_links:
      map(select(type == "object"))
      | sort_by(.date // .last_action.date // "")
      | reduce .[] as $row (
          {};
          ($row | link_key) as $key
          | if $key == "[\"\",\"\",\"\"]" then . else .[$key] = $row end
        )
      | [.[]];

    dedupe_links
    | sort_by(campaign_key)
    | group_by(campaign_key)
    | map({
        key: (.[0] | campaign_key),
        publication_id: (.[0].publication_id // ""),
        subj: (.[0].subj // "Без темы"),
        mails: (.[0].mails // []),
        links: (sort_by(.published_at // .date // .last_action.date // "") | reverse),
        links_count: length,
        types: (map(.type // "") | map(select(. != "")) | unique),
        date: (map(.published_at // .date // .last_action.date // "") | map(select(. != "")) | sort | .[0] // "")
      })
    | sort_by(.date // "") | reverse
    | . as $all
    | {
        status: "success",
        message: ($all[$offset:($offset + $limit)]),
        meta: {
          mode: "campaigns",
          limit: $limit,
          offset: $offset,
          count: ($all | length)
        }
      }
    ' "$TMP_LIST"
else
  jq -s \
    --argjson limit "$LIMIT" \
    --argjson offset "$OFFSET" '
    def link_key:
      [
        (.publication_id // ""),
        (.token // ""),
        (.short_id // .short // .short_url // "")
      ] | @json;
    def dedupe_links:
      map(select(type == "object"))
      | sort_by(.date // .last_action.date // "")
      | reduce .[] as $row (
          {};
          ($row | link_key) as $key
          | if $key == "[\"\",\"\",\"\"]" then . else .[$key] = $row end
        )
      | [.[]];

    dedupe_links
    | sort_by(.last_action.date // .date // "") | reverse
    | . as $all
    | {
        status: "success",
        message: ($all[$offset:($offset + $limit)]),
        meta: {
          mode: "links",
          limit: $limit,
          offset: $offset,
          count: ($all | length)
        }
      }
    ' "$TMP_LIST"
fi

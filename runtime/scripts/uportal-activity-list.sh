#!/usr/bin/env bash
set -euo pipefail

USER_TOKEN="${1:-}"
TYPE="${2:-}"
PUBLICATION_ID="${3:-}"
PUBLICATION="${4:-}"
LINK_TOKEN="${5:-}"
EVENT="${6:-}"
UID_FILTER="${7:-}"
PAGE="${8:-1}"
LIMIT="${9:-50}"
FROM="${10:-}"
TO="${11:-}"
SORT_ORDER="${12:-desc}"

PUB="${PUBLICATION_ID:-$PUBLICATION}"

ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
EVENTS_ROOT="$ROOT/events"
RAW_DIR="$EVENTS_ROOT/raw"
USER_TOKEN_ROOT="$ROOT/user-tokens"
BY_USER_DIR="$EVENTS_ROOT/by-user"
ACTIVITY_INDEX_ROOT="$EVENTS_ROOT/index/by-user"
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$(dirname "$0")/uportal-config.sh"
fi
PUBLIC_BASE_URL="$(uportal_public_base_url)"

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
[[ "$USER_TOKEN" =~ $safe_token_re ]] || json_error "bad or missing user token"

TOKEN_FILE="$USER_TOKEN_ROOT/$USER_TOKEN.json"
[[ -f "$TOKEN_FILE" ]] || json_error "user token not found"

# Old format: status=active
# New format: scope contains admin or activity
if ! jq -e '
  (.status // "") == "active"
  or ((.scope // []) | index("admin") != null)
  or ((.scope // []) | index("activity") != null)
' "$TOKEN_FILE" >/dev/null; then
  json_error "user token inactive"
fi

RAW_USER_TOKEN="$USER_TOKEN"
USER_TOKEN="$(uportal_resolve_user_id "$USER_TOKEN")"

PAGE="${PAGE:-1}"
LIMIT="${LIMIT:-50}"

[[ "$PAGE" =~ ^[0-9]+$ ]] || PAGE=1
[[ "$LIMIT" =~ ^[0-9]+$ ]] || LIMIT=50

if (( PAGE < 1 )); then PAGE=1; fi
if (( LIMIT < 1 )); then LIMIT=50; fi
if (( LIMIT > 500 )); then LIMIT=500; fi

safe_part_re='^[A-Za-z0-9._-]+$'

[[ -z "$TYPE" || "$TYPE" =~ ^[a-z_,]+$ ]] || json_error "bad type"
[[ -z "$PUB" || "$PUB" =~ $safe_part_re ]] || json_error "bad publication"
[[ -z "$LINK_TOKEN" || "$LINK_TOKEN" =~ ^[A-Za-z0-9._,-]+$ ]] || json_error "bad token"
[[ -z "$EVENT" || "$EVENT" =~ ^[a-z_,]+$ ]] || json_error "bad event"
[[ -z "$UID_FILTER" || "$UID_FILTER" =~ $safe_part_re ]] || json_error "bad uid"
[[ -z "$SORT_ORDER" || "$SORT_ORDER" =~ ^(asc|desc|ascend|descend)$ ]] || json_error "bad sort order"

case "$SORT_ORDER" in
  asc|ascend) SORT_ORDER="asc" ;;
  *) SORT_ORDER="desc" ;;
esac

TMP="$(mktemp)"
TMP_USER="$(mktemp)"
TMP_PAGE="$(mktemp)"
TMP_MATCHED="$(mktemp)"
TMP_ENRICHED_DIR="$(mktemp -d)"
TMP_ENRICHED_LIST="$(mktemp)"

cleanup() {
  rm -f "$TMP" "$TMP_USER" "$TMP_PAGE" "$TMP_MATCHED" "$TMP_ENRICHED_LIST"
  rm -rf "$TMP_ENRICHED_DIR"
}

on_error() {
  local code="$?"
  cleanup
  jq -cn \
    --arg code "$code" \
    '{status:"error",message:[{text:"activity list failed",code:($code|tonumber)}]}'
  exit 0
}

trap cleanup EXIT
trap on_error ERR

OFFSET=$(( (PAGE - 1) * LIMIT ))
FAST_TOTAL="-1"
SORT_CMD=(sort -r)
if [ "$SORT_ORDER" = "asc" ]; then
  SORT_CMD=(sort)
fi

ACTIVITY_INDEX_FILE="$ACTIVITY_INDEX_ROOT/$USER_TOKEN.jsonl"
ACTIVITY_INDEX_READY=0
if [ -f "$ACTIVITY_INDEX_ROOT/.ready" ] || [ -f "$ACTIVITY_INDEX_ROOT/.ready-$USER_TOKEN" ]; then
  ACTIVITY_INDEX_READY=1
fi

if [ "${UPORTAL_ACTIVITY_INDEX_DISABLE:-0}" != "1" ] && [ "$ACTIVITY_INDEX_READY" = "1" ] && [ -f "$ACTIVITY_INDEX_FILE" ]; then
  jq -s \
    --argjson page "$PAGE" \
    --argjson limit "$LIMIT" \
    --argjson offset "$OFFSET" \
    --arg user_token "$USER_TOKEN" \
    --arg raw_user_token "$RAW_USER_TOKEN" \
    --arg type "$TYPE" \
    --arg pub "$PUB" \
    --arg link_token "$LINK_TOKEN" \
    --arg event "$EVENT" \
    --arg uid "$UID_FILTER" \
    --arg from "$FROM" \
    --arg to "$TO" \
    --arg sort_order "$SORT_ORDER" '
    def csv_list($value):
      if $value == "" then []
      else ($value | split(",") | map(select(. != "")))
      end;

    def allowed_actor:
      (.meta.actor // "") == $user_token
      or (.meta.created_by // "") == $user_token
      or (.meta.actor // "") == $raw_user_token
      or (.meta.created_by // "") == $raw_user_token;

    def allowed_type:
      . as $row
      | (csv_list($type)) as $types
      | ($types | length) == 0
        or (($types | index($row.meta.type // "")) != null);

    def allowed_event:
      . as $row
      | (csv_list($event)) as $events
      | ($events | length) == 0
        or (($events | index($row.event // "")) != null);

    map(select(type == "object"))
    | map(select(allowed_actor))
    | map(select(allowed_type))
    | map(select($pub == "" or (.publication // .publication_id // "") == $pub))
    | map(select($link_token == "" or (. as $row | (csv_list($link_token) | index($row.token // "")) != null)))
    | map(select(allowed_event))
    | map(select($uid == "" or (.uid // "") == $uid))
    | map(select($from == "" or (.ts // .created_at // "") >= $from))
    | map(select($to == "" or (.ts // .created_at // "") <= $to))
    | sort_by(.ts // .created_at // "")
    | if $sort_order == "asc" then . else reverse end
    | . as $all
    | ($all | length) as $total
    | {
        status: "success",
        message: [
          {
            page: $page,
            limit: $limit,
            total: $total,
            has_next: (($offset + $limit) < $total),
            items: $all[$offset:($offset + $limit)]
          }
        ]
      }
  ' "$ACTIVITY_INDEX_FILE"
  exit 0
fi

if [[ -n "$PUB" && -n "$LINK_TOKEN" ]]; then
  if [[ "$LINK_TOKEN" == *,* ]]; then
    find "$EVENTS_ROOT/by-pub" -maxdepth 1 -type l -name "${PUB}_*.json" 2>/dev/null > "$TMP" || true
  else
    find "$EVENTS_ROOT/by-link" -maxdepth 1 -type l -name "${PUB}_${LINK_TOKEN}_*.json" 2>/dev/null > "$TMP" || true
  fi
  if [ ! -s "$TMP" ]; then
    find "$EVENTS_ROOT/by-pub" -maxdepth 1 -type l -name "${PUB}_*.json" 2>/dev/null > "$TMP" || true
  fi
  if [ ! -s "$TMP" ]; then
    find "$BY_USER_DIR" -maxdepth 1 -type l -name "${USER_TOKEN}_*.json" 2>/dev/null > "$TMP" || true
  fi
elif [[ -n "$PUB" ]]; then
  find "$EVENTS_ROOT/by-pub" -maxdepth 1 -type l -name "${PUB}_*.json" 2>/dev/null > "$TMP" || true
  if [ ! -s "$TMP" ]; then
    find "$BY_USER_DIR" -maxdepth 1 -type l -name "${USER_TOKEN}_*.json" 2>/dev/null > "$TMP" || true
  fi
elif [[ -n "$EVENT" && "$EVENT" != *,* ]]; then
  find "$EVENTS_ROOT/by-event" -maxdepth 1 -type l -name "${EVENT}_*.json" 2>/dev/null > "$TMP" || true
elif [[ -n "$UID_FILTER" ]]; then
  find "$EVENTS_ROOT/by-uid" -maxdepth 1 -type l -name "${UID_FILTER}_*.json" 2>/dev/null > "$TMP" || true
else
  find "$BY_USER_DIR" -maxdepth 1 -type l -name "${USER_TOKEN}_*.json" 2>/dev/null > "$TMP_USER" || true
  if [ -s "$TMP_USER" ]; then
    if [ -z "$TYPE" ] && [ -z "$PUB" ] && [ -z "$LINK_TOKEN" ] && [ -z "$EVENT" ] && [ -z "$UID_FILTER" ] && [ -z "$FROM" ] && [ -z "$TO" ]; then
      FAST_TOTAL="$(wc -l < "$TMP_USER" | tr -d ' ')"
      while IFS= read -r event_file; do
        [ -f "$event_file" ] || continue
        event_ts="$(jq -r '.ts // .created_at // ""' "$event_file" 2>/dev/null || true)"
        [ -n "$event_ts" ] || continue
        printf '%s\t%s\n' "$event_ts" "$event_file"
      done < "$TMP_USER" \
        | "${SORT_CMD[@]}" \
        | awk -v offset="$OFFSET" -v limit="$LIMIT" 'NR > offset && NR <= offset + limit { sub(/^[^\t]*\t/, ""); print }' \
        > "$TMP_PAGE"
      cp "$TMP_PAGE" "$TMP"
    else
      cp "$TMP_USER" "$TMP"
    fi
  else
    find "$RAW_DIR" -maxdepth 1 -type f -name "*.json" 2>/dev/null > "$TMP" || true
  fi
fi

if [ "$FAST_TOTAL" = "-1" ]; then
  while IFS= read -r event_file; do
    [ -f "$event_file" ] || continue

    event_snapshot="$(jq -r '
      [
        (.ts // .created_at // ""),
        (.event // ""),
        (.publication // .publication_id // ""),
        (.token // ""),
        (.uid // ""),
        (.meta.type // ""),
        (.meta.actor // ""),
        (.meta.created_by // "")
      ] | @tsv
    ' "$event_file" 2>/dev/null || true)"
    [ -n "$event_snapshot" ] || continue

    IFS=$'\t' read -r event_ts event_name event_pub event_token event_uid event_type event_actor event_created_by <<EOF
$event_snapshot
EOF

    if [ -z "$PUB" ] && [ -z "$LINK_TOKEN" ] &&
       [ "$event_actor" != "$USER_TOKEN" ] &&
       [ "$event_created_by" != "$USER_TOKEN" ] &&
       [ "$event_actor" != "$RAW_USER_TOKEN" ] &&
       [ "$event_created_by" != "$RAW_USER_TOKEN" ]; then
      continue
    fi
    if [ -n "$TYPE" ]; then
      case ",$TYPE," in
        *,"$event_type",*) ;;
        *) continue ;;
      esac
    fi
    if [ -n "$PUB" ] && [ "$event_pub" != "$PUB" ]; then
      continue
    fi
    if [ -n "$LINK_TOKEN" ]; then
      case ",$LINK_TOKEN," in
        *,"$event_token",*) ;;
        *) continue ;;
      esac
    fi
    if [ -n "$EVENT" ]; then
      case ",$EVENT," in
        *,"$event_name",*) ;;
        *) continue ;;
      esac
    fi
    if [ -n "$UID_FILTER" ] && [ "$event_uid" != "$UID_FILTER" ]; then
      continue
    fi
    if [ -n "$FROM" ] && [ "$event_ts" \< "$FROM" ]; then
      continue
    fi
    if [ -n "$TO" ] && [ "$event_ts" \> "$TO" ]; then
      continue
    fi

    printf '%s\t%s\n' "$event_ts" "$event_file"
  done < "$TMP" > "$TMP_MATCHED"

  FAST_TOTAL="$(wc -l < "$TMP_MATCHED" | tr -d ' ')"
  "${SORT_CMD[@]}" "$TMP_MATCHED" \
    | awk -v offset="$OFFSET" -v limit="$LIMIT" 'NR > offset && NR <= offset + limit { sub(/^[^\t]*\t/, ""); print }' \
    > "$TMP_PAGE"
  cp "$TMP_PAGE" "$TMP"
fi

if [ ! -s "$TMP" ]; then
  jq -n \
    --argjson page "$PAGE" \
    --argjson limit "$LIMIT" \
    '{
      status:"success",
      message:[{
        page:$page,
        limit:$limit,
        total:0,
        has_next:false,
        items:[]
      }]
    }'
  exit 0
fi

ENRICH_N=0
while IFS= read -r event_file; do
  [ -f "$event_file" ] || continue

  EVENT_PUB="$(jq -r '.publication // .publication_id // ""' "$event_file" 2>/dev/null || echo "")"
  EVENT_TOKEN="$(jq -r '.token // ""' "$event_file" 2>/dev/null || echo "")"
  EVENT_META_FILE="$ROOT/meta/$EVENT_PUB/$EVENT_TOKEN.json"
  ENRICHED_FILE="$TMP_ENRICHED_DIR/$ENRICH_N.json"
  ENRICH_N=$((ENRICH_N + 1))
  NEEDS_ENRICH=1

  if jq -e '
    (.meta.actor // "") != ""
    and (.meta.created_by // "") != ""
    and (.meta.type // "") != ""
    and (.meta.subj // null) != null
    and ((.meta.mails // []) | type) == "array"
    and (.meta.published_at // "") != ""
  ' "$event_file" >/dev/null 2>&1; then
    NEEDS_ENRICH=0
  fi

  if [[ "$NEEDS_ENRICH" = "1" && "$EVENT_PUB" =~ $safe_part_re && "$EVENT_TOKEN" =~ $safe_part_re && -f "$EVENT_META_FILE" ]]; then
    jq --arg public_base_url "$PUBLIC_BASE_URL" --slurpfile current_meta "$EVENT_META_FILE" '
      .meta = ((.meta // {}) + {
        pre: ($current_meta[0].pre // (.meta.pre // "")),
        link: ($current_meta[0].link // (.meta.link // "")),
        post: ($current_meta[0].post // (.meta.post // "")),
        actor: (
          $current_meta[0].actor
          // ($current_meta[0].actions // [] | map(select(.actor != null and .actor != "")) | last | .actor)
          // (.meta.actor // "")
        ),
        created_by: (
          $current_meta[0].created_by
          // ($current_meta[0].actions // [] | map(select(.actor != null and .actor != "")) | last | .actor)
          // (.meta.created_by // "")
        ),
        subj: ($current_meta[0].subj // (.meta.subj // "")),
        mails: (
          if (($current_meta[0].mails // []) | type) == "array"
          then ($current_meta[0].mails // [])
          else (.meta.mails // [])
          end
        ),
        published_at: (
          $current_meta[0].created_at
          // ($current_meta[0].actions // [] | map(.date // empty) | first)
          // (.meta.published_at // "")
        ),
        image: ($current_meta[0].image // (.meta.image // "")),
        preview_url: (
          if (($current_meta[0].image // (.meta.image // "")) != "")
          then ($public_base_url + "/assets-public/" + (.publication // .publication_id // "") + "/" + (.token // "") + "/" + ($current_meta[0].image // (.meta.image // "")))
          else (.meta.preview_url // "")
          end
        )
      })
    ' "$event_file" > "$ENRICHED_FILE" 2>/dev/null || cp "$event_file" "$ENRICHED_FILE"
  else
    cp "$event_file" "$ENRICHED_FILE"
  fi

  printf '%s\n' "$ENRICHED_FILE" >> "$TMP_ENRICHED_LIST"
done < "$TMP"

if [ ! -s "$TMP_ENRICHED_LIST" ]; then
  jq -n \
    --argjson page "$PAGE" \
    --argjson limit "$LIMIT" \
    '{
      status:"success",
      message:[{
        page:$page,
        limit:$limit,
        total:0,
        has_next:false,
        items:[]
      }]
    }'
  exit 0
fi

mapfile -t ENRICHED_FILES < "$TMP_ENRICHED_LIST"

jq -s \
  --argjson page "$PAGE" \
  --argjson limit "$LIMIT" \
  --argjson offset "$OFFSET" \
  --arg user_token "$USER_TOKEN" \
  --arg raw_user_token "$RAW_USER_TOKEN" \
  --arg type "$TYPE" \
  --arg pub "$PUB" \
  --arg link_token "$LINK_TOKEN" \
  --arg event "$EVENT" \
  --arg uid "$UID_FILTER" \
  --arg from "$FROM" \
  --arg to "$TO" \
  --arg sort_order "$SORT_ORDER" \
  --argjson fast_total "$FAST_TOTAL" '
  def csv_list($value):
    if $value == "" then []
    else ($value | split(",") | map(select(. != "")))
    end;

  def allowed_actor:
    (.meta.actor // "") == $user_token
    or (.meta.created_by // "") == $user_token
    or (.meta.actor // "") == $raw_user_token
    or (.meta.created_by // "") == $raw_user_token;

  def allowed_type:
    . as $row
    | (csv_list($type)) as $types
    | ($types | length) == 0
      or (($types | index($row.meta.type // "")) != null);

  def allowed_event:
    . as $row
    | (csv_list($event)) as $events
    | ($events | length) == 0
      or (($events | index($row.event // "")) != null);

  map(select(type == "object"))
  | map(select($pub != "" or $link_token != "" or allowed_actor))
  | map(select(allowed_type))
  | map(select($pub == "" or (.publication // .publication_id // "") == $pub))
  | map(select($link_token == "" or (. as $row | (csv_list($link_token) | index($row.token // "")) != null)))
  | map(select(allowed_event))
  | map(select($uid == "" or (.uid // "") == $uid))
  | map(select($from == "" or (.ts // .created_at // "") >= $from))
  | map(select($to == "" or (.ts // .created_at // "") <= $to))
  | sort_by(.ts // .created_at // "")
  | if $sort_order == "asc" then . else reverse end
  | . as $all
  | (if $fast_total >= 0 then $fast_total else ($all | length) end) as $total
  | {
      status: "success",
      message: [
        {
          page: $page,
          limit: $limit,
          total: $total,
          has_next: (($offset + $limit) < $total),
          items: (if $fast_total >= 0 then $all else $all[$offset:($offset + $limit)] end)
      }
    ]
  }
' "${ENRICHED_FILES[@]}"

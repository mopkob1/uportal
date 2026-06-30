#!/usr/bin/env bash
set -euo pipefail

EVENT_FILE="${1:-}"

ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
EVENTS_ROOT="$ROOT/events"
META_ROOT="$ROOT/meta"
INDEX_ROOT="$EVENTS_ROOT/index/by-user"
USER_FILTER="${UPORTAL_ACTIVITY_INDEX_USER_FILTER:-}"
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$(dirname "$0")/uportal-config.sh"
fi
PUBLIC_BASE_URL="$(uportal_public_base_url)"

safe_user_id_re='^[A-Za-z0-9._-]{1,128}$'
safe_part_re='^[A-Za-z0-9._-]+$'

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

[ -n "$EVENT_FILE" ] || json_error "event file is required"
[ -f "$EVENT_FILE" ] || json_error "event file not found"

mkdir -p "$INDEX_ROOT/.locks"

TMP_EVENT="$(mktemp)"
cleanup() {
  rm -f "$TMP_EVENT"
}
trap cleanup EXIT

EVENT_PUB="$(jq -r '.publication // .publication_id // ""' "$EVENT_FILE" 2>/dev/null || echo "")"
EVENT_TOKEN="$(jq -r '.token // ""' "$EVENT_FILE" 2>/dev/null || echo "")"
EVENT_META_FILE="$META_ROOT/$EVENT_PUB/$EVENT_TOKEN.json"

NEEDS_ENRICH=1
if jq -e '
  (.meta.actor // "") != ""
  and (.meta.created_by // "") != ""
  and (.meta.type // "") != ""
  and (.meta.subj // null) != null
  and ((.meta.mails // []) | type) == "array"
  and (.meta.published_at // "") != ""
' "$EVENT_FILE" >/dev/null 2>&1; then
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
  ' "$EVENT_FILE" > "$TMP_EVENT" 2>/dev/null || cp "$EVENT_FILE" "$TMP_EVENT"
else
  cp "$EVENT_FILE" "$TMP_EVENT"
fi

EVENT_LINE="$(jq -c '.' "$TMP_EVENT")"

append_for_user() {
  local user_id="$1"
  local index_file
  local lock_file

  [[ "$user_id" =~ $safe_user_id_re ]] || return 0
  [[ -z "$USER_FILTER" || "$user_id" == "$USER_FILTER" ]] || return 0

  index_file="$INDEX_ROOT/$user_id.jsonl"
  lock_file="$INDEX_ROOT/.locks/$user_id.lock"

  (
    flock 7
    printf '%s\n' "$EVENT_LINE" >> "$index_file"
    chmod 644 "$index_file"
  ) 7>"$lock_file"
}

ACTOR="$(jq -r '.meta.actor // ""' "$TMP_EVENT" 2>/dev/null || echo "")"
CREATED_BY="$(jq -r '.meta.created_by // ""' "$TMP_EVENT" 2>/dev/null || echo "")"

append_for_user "$ACTOR"
if [[ "$CREATED_BY" != "$ACTOR" ]]; then
  append_for_user "$CREATED_BY"
fi

jq -cn '{status:"success",message:[{indexed:true}]}'

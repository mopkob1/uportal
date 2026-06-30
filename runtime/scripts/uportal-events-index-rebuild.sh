#!/usr/bin/env bash
set -euo pipefail

USER_FILTER="${1:-}"

ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
EVENTS_ROOT="$ROOT/events"
RAW_DIR="$EVENTS_ROOT/raw"
META_ROOT="$ROOT/meta"
BY_USER_DIR="$EVENTS_ROOT/by-user"
ACTIVITY_INDEX_ROOT="$EVENTS_ROOT/index/by-user"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f /usr/local/bin/uportal-config.sh ]; then
  source /usr/local/bin/uportal-config.sh
else
  source "$SCRIPT_DIR/uportal-config.sh"
fi
PUBLIC_BASE_URL="$(uportal_public_base_url)"

safe_token_re='^[A-Za-z0-9._-]{16,128}$'
safe_user_id_re='^[A-Za-z0-9._-]{1,128}$'
safe_part_re='^[A-Za-z0-9._-]+$'

if [ -f /usr/local/bin/uportal-user-identity.sh ]; then
  source /usr/local/bin/uportal-user-identity.sh
else
  source "$(dirname "$0")/uportal-user-identity.sh"
fi

json_error() {
  jq -cn --arg msg "$1" '{status:"error",message:[{text:$msg}]}'
  exit 0
}

if [[ -n "$USER_FILTER" && ! "$USER_FILTER" =~ $safe_token_re ]]; then
  json_error "bad user token"
fi

if [[ -n "$USER_FILTER" ]]; then
  USER_FILTER="$(uportal_resolve_user_id "$USER_FILTER")"
fi

mkdir -p "$RAW_DIR" "$BY_USER_DIR" "$ACTIVITY_INDEX_ROOT"

if [[ -n "$USER_FILTER" ]]; then
  find "$BY_USER_DIR" -maxdepth 1 -type l -name "${USER_FILTER}_*.json" -delete 2>/dev/null || true
  rm -f "$ACTIVITY_INDEX_ROOT/$USER_FILTER.jsonl"
  rm -f "$ACTIVITY_INDEX_ROOT/.ready-$USER_FILTER"
else
  find "$BY_USER_DIR" -maxdepth 1 -type l -name "*.json" -delete 2>/dev/null || true
  find "$ACTIVITY_INDEX_ROOT" -maxdepth 1 -type f -name "*.jsonl" -delete 2>/dev/null || true
  rm -f "$ACTIVITY_INDEX_ROOT/.ready" "$ACTIVITY_INDEX_ROOT"/.ready-* 2>/dev/null || true
fi

SCANNED=0
ENRICHED=0
LINKED=0
INDEXED=0

link_user() {
  local user_id="$1"
  local raw_name="$2"

  [[ "$user_id" =~ $safe_user_id_re ]] || return 0
  [[ -z "$USER_FILTER" || "$user_id" == "$USER_FILTER" ]] || return 0

  ln -sf "../raw/$raw_name" "$BY_USER_DIR/${user_id}_${raw_name}"
  LINKED=$((LINKED + 1))
}

while IFS= read -r event_file; do
  [ -f "$event_file" ] || continue
  SCANNED=$((SCANNED + 1))

  RAW_NAME="$(basename "$event_file")"
  EVENT_PUB="$(jq -r '.publication // .publication_id // ""' "$event_file" 2>/dev/null || echo "")"
  EVENT_TOKEN="$(jq -r '.token // ""' "$event_file" 2>/dev/null || echo "")"
  EVENT_META_FILE="$META_ROOT/$EVENT_PUB/$EVENT_TOKEN.json"

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
    TMP_EVENT="$(mktemp)"
    if jq --arg public_base_url "$PUBLIC_BASE_URL" --slurpfile current_meta "$EVENT_META_FILE" '
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
    ' "$event_file" > "$TMP_EVENT"; then
      mv "$TMP_EVENT" "$event_file"
      chmod 644 "$event_file"
      ENRICHED=$((ENRICHED + 1))
    else
      rm -f "$TMP_EVENT"
    fi
  fi

  ACTOR="$(jq -r '.meta.actor // ""' "$event_file" 2>/dev/null || echo "")"
  CREATED_BY="$(jq -r '.meta.created_by // ""' "$event_file" 2>/dev/null || echo "")"

  link_user "$ACTOR" "$RAW_NAME"
  if [[ "$CREATED_BY" != "$ACTOR" ]]; then
    link_user "$CREATED_BY" "$RAW_NAME"
  fi

  if UPORTAL_ROOT="$ROOT" UPORTAL_ACTIVITY_INDEX_USER_FILTER="$USER_FILTER" "$SCRIPT_DIR/uportal-activity-index-upsert.sh" "$event_file" >/dev/null 2>&1; then
    INDEXED=$((INDEXED + 1))
  fi
done < <(find "$RAW_DIR" -maxdepth 1 -type f -name "*.json" 2>/dev/null | sort)

if [[ -n "$USER_FILTER" ]]; then
  : > "$ACTIVITY_INDEX_ROOT/.ready-$USER_FILTER"
else
  : > "$ACTIVITY_INDEX_ROOT/.ready"
fi

jq -n \
  --arg by_user_dir "$BY_USER_DIR" \
  --arg user_filter "$USER_FILTER" \
  --argjson scanned "$SCANNED" \
  --argjson enriched "$ENRICHED" \
  --argjson linked "$LINKED" \
  --argjson indexed "$INDEXED" \
  '{
    status:"success",
    message:[{
      scanned:$scanned,
      enriched:$enriched,
      linked:$linked,
      indexed:$indexed,
      user_filter:$user_filter,
      by_user_dir:$by_user_dir
    }]
  }'

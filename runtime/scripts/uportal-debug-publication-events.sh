#!/usr/bin/env bash
set -euo pipefail

PUB="${1:-}"
TOKEN_FILTER="${2:-}"
SHORT_FILTER="${3:-}"
ROOT="${UPORTAL_ROOT:-/data/files/uportal}"

META_DIR="$ROOT/meta/$PUB"
SHORT_DIR="$ROOT/short"
EVENTS_ROOT="$ROOT/events"

json_error() {
  jq -cn --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 0
}

safe_part_re='^[A-Za-z0-9._-]+$'

[ -n "$PUB" ] || json_error "usage: uportal-debug-publication-events.sh <publication_id> [token] [short_id]"
[[ "$PUB" =~ $safe_part_re ]] || json_error "bad publication_id"
[[ -z "$TOKEN_FILTER" || "$TOKEN_FILTER" =~ $safe_part_re ]] || json_error "bad token"
[[ -z "$SHORT_FILTER" || "$SHORT_FILTER" =~ ^[A-Za-z0-9]{9}$ ]] || json_error "bad short_id"

TMP_META="$(mktemp)"
TMP_SHORT_IDS="$(mktemp)"
TMP_SHORTS="$(mktemp)"
TMP_EVENT_LINKS="$(mktemp)"
TMP_EVENTS="$(mktemp)"
trap 'rm -f "$TMP_META" "$TMP_SHORT_IDS" "$TMP_SHORTS" "$TMP_EVENT_LINKS" "$TMP_EVENTS"' EXIT

touch "$TMP_META" "$TMP_SHORT_IDS" "$TMP_SHORTS" "$TMP_EVENT_LINKS" "$TMP_EVENTS"

if [ -d "$META_DIR" ]; then
  find "$META_DIR" -maxdepth 1 -type f -name '*.json' -print 2>/dev/null \
  | sort \
  | while IFS= read -r file; do
      [ -f "$file" ] || continue
      jq -c \
        --arg file "$file" \
        --arg token_filter "$TOKEN_FILTER" '
        select($token_filter == "" or (.token // "") == $token_filter)
        | {
            file: $file,
            publication_id: (.publication_id // ""),
            token: (.token // ""),
            type: (.type // ""),
            status: (.status // ""),
            short_id: (.short_id // ""),
            short: (.short // ""),
            short_url: (.short_url // ""),
            shortlink: (.shortlink // ""),
            subj: (.subj // ""),
            mails: (.mails // []),
            owner: (.owner // ""),
            created_by: (.created_by // ""),
            actors: ((.actions // []) | map(.actor // "") | unique | map(select(. != ""))),
            actions: ((.actions // []) | map({
              type: (.type // ""),
              date: (.date // ""),
              actor: (.actor // ""),
              short_id: (.short_id // "")
            })),
            remaining_clicks: (.remaining_clicks // null),
            fresh_until: (.fresh_until // null)
          }
      ' "$file" 2>/dev/null || true
    done > "$TMP_META"
fi

{
  jq -r '
    .short_id,
    (.short // "" | capture("/s/(?<id>[A-Za-z0-9]{9})").id?),
    (.short_url // "" | capture("/s/(?<id>[A-Za-z0-9]{9})").id?),
    (.shortlink // "" | capture("/s/(?<id>[A-Za-z0-9]{9})").id?)
  ' "$TMP_META" 2>/dev/null || true
  [ -n "$SHORT_FILTER" ] && printf '%s\n' "$SHORT_FILTER"
} | grep -E '^[A-Za-z0-9]{9}$' 2>/dev/null | sort -u > "$TMP_SHORT_IDS" || true

while IFS= read -r short_id; do
    file="$SHORT_DIR/$short_id.json"
    if [ -f "$file" ]; then
      jq -c \
        --arg short_id "$short_id" \
        --arg file "$file" '
        {
          short_id: $short_id,
          file: $file,
          publication_id: (.publication_id // ""),
          token: (.token // "")
        }
      ' "$file" 2>/dev/null || true
    else
      jq -cn --arg short_id "$short_id" '{short_id:$short_id,missing:true}'
    fi
done < "$TMP_SHORT_IDS" > "$TMP_SHORTS"

find_events() {
  if [ -n "$TOKEN_FILTER" ]; then
    find "$EVENTS_ROOT/by-link" -maxdepth 1 -type l -name "${PUB}_${TOKEN_FILTER}_*.json" -print 2>/dev/null
  else
    find "$EVENTS_ROOT/by-pub" -maxdepth 1 -type l -name "${PUB}_*.json" -print 2>/dev/null
  fi
}

find_events | sort > "$TMP_EVENT_LINKS" || true

while IFS= read -r link; do
    raw="$(readlink -f "$link" 2>/dev/null || true)"
    [ -f "$raw" ] || continue
    jq -c \
      --arg index_file "$link" \
      --arg raw_file "$raw" \
      --arg short_filter "$SHORT_FILTER" '
      def short_from_uri:
        (.request.original_uri // "" | capture("/s/(?<id>[A-Za-z0-9]{9})").id?) // "";

      select($short_filter == "" or (.meta.short_id // "") == $short_filter or short_from_uri == $short_filter)
      | {
          index_file: $index_file,
          raw_file: $raw_file,
          ts: (.ts // .created_at // ""),
          event: (.event // ""),
          publication_id: (.publication // .publication_id // ""),
          token: (.token // ""),
          uid: (.uid // ""),
          device_guess: {
            key: (.device_guess.key // ""),
            confidence: (.device_guess.confidence // ""),
            source: (.device_guess.source // "")
          },
          meta: {
            type: (.meta.type // ""),
            short_id: (.meta.short_id // ""),
            actor: (.meta.actor // ""),
            created_by: (.meta.created_by // ""),
            subj: (.meta.subj // "")
          },
          original_uri: (.request.original_uri // "")
        }
    ' "$raw" 2>/dev/null || true
done < "$TMP_EVENT_LINKS" > "$TMP_EVENTS"

jq -n \
  --arg root "$ROOT" \
  --arg publication_id "$PUB" \
  --arg token_filter "$TOKEN_FILTER" \
  --arg short_filter "$SHORT_FILTER" \
  --slurpfile meta "$TMP_META" \
  --slurpfile shorts "$TMP_SHORTS" \
  --slurpfile events "$TMP_EVENTS" '
  {
    root: $root,
    publication_id: $publication_id,
    token_filter: $token_filter,
    short_filter: $short_filter,
    counts: {
      meta: ($meta | length),
      shorts: ($shorts | length),
      events: ($events | length)
    },
    meta: $meta,
    short_maps: $shorts,
    events: $events,
    checks: {
      event_tokens_without_meta: (
        (($meta | map(.token)) as $tokens
        | $events | map(select((.token // "") as $token | ($tokens | index($token)) == null)))
      ),
      short_maps_pointing_to_missing_meta: (
        (($meta | map(.token)) as $tokens
        | $shorts | map(select((.token // "") as $token | ($tokens | index($token)) == null)))
      )
    }
  }
'

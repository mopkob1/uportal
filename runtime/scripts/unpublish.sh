#!/usr/bin/env bash

set -euo pipefail

source /usr/local/bin/uportal-actions.sh

publication_id="${1:-}"
token="${2:-}"

UPORTAL_BASE="/data/files/uportal"
INBOX_BASE="/data/files/inbox"

META_FILE="$UPORTAL_BASE/meta/$publication_id/$token.json"
SHORT_DIR="$UPORTAL_BASE/short"
STORAGE_DIR="$UPORTAL_BASE/storage/$publication_id/$token"
INBOX_DIR="$INBOX_BASE/$publication_id/$token"
STICKY_FILE="$UPORTAL_BASE/sticky/$publication_id/$token.json"

json_error() {
  jq -n --arg text "$1" '{status:"error",message:[{text:$text}]}'
  exit 1
}

require_nonempty() {
  [ -n "$2" ] || json_error "missing required field: $1"
}

require_nonempty "publication_id" "$publication_id"
require_nonempty "token" "$token"

[ -f "$META_FILE" ] || json_error "meta not found: $META_FILE"

short_id="$(jq -r '.short_id // .short // ""' "$META_FILE")"
actor="$(jq -r '(.actions // [] | map(select(.actor != null and .actor != "")) | last | .actor) // "system"' "$META_FILE" 2>/dev/null || echo "system")"

audit_details="$(mktemp)"
jq -n \
  --arg operation "unpublish" \
  --arg status "$(jq -r '.status // "active"' "$META_FILE" 2>/dev/null || echo "active")" \
  '{operation:$operation,status:$status}' > "$audit_details"

write_audit_action "link" "unpublish" "$actor" "$publication_id" "$token" "$short_id" "$audit_details" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
rm -f "$audit_details"

if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
  uportal-links-index-upsert.sh delete "$publication_id" "$token" >/dev/null || true
fi

# Delete short only when it actually points to this pub/token.
if [ -n "$short_id" ] && [ -f "$SHORT_DIR/$short_id.json" ]; then
  ref_pub="$(jq -r '.publication_id // ""' "$SHORT_DIR/$short_id.json")"
  ref_tok="$(jq -r '.token // ""' "$SHORT_DIR/$short_id.json")"
  if [ "$ref_pub" = "$publication_id" ] && [ "$ref_tok" = "$token" ]; then
    rm -f "$SHORT_DIR/$short_id.json"
  fi
fi

rm -f "$META_FILE"
rm -f "$STICKY_FILE"
rm -rf "$STORAGE_DIR"
rm -rf "$INBOX_DIR"

# Try to remove empty pub directories in meta/storage/inbox.
rmdir "$UPORTAL_BASE/meta/$publication_id" 2>/dev/null || true
rmdir "$UPORTAL_BASE/sticky/$publication_id" 2>/dev/null || true
rmdir "$UPORTAL_BASE/storage/$publication_id" 2>/dev/null || true
rmdir "$INBOX_BASE/$publication_id" 2>/dev/null || true

jq -n \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg short_id "$short_id" '
  {
    status: "success",
    message: [
      {
        publication_id: $publication_id,
        token: $token,
        short_id: $short_id,
        operation: "unpublish",
        unpublished: true
      }
    ]
  }
'

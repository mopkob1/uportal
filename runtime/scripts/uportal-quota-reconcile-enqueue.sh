#!/usr/bin/env bash
set -euo pipefail

publication_id="${1:-}"
token="${2:-}"
reason="${3:-publication_published}"

UPORTAL_ROOT="${UPORTAL_ROOT:-/data/files/uportal}"
QUEUE_DIR="${UPORTAL_QUOTA_RECONCILE_QUEUE_DIR:-$UPORTAL_ROOT/quota-reconcile-queue}"

safe_part_re='^[A-Za-z0-9._-]{1,160}$'
if ! [[ "$publication_id" =~ $safe_part_re ]] || ! [[ "$token" =~ $safe_part_re ]]; then
  exit 0
fi

mkdir -p "$QUEUE_DIR"

now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
nonce="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
base="quota-reconcile-${now//[:]/}${publication_id}_${token}_${nonce}"
tmp="$QUEUE_DIR/$base.tmp"
final="$QUEUE_DIR/$base.json"

jq -n \
  --arg task "quota_reconcile" \
  --arg ts "$now" \
  --arg publication_id "$publication_id" \
  --arg token "$token" \
  --arg reason "$reason" '
  {
    task: $task,
    ts: $ts,
    publication_id: $publication_id,
    token: $token,
    reason: $reason
  }
' > "$tmp"

mv -f "$tmp" "$final"

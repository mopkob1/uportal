#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${UPORTAL_DOMAIN:?UPORTAL_DOMAIN is required}"

has_compose_template_garbage() {
  case "$1" in
    *'$'*|*'{'*|*'}'*) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_base_url() {
  local value="$1"
  if [ -z "$value" ] || has_compose_template_garbage "$value"; then
    value="https://$DOMAIN"
  fi
  value="${value%/}"
  printf '%s' "$value"
}

normalize_bridge_url() {
  local value="$1"
  if [ -z "$value" ] || has_compose_template_garbage "$value"; then
    value="https://u.1qr.org/api/community/register-plugin"
  fi
  case "$value" in
    http://*|https://*)
      printf '%s' "${value%/}"
      ;;
    /*)
      printf '%s%s' "$BASE_URL" "$value"
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

BASE_URL="$(normalize_base_url "${UPORTAL_PUBLIC_BASE_URL:-${UPORTAL_BASE_URL:-}}")"
FALLBACK_URL="${UPORTAL_FALLBACK_URL:-}"
if [ -z "$FALLBACK_URL" ] || has_compose_template_garbage "$FALLBACK_URL"; then
  FALLBACK_URL="$BASE_URL/link-fallback"
else
  FALLBACK_URL="${FALLBACK_URL%/}"
fi
N8N_URL="${UPORTAL_N8N_URL:-}"
if [ "${UPORTAL_COMMERCIAL_BRIDGE:-}" = "rewr1te" ]; then
  COMMERCIAL_BRIDGE_URL="$(normalize_bridge_url "${UPORTAL_COMMERCIAL_BRIDGE_URL:-https://u.1qr.org/api/community/register-plugin}")"
  COMMERCIAL_BRIDGE_TIMEOUT="${UPORTAL_COMMERCIAL_BRIDGE_TIMEOUT:-3}"
else
  COMMERCIAL_BRIDGE_URL="$(normalize_bridge_url "https://u.1qr.org/api/community/register-plugin")"
  COMMERCIAL_BRIDGE_TIMEOUT="3"
fi

DATA_ROOT="/data/files"
UPORTAL_ROOT="$DATA_ROOT/uportal"
INBOX_ROOT="$DATA_ROOT/inbox"

rand_hex() {
  dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

ensure_dir() {
  install -d "$@"
}

require_runtime_dir() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "missing required runtime directory: $dir" >&2
    echo "check the deployment source tree; runtime/nginx, runtime/njs, runtime/shhoook and runtime/scripts must be included" >&2
    exit 1
  fi
}

write_if_missing() {
  local src="$1"
  local dst="$2"
  local mode="${3:-0644}"
  if [ ! -e "$dst" ]; then
    install -m "$mode" "$src" "$dst"
  fi
}

base64_one_line() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

escape_sed_re() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{}|]/\\&/g'
}

gen_short_id() {
  local v
  while true; do
    v="$(rand_hex | cut -c1-9)"
    [ ! -e "$UPORTAL_ROOT/short/$v.json" ] || continue
    printf '%s' "$v"
    return
  done
}

delete_env_keys() {
  local file="$1"
  shift

  [ -f "$file" ] || return 0
  [ "$#" -gt 0 ] || return 0

  for key in "$@"; do
    sed -i "/^$key=/d" "$file"
  done
}

ensure_install_id() {
  local file="$UPORTAL_ROOT/config/install-id"
  local value

  if [ -s "$file" ]; then
    tr -d '[:space:]' < "$file"
    return
  fi

  value="$(rand_hex | cut -c1-32)"
  printf '%s\n' "$value" > "$file"
  chmod 600 "$file"
  printf '%s' "$value"
}

read_git_commit() {
  local git_dir="/opt/uportal/git"
  local head
  local ref

  [ -r "$git_dir/HEAD" ] || {
    printf 'unknown'
    return
  }

  head="$(cat "$git_dir/HEAD" 2>/dev/null | tr -d '[:space:]' || true)"
  case "$head" in
    ref:*)
      ref="${head#ref:}"
      if [ -r "$git_dir/$ref" ]; then
        cat "$git_dir/$ref" 2>/dev/null | tr -d '[:space:]'
      elif [ -r "$git_dir/packed-refs" ]; then
        awk -v ref="$ref" '$2 == ref { print $1; exit }' "$git_dir/packed-refs" 2>/dev/null | tr -d '[:space:]'
      else
        printf 'unknown'
      fi
      ;;
    "")
      printf 'unknown'
      ;;
    *)
      printf '%s' "$head"
      ;;
  esac
}

hide_plugin_link_from_first_user() {
  local publication_id="$1"
  local token="$2"
  local meta_file="$UPORTAL_ROOT/meta/$publication_id/$token.json"
  local tmp

  if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
    uportal-links-index-upsert.sh delete "$publication_id" "$token" >/dev/null || true
  fi

  [ -f "$meta_file" ] || return 0
  tmp="$(mktemp)"
  jq '
    .actions = ((.actions // []) | map(.actor = "installer-internal"))
  ' "$meta_file" > "$tmp" && mv "$tmp" "$meta_file"
  chmod 644 "$meta_file"
}

ensure_plugin_local_download_link() {
  local first_user_token="$1"
  local tokens_file="$2"
  local publication_id="setup-plugin-xpi-local"
  local token="download-uportal-link-inserter-xpi-local"
  local file_name="uportal-link-inserter.xpi"
  local inbox_dir="$INBOX_ROOT/$publication_id/$token"
  local meta_file="$UPORTAL_ROOT/meta/$publication_id/$token.json"
  local short_id
  local result
  local url

  [ -n "$first_user_token" ] || return 0
  if [ -f "$meta_file" ]; then
    url="$(jq -r '.short_url // ""' "$meta_file" 2>/dev/null || true)"
    if [ -z "$url" ]; then
      short_id="$(jq -r '.short_id // .short // ""' "$meta_file" 2>/dev/null || true)"
      [ -n "$short_id" ] && url="$BASE_URL/s/$short_id"
    fi
    [ -n "$url" ] && PLUGIN_XPI_LOCAL_URL="$url"
    hide_plugin_link_from_first_user "$publication_id" "$token"
    return 0
  fi

  ensure_dir "$inbox_dir"
  cp -f "$UPORTAL_ROOT/build/plugin/$file_name" "$inbox_dir/$file_name"
  short_id="$(gen_short_id)"

  result="$(
    /usr/local/bin/publish-download.sh \
      "download" \
      "active" \
      "$publication_id" \
      "$token" \
      "$short_id" \
      "UPORTAL plugin" \
      '["first user"]' \
      "Download UPORTAL plugin package" \
      "$file_name" \
      "$file_name" \
      "" \
      "0" \
      "download" \
      "60" \
      "15" \
      "UPORTAL Thunderbird plugin" \
      "Generated XPI for this UPORTAL installation" \
      "-1" \
      "-1" \
      "$FALLBACK_URL" \
      "" \
      "" \
      "1800" \
      "$first_user_token" \
      "" \
      "" \
      "" \
      "installer-first-run" \
      "web" \
      "${UPORTAL_UI_LANG:-en}"
  )"

  url="$(printf '%s' "$result" | jq -r '.message[0].short_url // ""' 2>/dev/null || true)"
  [ -n "$url" ] || {
    echo "plugin xpi download link creation failed: $result" >&2
    return 0
  }

  chmod 600 "$tokens_file"
  PLUGIN_XPI_URL="$url"
  PLUGIN_XPI_LOCAL_URL="$url"
  hide_plugin_link_from_first_user "$publication_id" "$token"
}

register_plugin_commercial_redirect() {
  local tokens_file="$1"
  local endpoint="$COMMERCIAL_BRIDGE_URL"
  local install_id="$2"
  local version
  local commit
  local payload
  local response
  local commercial_url

  [ -n "${PLUGIN_XPI_LOCAL_URL:-}" ] || return 1
  [ -n "$endpoint" ] || return 1

  version="$(cat /opt/uportal/VERSION 2>/dev/null | tr -d '[:space:]' || true)"
  [ -n "$version" ] || version="unknown"
  commit="$(read_git_commit)"
  [ -n "$commit" ] || commit="unknown"

  payload="$(
    jq -n \
      --arg local_plugin_url "$PLUGIN_XPI_LOCAL_URL" \
      --arg instance_base_url "$BASE_URL" \
      --arg runtime "community" \
      --arg version "$version" \
      --arg commit "$commit" \
      --arg install_id "$install_id" \
      --arg language "${UPORTAL_UI_LANG:-en}" \
      --arg domain "$DOMAIN" \
      '{
        local_plugin_url: $local_plugin_url,
        instance_base_url: $instance_base_url,
        runtime: $runtime,
        version: $version,
        commit: $commit,
        install_id: $install_id,
        language: $language,
        domain: $domain
      }'
  )"

  if ! response="$(
    curl -fsS \
      --connect-timeout "$COMMERCIAL_BRIDGE_TIMEOUT" \
      --max-time "$COMMERCIAL_BRIDGE_TIMEOUT" \
      -H 'Content-Type: application/json' \
      -H "X-UPortal-Version: $version" \
      -H "X-UPortal-Commit: $commit" \
      -H "X-UPortal-Install-Id: $install_id" \
      -d "$payload" \
      "$endpoint" 2>/dev/null
  )"; then
    echo "commercial bridge unavailable; using local plugin xpi download" >&2
    return 1
  fi

  commercial_url="$(
    printf '%s' "$response" | jq -r '
      .commercial_redirect_url
      // .redirect_url
      // .message[0].commercial_redirect_url
      // .message[0].redirect_url
      // ""
    ' 2>/dev/null || true
  )"

  if [ -z "$commercial_url" ]; then
    echo "commercial bridge returned no redirect; using local plugin xpi download" >&2
    return 1
  fi

  PLUGIN_XPI_COMMERCIAL_URL="$commercial_url"
  PLUGIN_XPI_URL="$commercial_url"
  printf '%s' "$commercial_url"
  return 0
}

print_plugin_download_link() {
  local tokens_file="$1"
  local install_id="$2"

  if register_plugin_commercial_redirect "$tokens_file" "$install_id" >/dev/null; then
    echo "plugin xpi download: $PLUGIN_XPI_COMMERCIAL_URL"
    return
  fi

  if [ -n "${PLUGIN_XPI_LOCAL_URL:-}" ]; then
    echo "plugin xpi download: $PLUGIN_XPI_LOCAL_URL"
  fi
  return 0
}

visible_plugin_short_id() {
  local publication_id="setup-plugin-xpi"
  local token="download-uportal-link-inserter-xpi"
  local meta_file="$UPORTAL_ROOT/meta/$publication_id/$token.json"
  local short

  if [ -f "$meta_file" ]; then
    short="$(jq -r '.short_id // .short // ""' "$meta_file" 2>/dev/null || true)"
    if [[ "$short" =~ ^[A-Za-z0-9]{9}$ ]]; then
      printf '%s' "$short"
      return
    fi
  fi

  gen_short_id
}

publish_plugin_public_redirect() {
  local first_user_token="$1"
  local commercial_url="$2"
  local publication_id="setup-plugin-xpi"
  local token="download-uportal-link-inserter-xpi"
  local meta_dir="$UPORTAL_ROOT/meta/$publication_id"
  local short_id
  local meta_file="$meta_dir/$token.json"
  local short_file
  local local_fallback_url="${PLUGIN_XPI_LOCAL_URL:-$FALLBACK_URL}"
  local existing_file
  local now
  local tmp

  [ -n "$first_user_token" ] || return 0
  [ -n "$commercial_url" ] || return 0

  ensure_dir "$meta_dir"
  ensure_dir "$UPORTAL_ROOT/short"

  short_id="$(visible_plugin_short_id)"
  short_file="$UPORTAL_ROOT/short/$short_id.json"
  tmp="$(mktemp)"
  jq -n \
    --arg publication_id "$publication_id" \
    --arg token "$token" \
    '{publication_id: $publication_id, token: $token}' > "$tmp" && mv "$tmp" "$short_file"
  chmod 644 "$short_file"

  existing_file="$(mktemp)"
  if [ -f "$meta_file" ]; then
    cp "$meta_file" "$existing_file"
  else
    printf '{}\n' > "$existing_file"
  fi

  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp)"
  jq \
    --arg publication_id "$publication_id" \
    --arg token "$token" \
    --arg short_id "$short_id" \
    --arg commercial_url "$commercial_url" \
    --arg fallback_url "$local_fallback_url" \
    --arg now "$now" \
    --arg lang "${UPORTAL_UI_LANG:-en}" \
    '
    . as $existing
    | {
        type: "redirect",
        status: "active",
        publication_id: $publication_id,
        token: $token,
        short_id: $short_id,
        short: $short_id,
        subj: "UPORTAL plugin",
        mails: ["first user"],
        pre: "",
        link: "Download UPORTAL plugin",
        post: "",
        sticky: false,
        fresh_until: -1,
        remaining_clicks: -1,
        fallback_url: $fallback_url,
        title: "UPORTAL Thunderbird plugin",
        description: "Generated XPI for this UPORTAL installation",
        image: "",
        target_url: $commercial_url,
        delay: "0",
        template: "redirect",
        stat_ttl_sec: "15",
        lang: $lang,
        actions: (
          ($existing.actions // [])
          + [
            {
              type: "redirect",
              date: $now,
              actor: "first-user",
              short_id: $short_id,
              details: {
                link: "Download UPORTAL plugin",
                target_url: $commercial_url
              }
            }
          ]
        )
      }
    ' "$existing_file" > "$tmp" && mv "$tmp" "$meta_file"
  rm -f "$existing_file"
  chmod 644 "$meta_file"

  if command -v uportal-links-index-upsert.sh >/dev/null 2>&1; then
    uportal-links-index-upsert.sh upsert "$publication_id" "$token" >/dev/null || true
  fi
}

ensure_plugin_public_download_link() {
  local first_user_token="$1"
  local publication_id="setup-plugin-xpi"
  local token="download-uportal-link-inserter-xpi"
  local file_name="uportal-link-inserter.xpi"
  local inbox_dir="$INBOX_ROOT/$publication_id/$token"
  local meta_file="$UPORTAL_ROOT/meta/$publication_id/$token.json"
  local short_id
  local result

  [ -n "$first_user_token" ] || return 0
  if [ -f "$meta_file" ] && [ "$(jq -r '.type // ""' "$meta_file" 2>/dev/null || true)" = "download" ]; then
    return 0
  fi

  ensure_dir "$inbox_dir"
  cp -f "$UPORTAL_ROOT/build/plugin/$file_name" "$inbox_dir/$file_name"
  short_id="$(visible_plugin_short_id)"

  result="$(
    /usr/local/bin/publish-download.sh \
      "download" \
      "active" \
      "$publication_id" \
      "$token" \
      "$short_id" \
      "UPORTAL plugin" \
      '["first user"]' \
      "Download UPORTAL plugin" \
      "$file_name" \
      "$file_name" \
      "" \
      "0" \
      "download" \
      "60" \
      "15" \
      "UPORTAL Thunderbird plugin" \
      "Generated XPI for this UPORTAL installation" \
      "-1" \
      "-1" \
      "$FALLBACK_URL" \
      "" \
      "" \
      "1800" \
      "$first_user_token" \
      "" \
      "" \
      "" \
      "installer-first-run" \
      "web" \
      "${UPORTAL_UI_LANG:-en}"
  )"

  if ! printf '%s' "$result" | jq -e '.status == "success"' >/dev/null 2>&1; then
    echo "plugin public download publication failed: $result" >&2
  fi
}

for dir in \
  "$UPORTAL_ROOT" \
  "$UPORTAL_ROOT/meta" \
  "$UPORTAL_ROOT/short" \
  "$UPORTAL_ROOT/storage" \
  "$UPORTAL_ROOT/templates" \
  "$UPORTAL_ROOT/pixel" \
  "$UPORTAL_ROOT/user-tokens" \
  "$UPORTAL_ROOT/user-tokens-enabled" \
  "$UPORTAL_ROOT/dictionaries" \
  "$UPORTAL_ROOT/events" \
  "$UPORTAL_ROOT/sticky" \
  "$UPORTAL_ROOT/index" \
  "$UPORTAL_ROOT/audit" \
  "$UPORTAL_ROOT/config" \
  "$UPORTAL_ROOT/upload-grants" \
  "$UPORTAL_ROOT/telegram-notify-queue" \
  "$UPORTAL_ROOT/build/admin" \
  "$UPORTAL_ROOT/build/plugin" \
  "$DATA_ROOT/upload-temp" \
  "$INBOX_ROOT"
do
  ensure_dir "$dir"
done

# Uploads are handled by nginx WebDAV workers, not by shhoook scripts. Keep the
# inbox writable for the nginx user while the rest of the data tree can stay
# root-owned and world-readable.
chmod 755 "$DATA_ROOT" "$UPORTAL_ROOT"
chown -R www-data:www-data "$INBOX_ROOT"
chmod 775 "$INBOX_ROOT"
chown -R www-data:www-data "$DATA_ROOT/upload-temp"
chmod 775 "$DATA_ROOT/upload-temp"
chmod 775 "$UPORTAL_ROOT/upload-grants" "$UPORTAL_ROOT/telegram-notify-queue"

cp -a /opt/uportal/runtime/templates/. "$UPORTAL_ROOT/templates/"
cp -a /opt/uportal/build/admin/. "$UPORTAL_ROOT/build/admin/"
cp -a /opt/uportal/build/plugin/. "$UPORTAL_ROOT/build/plugin/"

pixel="$UPORTAL_ROOT/pixel/1x1.gif"
if [ ! -f "$pixel" ]; then
  printf '%s' 'R0lGODlhAQABAPAAAP///wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw==' | base64 -d > "$pixel"
  chmod 644 "$pixel"
fi

config_file="$UPORTAL_ROOT/config/uportal.env"
cat > "$config_file" <<EOF
UPORTAL_PUBLIC_BASE_URL=$BASE_URL
UPORTAL_BASE_URL=$BASE_URL
UPORTAL_FALLBACK_URL=$FALLBACK_URL
EOF
chmod 644 "$config_file"

secrets_file="/etc/nginx/conf.d/00-uportal-secrets.conf"
cp /opt/uportal/runtime/nginx/conf.d/00-uportal-secrets.conf "$secrets_file"

persisted_secrets="$UPORTAL_ROOT/config/secrets.env"
if [ -f "$persisted_secrets" ]; then
  # shellcheck disable=SC1090
  source "$persisted_secrets"
fi

ADMIN_SECRET="${UPORTAL_ADMIN_SECRET:-${ADMIN_SECRET:-$(rand_hex)}}"
DL_SALT="${UPORTAL_DOWNLOAD_SALT:-${DL_SALT:-$(rand_hex)}}"
STAT_SECRET="${UPORTAL_STAT_SECRET:-${STAT_SECRET:-$(rand_hex)}}"
PAGE_SECRET="${UPORTAL_PAGE_SECRET:-${PAGE_SECRET:-$(rand_hex)}}"
INTERNAL_KEY="${UPORTAL_INTERNAL_KEY:-${INTERNAL_KEY:-$(rand_hex)}}"

cat > "$persisted_secrets" <<EOF
ADMIN_SECRET=$ADMIN_SECRET
DL_SALT=$DL_SALT
STAT_SECRET=$STAT_SECRET
PAGE_SECRET=$PAGE_SECRET
INTERNAL_KEY=$INTERNAL_KEY
EOF
chmod 600 "$persisted_secrets"

sed -i \
  -e "s|CHANGE_ME_UPORTAL_ADMIN_SECRET|$ADMIN_SECRET|g" \
  -e "s|CHANGE_ME_DOWNLOAD_SALT|$DL_SALT|g" \
  -e "s|CHANGE_ME_STAT_SECRET|$STAT_SECRET|g" \
  -e "s|CHANGE_ME_PAGE_SECRET|$PAGE_SECRET|g" \
  -e "s|CHANGE_ME_UPORTAL_INTERNAL_KEY|$INTERNAL_KEY|g" \
  -e "s|http://CHANGE_ME_N8N_HOST:5673|${N8N_URL:-http://127.0.0.1:5673}|g" \
  "$secrets_file"

cp /opt/uportal/runtime/nginx/conf.d/00-uportal.conf /etc/nginx/conf.d/00-uportal.conf
cp /opt/uportal/runtime/nginx/conf.d/00-uportal-api.conf /etc/nginx/conf.d/00-uportal-api.conf
require_runtime_dir /opt/uportal/runtime/nginx/snippets
require_runtime_dir /opt/uportal/runtime/njs
require_runtime_dir /opt/uportal/runtime/shhoook
require_runtime_dir /opt/uportal/runtime/scripts
ensure_dir /etc/nginx/snippets /etc/nginx/njs /etc/nginx/sites-enabled /etc/shhoook
cp -a /opt/uportal/runtime/nginx/snippets/. /etc/nginx/snippets/
cp -a /opt/uportal/runtime/njs/. /etc/nginx/njs/
cp -a /opt/uportal/runtime/shhoook/. /etc/shhoook/
cp -a /opt/uportal/runtime/scripts/. /usr/local/bin/
find /usr/local/bin -maxdepth 1 -type f -name '*.sh' -exec chmod 755 {} \;

first_run_tokens_file="$UPORTAL_ROOT/config/first-run-tokens.env"
if [ ! -f "$first_run_tokens_file" ]; then
  first_user_token="$(rand_hex | cut -c1-48)"
  first_user_payload_b64="$(
    printf '%s' '{"user":"first user","user_id":"first-user","scope":["admin","upload","activity","dictionary"],"status":"active","tags":["bootstrap","first-run"]}' \
      | base64_one_line
  )"

  /usr/local/bin/uportal-token-upsert.sh "$first_user_token" "$first_user_payload_b64" >/dev/null

  cat > "$first_run_tokens_file" <<EOF
ADMIN_TOKEN=$ADMIN_SECRET
FIRST_USER_TOKEN=$first_user_token
EOF
  chmod 600 "$first_run_tokens_file"

  echo "admin token: $ADMIN_SECRET"
  echo "first user token: $first_user_token"
fi

# shellcheck disable=SC1090
source "$first_run_tokens_file"
delete_env_keys "$first_run_tokens_file" \
  "PLUGIN_XPI_LOCAL_URL" \
  "PLUGIN_XPI_COMMERCIAL_URL" \
  "PLUGIN_XPI_URL"
unset PLUGIN_XPI_LOCAL_URL PLUGIN_XPI_COMMERCIAL_URL PLUGIN_XPI_URL
ensure_plugin_local_download_link "${FIRST_USER_TOKEN:-}" "$first_run_tokens_file"
INSTALL_ID="$(ensure_install_id)"
print_plugin_download_link "$first_run_tokens_file" "$INSTALL_ID"
if [ -n "${PLUGIN_XPI_COMMERCIAL_URL:-}" ]; then
  publish_plugin_public_redirect "${FIRST_USER_TOKEN:-}" "$PLUGIN_XPI_COMMERCIAL_URL"
else
  ensure_plugin_public_download_link "${FIRST_USER_TOKEN:-}"
fi

escaped_domain="$(escape_sed_re "$DOMAIN")"
escaped_base_regex="$(escape_sed_re "$BASE_URL")"

find /etc/nginx/conf.d /etc/shhoook /usr/local/bin "$UPORTAL_ROOT/templates" "$UPORTAL_ROOT/build/admin" -type f -exec sed -i \
  -e "s|__UPORTAL_BASE_URL__|$BASE_URL|g" \
  -e "s|__UPORTAL_DOMAIN__|$DOMAIN|g" \
  -e "s|__UPORTAL_BASE_URL_REGEX__|$escaped_base_regex|g" \
  -e "s|__UPORTAL_DOMAIN_REGEX__|$escaped_domain|g" \
  -e "s|CHANGE_ME_UPORTAL_ADMIN_SECRET|$ADMIN_SECRET|g" \
  -e "s|CHANGE_ME_DOWNLOAD_SALT|$DL_SALT|g" \
  -e "s|CHANGE_ME_STAT_SECRET|$STAT_SECRET|g" \
  -e "s|CHANGE_ME_PAGE_SECRET|$PAGE_SECRET|g" \
  -e "s|CHANGE_ME_UPORTAL_INTERNAL_KEY|$INTERNAL_KEY|g" \
  {} +

site_tmp="$(mktemp)"
sed \
  -e 's/listen 443 ssl http2;/listen 8080;/' \
  -e '/ssl_certificate/d' \
  -e 's|http://127.0.0.1:8080|http://127.0.0.1:18081|g' \
  -e "s|__UPORTAL_DOMAIN__|$DOMAIN|g" \
  /opt/uportal/runtime/nginx/sites-available/uportal.conf > "$site_tmp"

head -n -1 "$site_tmp" > "$site_tmp.with-ui"
cat >> "$site_tmp.with-ui" <<'EOF'
    location = /ui { return 301 /ui/; }
    location /ui/ {
        alias /data/files/uportal/build/admin/;
        try_files $uri $uri/ /ui/index.html;
        add_header Cache-Control "no-store" always;
    }
EOF
tail -n 1 "$site_tmp" >> "$site_tmp.with-ui"
mv "$site_tmp.with-ui" "$site_tmp"
install -m 0644 "$site_tmp" /etc/nginx/sites-enabled/uportal.conf
rm -f "$site_tmp"

export LISTEN_ADDR="127.0.0.1:18081"
export CONFIG_DIR="/etc/shhoook"
export UPORTAL_ROOT

/usr/local/bin/shhoook &
shhoook_pid="$!"

nginx -t
nginx -g 'daemon off;' &
nginx_pid="$!"

term_handler() {
  kill "$nginx_pid" "$shhoook_pid" 2>/dev/null || true
  wait "$nginx_pid" "$shhoook_pid" 2>/dev/null || true
}
trap term_handler TERM INT

wait -n "$nginx_pid" "$shhoook_pid"
term_handler

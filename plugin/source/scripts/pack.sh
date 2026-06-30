#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."

version_file="${UPORTAL_VERSION_FILE:-}"
if [ -z "$version_file" ]; then
  for candidate in ../../VERSION /src/VERSION; do
    if [ -f "$candidate" ]; then
      version_file="$candidate"
      break
    fi
  done
fi

build_dir=""
src_dir="."
if [ -n "$version_file" ] && [ -f "$version_file" ]; then
  version="$(tr -d '[:space:]' < "$version_file")"
  printf '%s' "$version" | grep -Eq '^[0-9]+(\.[0-9]+){1,3}$'
  build_dir="$(mktemp -d)"
  cp -R . "$build_dir/source"
  jq --arg version "$version" '.version = $version' manifest.json > "$build_dir/source/manifest.json"
  src_dir="$build_dir/source"
fi

out_file="$(pwd)/../uportal-link-inserter.xpi"
rm -f "$out_file"
(cd "$src_dir" && zip -r "$out_file" . \
  -x "*.git*" \
  -x "*.DS_Store" \
  -x "fixtures/*" \
  -x "scripts/pack.sh")

[ -z "$build_dir" ] || rm -rf "$build_dir"
echo "../uportal-link-inserter.xpi"

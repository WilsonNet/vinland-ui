#!/usr/bin/env bash
# Screenshots every showroom page (full height) for visual review.
#   scripts/shoot-pages.sh <out-dir> [light|dark] [scale] [slug-filter-regex]
# Needs a running showroom with a control port (VUI_HIDDEN=1 recommended).
set -euo pipefail
out=${1:-build/shots}; mode=${2:-light}; filter=${4:-.}
ctl="$(dirname "$0")/../build/vui-ctl"
mkdir -p "$out"
"$ctl" dark "$([ "$mode" = dark ] && echo on || echo off)" >/dev/null
slugs=$("$ctl" pages | python3 -c 'import json,sys; print("\n".join(p["slug"] for p in json.load(sys.stdin)["pages"]))' | grep -E "$filter")
for slug in $slugs; do
  "$ctl" nav page="$slug" >/dev/null
  "$ctl" settle >/dev/null
  "$ctl" screenshot "$out/$mode-$slug.png" >/dev/null
done
echo "$(echo "$slugs" | wc -l) pages -> $out"

#!/usr/bin/env bash
# Builds everything into ./build
#   ./build.sh            debug builds
#   ./build.sh release    optimized builds
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-debug}
flags="-debug"
[ "$mode" = release ] && flags="-o:speed"
mkdir -p build
odin build tools/vui-ctl  -out:build/vui-ctl  $flags
odin build showroom       -out:build/showroom $flags
odin build examples/hello -out:build/hello    $flags
echo "built: build/showroom build/vui-ctl build/hello ($mode)"

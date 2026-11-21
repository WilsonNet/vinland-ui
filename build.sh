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
# SPIR-V for the Vulkan backend is committed; rebuild it when glslc is available.
if command -v glslc >/dev/null; then
  (cd vui/app/shaders && glslc -fshader-stage=vert ui.vert -o ui.vert.spv && glslc -fshader-stage=frag ui.frag -o ui.frag.spv)
fi
odin build tools/vui-ctl  -out:build/vui-ctl  $flags
odin build tools/vui-test -out:build/vui-test $flags
odin build showroom       -out:build/showroom $flags
odin build examples/hello -out:build/hello    $flags
odin test tests >/dev/null && echo "tests: ok"
echo "built: build/showroom build/vui-ctl build/vui-test build/hello ($mode)"

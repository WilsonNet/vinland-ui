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
# SPIR-V for the Vulkan backend is committed; rebuild it when glslc is available and sources are newer.
if command -v glslc >/dev/null; then
  (
    cd vui/app/shaders
    if [ ! -f ui.vert.spv ] || [ ui.vert -nt ui.vert.spv ] || [ ui_vs_body.glsl -nt ui.vert.spv ]; then
      glslc -fshader-stage=vert ui.vert -o ui.vert.spv
    fi
    if [ ! -f ui.frag.spv ] || [ ui.frag -nt ui.frag.spv ] || [ ui_fs_body.glsl -nt ui.frag.spv ]; then
      glslc -fshader-stage=frag ui.frag -o ui.frag.spv
    fi
  )
fi
odin build tools/vui-ctl  -out:build/vui-ctl  $flags
odin build tools/vui-test -out:build/vui-test $flags
odin build showroom       -out:build/showroom $flags
odin build examples/hello -out:build/hello    $flags
# WebAssembly build of the showroom examples (website); needs wasm-ld (LLVM)
WASM_LD_DIR=$(dirname "$(command -v wasm-ld 2>/dev/null || ls /usr/lib/llvm*/bin/wasm-ld /opt/homebrew/opt/llvm*/bin/wasm-ld /usr/local/opt/llvm*/bin/wasm-ld 2>/dev/null | tail -1)" 2>/dev/null || true)
if [ -n "$WASM_LD_DIR" ] && [ -x "$WASM_LD_DIR/wasm-ld" ]; then
  mkdir -p build/web
  PATH="$WASM_LD_DIR:$PATH" odin build showroom -target:js_wasm32 -o:size -out:build/web/vui.wasm && echo "wasm: build/web/vui.wasm"
fi
odin test tests >/dev/null && echo "tests: ok"
echo "built: build/showroom build/vui-ctl build/vui-test build/hello ($mode)"

# Platforms & Cross-OS Handoff

## Pending Cross-OS Verification

<!-- Add a one-line bullet when editing code for the other OS that cannot be run locally; delete it once verified there. -->

- [ ] **Web** (from macOS): verify the Game UI page (`game-ui`) in the WebGL2 build; `textureGrad` + corner shapes come from the shared GLSL body.

- [ ] **macOS** (visible window): `./build/vui-hot examples/counter` on Metal swaps without closing the window. The headless suite (`python3 tests/hot/test_hot.py`, `.dylib` swaps) passes on macOS CI.
- [ ] **Windows**: `tools/vui-hot/platform_other.odin` / `vui/hot/stat_other.odin` (`.dll`; Windows locks a loaded DLL, so deleting old builds fails silently until exit) are untested.

## Platform & Backend Matrix

| Platform | Preferred GPU | Fallback | Headless (`VUI_HIDDEN=1`) | Background (`VUI_BACKGROUND=1`) | Status |
|---|---|---|---|---|---|
| **Linux** | Vulkan (`SPIR-V`) | OpenGL 3.3 | `SDL_VIDEO_DRIVER=offscreen` + Mesa `llvmpipe` (`sandboxed:true`) | `NOT_FOCUSABLE` + `HINT_WINDOW_ACTIVATE_WHEN_SHOWN=0` (X11 honors; Wayland compositor decides) | Tested |
| **macOS** | Metal (`MSL`) | OpenGL 3.3 Core (`FORWARD_COMPATIBLE`) | Hidden Cocoa window + `SDL_MAC_BACKGROUND_APP=1` | `NOT_FOCUSABLE` + `SDL_MAC_BACKGROUND_APP=1` (no Dock icon or focus steal) | Tested |
| **Web (demos)** | WebGL2 (`vui/web`) | — | Playwright Chromium + SwiftShader | — | Tested |
| **Windows** | Vulkan / Metal stub (`platform_other.odin`) | OpenGL 3.3 | Hidden window | `NOT_FOCUSABLE` | Untested |

Override GPU/backend at runtime with `VUI_BACKEND=metal|vulkan|gl` (or `VUI_HIDDEN_GPU=1` on Linux headless).

## File Ownership Map

| Scope | Files |
|---|---|
| Shared app host & control server | [vui/app/app.odin](vui/app/app.odin), [vui/app/control.odin](vui/app/control.odin), [vui/app/gpu.odin](vui/app/gpu.odin), [vui/app/gl.odin](vui/app/gl.odin) |
| Linux host hooks | [vui/app/platform_linux.odin](vui/app/platform_linux.odin), [tools/vui-test/platform_linux.odin](tools/vui-test/platform_linux.odin) |
| macOS host hooks | [vui/app/platform_darwin.odin](vui/app/platform_darwin.odin), [tools/vui-test/platform_darwin.odin](tools/vui-test/platform_darwin.odin) |
| Other OS fallback hooks | [vui/app/platform_other.odin](vui/app/platform_other.odin), [tools/vui-test/platform_other.odin](tools/vui-test/platform_other.odin) |
| SDL GPU renderer (shared by `vui/app` and embedding hosts) | [vui/sdlgpu/sdlgpu.odin](vui/sdlgpu/sdlgpu.odin): MSL ([vui/app/shaders/ui.metal](vui/app/shaders/ui.metal)) or SPIR-V (`vui/app/shaders/ui.{vert,frag}` + `.spv`) chosen from the device's shader formats |
| Shared GLSL bodies | `vui/app/shaders/ui_vs_body.glsl`, `vui/app/shaders/ui_fs_body.glsl` |
| WebGL2 / WASM host | [vui/web/web.odin](vui/web/web.odin), [showroom/web_main.odin](showroom/web_main.odin) |
| Hot reload (`vui-hot`) | [vui/hot/](vui/hot/) (shared ABI, fingerprints, migration, watcher; `stat_{linux,darwin,other}.odin`), [vui/app/program.odin](vui/app/program.odin), [tools/vui-hot/](tools/vui-hot/) (`platform_{linux,darwin,other}.odin`) |
| Embedded GL renderer (game hosts) | [vui/gl/gl.odin](vui/gl/gl.odin) + `loader_{darwin,linux,other}.odin`, [vui/raylib/raylib.odin](vui/raylib/raylib.odin) |

## Quick Verification Commands

### macOS

```bash
./build.sh
./build/vui-test tests/e2e/showroom.vt
VUI_BACKEND=gl VUI_HIDDEN=1 VUI_PORT=7422 ./build/showroom &
./build/vui-ctl --port 7422 info && ./build/vui-ctl --port 7422 quit
```

### Linux

```bash
./build.sh
./build/vui-test tests/e2e/showroom.vt
./scripts/check-background.sh
python3 tests/hot/test_hot.py      # when touching vui/hot, vui/app/program.odin or tools/vui-hot
```

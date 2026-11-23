# Platforms & Cross-OS Handoff

## Pending Cross-OS Verification

<!-- Add a one-line bullet when editing code for the other OS that cannot be run locally; delete it once verified there. -->

- [ ] **Linux** (from macOS commit `85038f0`): Run `./build.sh`, `./build/vui-test tests/e2e/showroom.vt`, and `scripts/check-background.sh` to verify the `platform_linux.odin` / `gpu_vulkan.odin` split and `tools/vui-test/platform_linux.odin`.

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
| Metal GPU shaders | [vui/app/gpu_metal.odin](vui/app/gpu_metal.odin) (`#+build darwin`), [vui/app/gpu_metal_stub.odin](vui/app/gpu_metal_stub.odin) (`#+build !darwin`), [vui/app/shaders/ui.metal](vui/app/shaders/ui.metal) |
| Vulkan GPU shaders | [vui/app/gpu_vulkan.odin](vui/app/gpu_vulkan.odin), `vui/app/shaders/ui.{vert,frag}` + `.spv` |
| Shared GLSL bodies | `vui/app/shaders/ui_vs_body.glsl`, `vui/app/shaders/ui_fs_body.glsl` |
| WebGL2 / WASM host | [vui/web/web.odin](vui/web/web.odin), [showroom/web_main.odin](showroom/web_main.odin) |

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
```

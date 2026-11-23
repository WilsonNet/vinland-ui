---
trigger: model_decision
description: >-
  Enforces OS isolation contracts when editing vui/app/platform_*.odin, vui/app/gpu_*.odin,
  vui/app/app.odin, vui/app/control.odin, or tools/vui-test/platform_*.odin.
---

# Platform Isolation Contract

1. **No `when ODIN_OS` in shared files**: `vui/app/app.odin`, `vui/app/control.odin`, `vui/app/gpu.odin`, and `tools/vui-test/main.odin` must stay OS-agnostic.
2. **Odin `#+build` negation syntax**: multiple negations require separate `#+build` lines (AND semantics), e.g.:
   ```odin
   #+build !linux
   #+build !darwin
   ```
   Do not combine `!linux !darwin` on one line.
3. **Required `vui_app` hooks** (must match across `platform_linux.odin`, `platform_darwin.odin`, `platform_other.odin`):
   - `platform_prepare_init :: proc(app: ^App)`
   - `platform_create_gpu_device :: proc(backend_env: string) -> ^sdl.GPUDevice`
   - `platform_gl_set_attributes :: proc()`
   - `platform_validate_gl_renderer :: proc(app: ^App, renderer: string) -> bool`
   - `platform_clipboard_fallback :: proc(allocator: mem.Allocator) -> (string, bool)`
   - `platform_foreground_hint :: proc(driver: string, focusable: bool) -> string`
4. **Required `vui_test` hooks** (must match across `tools/vui-test/platform_{linux,darwin,other}.odin`):
   - `platform_headless_env :: proc(envs: ^[dynamic]string, use_gpu: bool)`
   - `platform_verify_headless :: proc(info: json.Object, use_gpu: bool) -> (bool, string)`
5. **Cross-OS handoff**: if you change an OS file you cannot compile/run locally, add a one-line bullet under `Pending Cross-OS Verification` in `PLATFORMS.md`.

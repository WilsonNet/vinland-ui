# vinland-ui Repository Agent Rules

## Cross-OS Isolation

- Never add `when ODIN_OS` conditionals inside shared host/runner files (`vui/app/app.odin`, `vui/app/control.odin`, `vui/app/gpu.odin`, `tools/vui-test/main.odin`).
- Put OS-specific code in `platform_linux.odin`, `platform_darwin.odin`, and `platform_other.odin` using `#+build` tags.
- SDL GPU shader selection lives in `vui/sdlgpu/sdlgpu.odin` (MSL vs SPIR-V by the device's shader formats, at runtime; no OS conditionals).
- When changing any `platform_*` procedure signature or behavior contract, update all three OS implementations (`_linux`, `_darwin`, `_other`) in the same commit.

## Shader Parity

When changing `Draw_Cmd`, `Frag_Uniforms`, or any rendering primitive, update all four shader targets together:

1. OpenGL 3.3 GLSL (`vui/app/shaders/ui_vs_body.glsl`, `vui/app/shaders/ui_fs_body.glsl`, `vui/app/gl.odin`)
2. Vulkan SPIR-V (`vui/app/shaders/ui.vert`, `vui/app/shaders/ui.frag` -> `.spv` via `glslc`)
3. Metal MSL (`vui/app/shaders/ui.metal`)
4. WebGL2 (`vui/web/web.odin`)

## Cross-OS Handoff

- Read `PLATFORMS.md` ("Pending Cross-OS Verification") at the start of a session.
- Clear any pending item you verify on your current OS.
- Whenever you edit OS-specific or shader code for the *other* OS that you cannot run locally, add a one-line checkbox item to `PLATFORMS.md` before committing.

## Documentation Single Source of Truth

- **User docs** (install, CLI, background mode, testing): edit `showroom/pages_intro.odin` and `showroom/pages_testing.odin`, then regenerate `website/` MDX and `gh-pages` HTML. Never hand-edit generated `.mdx` or `.html` files.
- **Framework usage skill** (for downstream apps): `skills/vinland-ui/SKILL.md` (symlinked at `.agents/skills/vinland-ui`).
- **Platform matrix & handoff**: `PLATFORMS.md`.
- **Overview / strategy / visual system**: `README.md`, `PRODUCT.md`, `DESIGN.md`.

## Quick Verification

- **macOS**: `./build.sh && ./build/vui-test tests/e2e/showroom.vt` (plus `VUI_BACKEND=gl VUI_HIDDEN=1 ./build/showroom` when touching GL fallback)
- **Linux**: `./build.sh && ./build/vui-test tests/e2e/showroom.vt && scripts/check-background.sh`

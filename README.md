# vinland-ui

A utility-first UI framework for [Odin](https://odin-lang.org). Write UI in Odin, style it with
Tailwind CSS class names that resolve through design tokens, and let a small GPU renderer draw it
at your display's real pixel density.

![Showroom, light](docs/showroom-light.png)
![Showroom, dark](docs/showroom-dark.png)

```odin
if ui.div("flex items-center gap-4 rounded-xl bg-white p-6 shadow-lg ring-1 ring-gray-950/5 dark:bg-gray-900") {
    ui.icon(IC.sparkles, "size-6 text-violet-500")
    if ui.div() {
        ui.text("Ship it natively", "font-semibold text-gray-950 dark:text-white")
        ui.text("One binary, no webview, sharp text.", "text-sm text-gray-500")
    }
    if ui.button("Get started", "ml-auto rounded-lg bg-violet-600 px-3 py-2 text-sm font-semibold text-white hover:bg-violet-500") {
        start()
    }
}
```

## Why

Native Odin tools and games deserve UI that holds up next to a good web app. Most immediate-mode
UI libraries look "programmer art" because of two things: text and taste. vinland-ui fixes the
first in the renderer and hands the second to a vocabulary people already know.

- **Crisp text.** Glyphs are rasterized at the exact physical size (font size × display scale),
  positioned with 1/4-pixel precision and snapped to whole-pixel baselines. Windows use SDL3
  high-density mode, so fractional scales such as 1.25 or 1.333 render natively instead of being
  stretched by the compositor. Icons go through the same rasterizer.
- **Tailwind vocabulary.** `flex`, `gap-4`, `rounded-xl`, `shadow-lg`, `hover:bg-sky-600`,
  `dark:text-white`, `md:grid-cols-3`, `group-hover:`, `bg-linear-to-r from-violet-500 to-fuchsia-500`.
  The palette and scales are Tailwind CSS v4's.
- **Design tokens.** Every utility resolves through a `Theme` (colors, spacing, radii, shadows,
  type, breakpoints...). Tokens can carry light and dark values and can be loaded from JSON, so an
  app can be re-skinned without touching component code.
- **Unstyled core.** A `ui.div` is an empty box. Buttons, checkboxes, sliders and text inputs are
  behaviour only; every pixel comes from your classes.
- **Real layout.** Block flow, flexbox (grow/shrink/wrap/auto margins), grid (fr/px/auto tracks,
  spans), absolute/fixed positioning, scroll containers.
- **Vector canvas.** `ui.canvas` boxes draw charts, meters and dials with GPU primitives
  (`draw_line`, `draw_polyline`, `draw_arc`, `draw_area`, `draw_circle`), anti-aliased by SDF.
- **Fast.** Idle apps sleep; one instanced draw call per frame; a full mixing-desk UI renders in
  about 2 ms.
- **Agent-drivable.** Apps expose a local control port; `vui-ctl` clicks, types, scrolls, resizes,
  toggles dark mode, dumps the element tree and takes screenshots. An agent skill ships in
  [`skills/vinland-ui`](skills/vinland-ui/SKILL.md).

Inspired by Jetpack Compose (UI in the host language), Flutter (own the renderer), Quickshell
(small, animated desktop UI) and Tailwind CSS (the vocabulary).

## Quick start

Requirements: Odin `dev-2026-11` or newer, SDL3 development files, a Vulkan driver (or OpenGL 3.3).

```bash
git clone https://github.com/WilsonNet/vinland-ui
cd vinland-ui
./build.sh            # build/showroom, build/vui-ctl, build/hello
./build/showroom      # the documentation app
```

A first window:

```odin
package my_app

import ui "vinland:vui"
import "vinland:vui/app"
import "vinland:vui/fonts"

main :: proc() {
    ctx: ui.Context
    ui.init(&ctx)
    defer ui.destroy(&ctx)
    fonts.register(&ctx)

    a: app.App
    if !app.init(&a, {title = "Hello", size = {960, 640}, control_port = 7420}, &ctx) do return
    defer app.shutdown(&a)

    for app.next_frame(&a) {
        if ui.div("flex h-full items-center justify-center bg-white dark:bg-gray-950") {
            ui.text("Hello from Odin", "text-4xl font-semibold tracking-tight text-gray-950 dark:text-white")
        }
        app.end_frame(&a)
    }
}
```

```bash
odin build my_app -collection:vinland=path/to/vinland-ui
```

## Website

https://wilsonnet.github.io/vinland-ui/ is the showroom published as a static site that mirrors
the desktop app (same sidebar, hatched gutters, previews and code panels): every page's text,
tables and code are real HTML, previews are screenshots captured from the native showroom
(light and dark), and the component showcase runs live through WebAssembly + WebGL2.

```bash
./build.sh release
python3 tools/site/build.py build/site        # sandboxed capture + HTML into build/site
# validate with Playwright, then publish build/site to the gh-pages branch
```

GitHub Pages serves the `gh-pages` branch. (`website/` holds an experimental Astro Starlight
version that is not deployed.)

## The showroom

`showroom/` is the documentation: every Tailwind docs page (184 utility pages plus guides), each
with its class reference and, for everything the renderer draws, live examples whose code is the
real source cut from the showroom files. Search with Ctrl+K, toggle dark mode from the top bar.

## Driving an app from the terminal

```bash
VUI_HIDDEN=1 VUI_SCALE=2 ./build/showroom &      # offscreen, 2x
./build/vui-ctl nav page=box-shadow
./build/vui-ctl dark on
./build/vui-ctl screenshot shadow.png
./build/vui-ctl click-text "Show all"
./build/vui-ctl tree 6
```

See `vui-ctl --help` and the "Agent skill & CLI" page in the showroom.

## End-to-end tests (`vui-test`)

Playwright-style suites for any vinland-ui app: launch, click by text, drag, type, assert on the
element tree, take screenshots and diff them against baselines, with an HTML report.

```
# tests/e2e/showroom.vt
app ../../build/showroom
baselines baselines

test "navigate to canvas page"
  click "Canvas & charts"
  expect-text "Drawing primitives"
  expect-class "Canvas & charts" text-accent
  expect-frame-ms 40
  screenshot canvas
```

```bash
./build/vui-test tests/e2e/showroom.vt            # --update rewrites baselines
```

**Headless runs cannot touch your desktop.** `VUI_HIDDEN=1` (used by `vui-test`, agents and the
site generator) runs on SDL's offscreen video driver with Mesa's llvmpipe software rasterizer: no
compositor connection, no GPU memory, no `/dev/dri` handles, the same isolation headless browsers
get from SwiftShader. The app refuses to start headless on a hardware renderer, and `vui-test`
refuses to drive an app that is not sandboxed. `VUI_HIDDEN_GPU=1` opts into the GPU deliberately.
Visible windows keep at most one frame in flight on the GPU, and occluded windows are paced.

Why this matters: on APUs with a small VRAM carveout (e.g. Radeon 680M, 2 GB), an app that queues
GPU work faster than it retires can fill VRAM until the compositor cannot pin its scanout buffer
(`amdgpu: Not enough memory for command submission`, `prepare_fb bind failed: -ENOSPC`) and
crashes. For deliberate GPU benchmarks, wrap the run in the watchdog:

```bash
tools/gpu-guard.sh --limit 150 -- env VUI_HIDDEN=1 VUI_HIDDEN_GPU=1 ./build/showroom
# gpu-guard: vram carveout 2048 MB | start 1003 MB | after warmup 1134 MB | peak 1134 MB (+131) | OK
```

Measured (tracker, continuous rendering, 1770×1140): GPU 1.1 ms/frame with flat memory
(+115 MB, 800 frames); sandboxed llvmpipe 5 ms/frame with zero GPU memory.

## Layout of the repo

| Path | |
|---|---|
| `vui/` | core: tree builder, utility parser, tokens, layout, text, paint |
| `vui/app/` | SDL3 host (Vulkan via SDL GPU, OpenGL 3.3 fallback) and control server |
| `vui/fonts/` | embedded Inter, IBM Plex Mono, Source Serif 4 (OFL) |
| `vui/icons/` | Heroicons (MIT) |
| `tools/vui-ctl/` | control CLI |
| `tools/vui-test/` | end-to-end test runner (suites in `tests/e2e/`) |
| `tools/gen/` | generators for the palette, icons and reference tables |
| `showroom/` | documentation app |
| `skills/vinland-ui/` | skill for coding agents |

## Used by

- [tracker](https://github.com/WilsonNet/tracker): a keyboard-first multitrack recorder; its
  whole window (track strips, knobs, meters, FX rack graphs) is vinland-ui.

## Status

Early (v0.1). Linux is the tested platform; the code avoids platform specifics (SDL3, GL 3.3) but
macOS and Windows are untested. Not yet rendered: blur and backdrop filters, blend modes, masks,
3D transforms, multi-font fallback for missing glyphs, complex-script shaping (Latin text with
kerning is supported). Unsupported utilities parse without errors and are listed by
`vui-ctl info` when unknown.

## License

MIT. Bundled fonts are under the SIL Open Font License; Heroicons and the Tailwind-derived palette
and scales are MIT. See [LICENSE](LICENSE).

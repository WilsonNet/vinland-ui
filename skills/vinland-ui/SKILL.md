---
name: vinland-ui
description: >-
  Build, style, test, and visually verify native desktop UI in Odin with vinland-ui
  (Tailwind-style utility classes, design tokens, flex/grid layout, SDL3 GPU Metal/Vulkan
  renderer with OpenGL 3.3 fallback), drive running apps with vui-ctl (including headless
  VUI_HIDDEN=1 and non-focusable VUI_BACKGROUND=1 modes), and run e2e suites with vui-test.
  Use when writing or editing Odin code that imports vinland-ui (vui, vui/app, vui/fonts,
  vui/icons), porting a Tailwind/HTML design to Odin, or screenshotting/testing a vinland-ui app.
---

# vinland-ui

vinland-ui is a utility-first UI framework for Odin. UI is plain Odin code; looks come from
Tailwind CSS v4 class strings resolved through a `Theme` of design tokens. Nothing is styled
by default: an element with no classes is an invisible box.

Repository layout:

| Path | What |
|---|---|
| `vui/` | core: element tree, utility parser (`tw.odin`), tokens, layout, text, paint |
| `vui/app/` | SDL3 host (Metal on macOS, Vulkan on Linux, OpenGL 3.3 fallback) and control server |
| `vui/fonts/` | embedded Inter, IBM Plex Mono, Source Serif 4 (`fonts.register(&ctx)`) |
| `vui/icons/` | Heroicons 20 solid (`icons.register(&ctx)` returns handles) |
| `tools/vui-ctl/` | CLI that drives a running app |
| `tools/vui-test/` | Playwright-style e2e test runner (suites in `tests/e2e/`) |
| `showroom/` | documentation app: every utility with live examples (best reference) |

Build: `./build.sh` (outputs `build/showroom`, `build/vui-ctl`, `build/vui-test`, `build/hello`).

## The feedback loop (always use it)

Never assume a layout is right: render it and look. Run the app offscreen so nothing pops up on
the user's desktop, then drive it with `vui-ctl`.

```bash
./build.sh
VUI_HIDDEN=1 VUI_SCALE=2 VUI_SIZE=1280x800 ./build/my_app &   # needs control_port in app.Config
./build/vui-ctl info                     # scale, frame time, backend/driver, node count, unknown_classes
./build/vui-ctl screenshot /abs/path/shot.png      # then open it with your image viewer/Read tool
./build/vui-ctl screenshot crop.png 0 0 400 300    # crop in logical px
./build/vui-ctl click-text "Save"         # click by visible text
./build/vui-ctl click 120 48 [right|double|triple] # logical px
./build/vui-ctl foreground                # escape hatch: opt into OS focus
./build/vui-ctl background                # back to non-focusable driving
./build/vui-ctl type "hello" ; ./build/vui-ctl key tab ; ./build/vui-ctl key a ctrl
./build/vui-ctl scroll 600 [x y]          # wheel at a point (default: window center)
./build/vui-ctl dark on|off               # color scheme
./build/vui-ctl resize 700 900            # test responsive breakpoints
./build/vui-ctl settle                    # wait until animations/transitions finish
./build/vui-ctl tree 8 | jq '.nodes[] | select(.t)'   # rects, classes, text of every element
./build/vui-ctl quit
```

Input is in-process: `click`, `type` and `scroll` never move the real OS
pointer, never raise the window and never ask for focus. To keep a *visible*
window while the user keeps working or gaming, start it with
`VUI_BACKGROUND=1` (mapped without activation; X11 honors the non-focusable
hint, macOS also sets `SDL_MAC_BACKGROUND_APP=1` so no Dock icon or focus steal
occurs, and Wayland leaves focus to the compositor — use a no-focus rule there).
`vui-ctl info` reports `background`, `focusable`, `keyboard_focus`,
`mouse_inside`, `pointer_synthetic` and `video_driver`. If a flow genuinely
needs the OS window (native file dialog, IME, a human taking over), the explicit
escape hatch is `./build/vui-ctl foreground`; `./build/vui-ctl background`
returns to non-focusable driving. On Wayland a compositor may refuse to make an
existing surface focusable, in which case restart without `VUI_BACKGROUND=1`.
`VUI_HIDDEN=1` remains the fully offscreen mode with zero desktop contact and
the only hard no-focus guarantee.

Environment overrides: `VUI_HIDDEN=1` (offscreen, the hard no-desktop-contact mode),
`VUI_BACKGROUND=1` (visible but not activated on show; X11 and macOS honor the
non-focusable hints, Wayland leaves focus to the compositor), `VUI_SCALE=<f>` (UI scale; use the user's
real scale when judging text crispness, e.g. 1.3333 on a 4/3 fractional display), `VUI_SIZE=WxH`,
`VUI_PORT=<n>`, `VUI_BACKEND=metal|vulkan|gl`. App-specific commands are forwarded to `App.on_command` (the showroom adds
`nav page=<slug>`, `pages`, `search q=...`). Full-page captures: resize to a very tall window
(`VUI_SIZE=1280x7000`) so scroll containers show everything.

Check `info.unknown_classes` after every change: it lists class tokens that failed to parse.

## Validate every UI change with an e2e suite (always)

Write a `.vt` suite next to the app and run it with `vinland-ui/build/vui-test`; it launches the
app headless per test (`SDL_VIDEO_DRIVER=offscreen` + Mesa llvmpipe on Linux; hidden Cocoa window
with `SDL_MAC_BACKGROUND_APP=1` on macOS), so it is safe to run any number of times:

```
app ../bin/my-app --data {test}/data     # {test}: fresh scratch dir per test
size 1180x760
baselines baselines
test "save flow"
  click "Save"                  # exact-text match first, then substring
  expect-text "saved"
  expect-class "Save" bg-sky-600
  drag-text "Volume" 0 -40      # drags: also drag X1 Y1 X2 Y2
  type ":"   key escape   scroll -120 400 300   resize 900 620
  expect-frame-ms 40            # perf budget (software renderer)
  screenshot saved              # diffed against baselines/saved.png
```

Look at the screenshots (report.html) after each run; never claim a UI works without them.
Never run a GUI app on the real GPU from an agent: always `VUI_HIDDEN=1` (sandboxed) and never
set `VUI_HIDDEN_GPU`, except for an explicit GPU benchmark wrapped in
`vinland-ui/tools/gpu-guard.sh --limit 150 -- <cmd>` (kills runaway GPU memory before the
compositor starves). `vui-test` owns the sandbox environment and rejects suite `env` overrides
of `VUI_HIDDEN`, `SDL_VIDEO_DRIVER`, `DISPLAY` and `WAYLAND_DISPLAY`; do not try to make a
suite visible.

## Minimal app

```odin
package my_app

import ui "vinland:vui"          // or a relative path: "../vinland-ui/vui"
import "vinland:vui/app"
import "vinland:vui/fonts"

main :: proc() {
	ctx: ui.Context
	ui.init(&ctx)
	defer ui.destroy(&ctx)
	fonts.register(&ctx)

	a: app.App
	if !app.init(&a, {title = "My app", size = {1100, 720}, control_port = 7420}, &ctx) do return
	defer app.shutdown(&a)

	for app.next_frame(&a) {
		if ui.div("flex h-full flex-col bg-white dark:bg-gray-950") {
			ui.text("Hello", "p-8 text-2xl font-semibold text-gray-950 dark:text-white")
		}
		app.end_frame(&a)
	}
}
```

Build with `odin build my_app -collection:vinland=path/to/vinland-ui`.

## Element API (package `vui`, usually imported as `ui`)

| Call | Use |
|---|---|
| `if ui.div(class) { ... }` | container; closes automatically at the end of the `if` block. **Always use with `if`.** |
| `ui.open(class)` / `ui.close()` | manual container scope (for helpers that open on behalf of a caller) |
| `ui.el(class)` | leaf box: dividers, swatches, bars, spacers |
| `ui.text(str, class)` | text element (one run) |
| `if ui.p(class) { ui.span(str, class) ... }` | paragraph with styled inline runs (bold word, inline code, links) |
| `ui.icon(handle, "size-5 text-gray-500")` | vector icon; color from `text-*` or `fill-*` |
| `ui.image(img, "h-48 w-full object-cover rounded-lg")` | raster image (`ui.image_register(ctx, rgba, w, h)`) |
| `ui.button(label, class, flags) -> bool` | focusable text button; true when activated |
| `if ui.button_box(class) { ...; if ui.clicked() {} }` | button with arbitrary content |
| `if ui.pressable(class) {}` | clickable/focusable container without pointer cursor |
| `if ui.checkbox(&b, class) {}` / `if ui.radio(&v, option, class) {}` | toggles state, sets `checked:` |
| `ui.slider(&v, lo, hi, track, fill, thumb, step)` | horizontal slider |
| `ui.text_input(&buf, class, placeholder) -> {changed, submitted}` | single-line field (`[dynamic]u8`) |
| `ui.canvas(class, draw_proc, data)` | custom drawing inside a laid-out box |

Interaction is queried on the innermost open element: `ui.clicked()`, `ui.hovered()`,
`ui.active()`, `ui.focused()`, `ui.double_clicked()`, `ui.right_clicked()`. For the element just
created by a leaf call use `ui.last_clicked()`, `ui.last()`, `ui.last_style()`.

State flags (4th-ish param `flags: ui.Elem_Flags`): `{.Selected}`, `{.Checked}`, `{.Disabled}`,
`{.Open}`, `{.Focusable}`, `{.No_Hit}` drive the `aria-selected:`, `checked:`, `disabled:`, `open:`
variants. Example: `ui.button(label, "... aria-selected:bg-white", i == tab ? {.Selected} : {})`.

Identity: elements are keyed by call site + occurrence, so loops just work. When list items can
reorder, call `ui.key(item.id)` before the element. Use `ui.push_id(x)`/`ui.pop_id()` around a
reused helper that is called from the same line in a loop.

Dynamic values: build class strings with `ui.cx("p-4", cond ? "bg-sky-500" : "")` or
`fmt.tprintf("bg-%s-500", name)`, or set fields after classes apply:
`ui.el("h-2 rounded-full bg-violet-500"); ui.last_style().width = ui.pct(progress)`.
Persistent per-element state: `p := ui.remember(f32, 0)` (like Compose `remember`).
Scrolling: `ui.scroll_to(container_id, y)`, `ui.rect_of(id)`, `ui.scroll_of(id)`.

## Utilities

Tailwind CSS v4 names and semantics. Supported and rendered:

- Layout: `block inline inline-block flex inline-flex grid hidden`, `relative absolute fixed sticky`
  (sticky behaves like relative), `inset-* top-* right-* bottom-* left-*`, `z-*`, `overflow-*`
  (`auto`/`scroll` = scroll container with smooth wheel + draggable overlay scrollbar), `visible invisible`,
  `aspect-*`, `box-border box-content`, `object-*` fit and position.
- Flex/grid: `flex-row/col(-reverse)`, `flex-wrap(-reverse)/nowrap`, `flex-1/auto/initial/none`,
  `grow* shrink* basis-*`, `order-*`, `gap-* gap-x-* gap-y-*`, `justify-*`, `items-*`, `self-*`,
  `content-*`, `place-*`, `justify-items-* justify-self-*`, `grid-cols-N`, `grid-cols-[200px_1fr_auto]`,
  `grid-rows-*`, `col-span-* col-start-* col-end-* row-*`, `grid-flow-row/col(-dense)`, `auto-cols-* auto-rows-*`.
- Spacing/sizing: `p* m*` (incl. negative and `mx-auto`), `space-x/y-*`, `divide-x/y(-*)`,
  `w-* h-* size-* min-* max-*` with numbers, fractions (`w-1/2`), `full screen min max fit px`,
  container sizes (`max-w-md`, `max-w-prose`), arbitrary (`w-[340px]`, `h-[60vh]`).
- Typography: `font-sans/serif/mono`, `text-xs … text-9xl`, `text-sm/6` (size/line-height),
  `text-[13px]/6`, `font-thin … font-black`, `italic`, `tracking-*`, `leading-*`, `text-<color>`,
  `text-left/center/right`, `underline overline line-through`, `decoration-*` (color, style incl. wavy,
  thickness), `underline-offset-*`, `uppercase lowercase capitalize`, `truncate`, `line-clamp-*`,
  `whitespace-*`, `text-wrap/nowrap`, `break-all wrap-anywhere`, `text-shadow-*` (offset only, no blur).
- Backgrounds: `bg-<color>` (opacity modifiers `bg-black/50`), gradients `bg-linear-to-r`,
  `bg-linear-45`, `bg-radial`, `bg-conic`, `from-* via-* to-*` with positions `from-10%`,
  pattern `bg-stripes stripes-<color> bg-stripes-<period>` (vinland-ui extension).
- Borders: `rounded-*` (per side/corner), `border-*` widths/colors per side, `border-dashed/dotted/double`,
  `outline-* outline-offset-*`, `ring-* ring-offset-* inset-ring-*`.
- Effects: `shadow-*` (true gaussian), `shadow-<color>/50`, `inset-shadow-*`, `drop-shadow-*`
  (approximated as box shadow), `opacity-*`.
- Filters: `grayscale sepia invert brightness-* contrast-* saturate-* hue-rotate-*` (color matrix).
- Motion: `transition(-colors|-opacity|-shadow|-transform|-all|-none)`, `duration-* delay-* ease-*`,
  `animate-spin/ping/pulse/bounce`.
- Transforms: `translate-* scale-* rotate-* skew-* origin-*` (hit testing follows transforms).
- Interactivity: `cursor-*`, `pointer-events-none`, `select-none`, `caret-*`, `selection:bg-*`,
  `placeholder:text-*`, `accent-*`, `fill-*`.

Variants: `hover: focus: focus-visible: focus-within: active: disabled: enabled: first: last: odd:
even: only: not-first: not-last: dark: group-hover: group-focus: group-active: aria-selected:
checked: open: *: placeholder: selection: sm: md: lg: xl: 2xl: max-md: min-[900px]:`.
`group` marks the parent for `group-*` variants. `*:` applies to direct children.

Parsed but not drawn (accepted so markup ports): `blur-*`, `backdrop-*`, `mix-blend-*`, masks,
`float`, `columns`, scroll-snap, 3D transforms, tables (`border-collapse` etc.). Do not rely on them
for visible results; build the effect another way.

## Custom drawing: charts, meters, dials

`ui.canvas(class, draw, data)` is a normal laid-out box whose content is drawn by
`draw :: proc(ctx: ^ui.Context, r: ui.Rect, data: rawptr)` each frame, in logical window
coordinates. Primitives (one GPU instance each, SDF anti-aliased, no CPU tessellation):

| Call | Draws |
|---|---|
| `ui.draw_rect(ctx, rect, color, radius)` | filled rounded rect |
| `ui.draw_line(ctx, a, b, color, width)` | segment, round caps |
| `ui.draw_polyline(ctx, pts, color, width)` | curve / waveform |
| `ui.draw_arc(ctx, center, r, start, sweep, color, width)` | arc, radians clockwise from +x |
| `ui.draw_circle(ctx, center, r, color)` | disc |
| `ui.draw_area(ctx, pts, base_y, top, bottom)` | gradient fill under a curve (x ascending) |

Pass per-instance data with `d := new(T, context.temp_allocator)` (reset after each frame).
Read colors from tokens: `ui.theme().colors["accent"].dark`. A 270° knob is
`draw_arc(c, r, 0.75*PI, 1.5*PI, track)` + `draw_arc(..., 1.5*PI*v, accent)` + a `draw_line`
pointer. Drag: inside the element, `ui.active() && .Left in ui.ctx_get().input.pressed` starts it;
follow `ctx.input.mouse` while `.Left in ctx.input.buttons`.

Colors: `ui.oklch(l, c, h)` and `"oklch(...)"` in JSON themes, same space as Tailwind v4.

## Game UI and embedding in a game

- Geometry: `corner-{bevel,scoop,notch,arch}` (per corner: `corner-tl-scoop`, `corner-t-arch`); the
  size comes from `rounded-*`. An arch's `rounded-t-[h]` is its height (more than half the width =
  pointed). Borders, rings, insets and hard shadows follow the shape.
- Textures: `vui/materials.register(&ctx)` adds tileable `hammered brushed grain stone parchment
  weave` (relief: multiply the bg colour/gradient) and `khatam interlace studs` (alpha masks: tint
  with a bg colour). Use `bg-tex-<name> bg-tile-<px>`. Any image named with `ui.image_name(ctx,
  name, img)` works too, including host textures from `ui.image_register_external`.
- Fonts/icons: `vui/fonts/game.register` (`font-display` Cinzel, `font-decorative` Cinzel Decorative
  for single words, `font-game` Alegreya Sans), `vui/icons/game.register` (attack, move, patrol, stop, follow, scroll, khatam, heart, helm).
- In an SDL3 GPU game: `vui/sdlgpu` (`init(&r, dev, color_format, depth_format)`, then per frame
  `prepare(&r, ctx, draw, cmd)` before any render pass and `draw(&r, ctx, draw, cmd, pass, w, h)`
  inside the pass that should show the HUD). External images are `SDL_GPUTexture` pointers;
  `image_register_external(..., nearest = true)` samples pixel maps unfiltered.
- In a raylib game: `vui/raylib` (`init`, `input`, `begin`/`end`, `render` after the world,
  `pointer_over_ui(host, mouse)` to route world clicks, `texture_image` for minimaps and render
  targets). Other GL hosts use `vui/gl` directly. Build the HUD after the camera update so
  world-anchored labels never lag.
- Decorative absolute overlays (patterns, friezes) must be `pointer-events-none`: positioned
  elements paint and hit-test above in-flow siblings.
- Leaf boxes are `ui.el(...)`; `ui.div(...)` without `if` nests everything after it.
- Per-frame dynamic geometry (positions, bar widths): set `ui.style()` / `ui.last_style()` fields
  instead of formatting class strings, so the class cache does not grow every frame.

## Performance rules

vinland-ui must beat a webview, so keep frames cheap: the loop idles when nothing changes
(`app.next_frame` blocks); call `app.request_redraw(&a)` only while something is live (meters,
playback). Avoid per-frame heap allocation (use `context.temp_allocator`). Prefer one canvas with
many primitives over hundreds of tiny elements. Check `vui-ctl info` → `frame_ms`, `draw_cmds`.

## Host hooks

`app.Config.app_id` sets the Wayland app id / X11 class (window rules). `a.on_event = proc(app, e)
-> bool` sees raw SDL events first (return true to consume): use it for global keymaps.

## Design tokens

`ctx.theme` (`ui.Theme`) holds spacing unit, colors, radii, shadows, type scale, weights, tracking,
leading, breakpoints, container widths, blur, easings and font families. Prefer semantic tokens for
app chrome so dark mode and re-theming need no code changes:

```odin
t := &ctx.theme
ui.theme_set_color(t, "canvas", ui.WHITE, ui.rgb(0x030712))      // light, dark
ui.theme_set_color(t, "ink", ui.rgb(0x030712), ui.WHITE)
ui.theme_set_color(t, "accent", t.colors["violet-600"].light, t.colors["violet-400"].light)
t.radius["card"] = 14
ui.theme_changed()                       // after mutating maps directly
// then: "bg-canvas text-ink rounded-card ring-accent"
```

Themes also load from JSON: `ui.theme_load_json(&ctx.theme, "theme.json")` with keys `colors`
(string or `{light, dark}`), `radius`, `fonts`, `textSizes`, `breakpoints`, `containers`, `tracking`,
`leading`, `spacing`. Dark mode: `ui.set_dark(bool)`.

## Layout rules that differ from the web

- Everything is border-box. Margins never collapse.
- Block flow stacks block children and stretches them; inline-level children (`inline-block`,
  `inline-flex`) flow on lines with baseline alignment. Use `ui.p` + `ui.span` for real inline text.
- Flex items have `min-width: auto`: add `min-w-0` on an item that must shrink below its content
  (needed for `truncate` inside flex rows).
- `h-full` only resolves when the parent has a definite height. App roots should start with
  `"flex h-full flex-col"` and use `min-h-0 flex-1 overflow-y-auto` for scroll regions.
- `fixed` elements paint above everything (overlays, modals, palettes); give them `z-*` to order.
- Interaction state is from the previous frame's layout (one-frame latency, invisible in practice).

## Gotchas

- `ui.div` without `if` closes at the end of the *enclosing* block and swallows later siblings.
- `leading-[1.4]` is a multiplier (CSS semantics); `leading-[22px]` is absolute.
- Offscreen runs (`VUI_HIDDEN=1`) are paced at 60 fps with one frame in flight; keep captures
  at normal window sizes (the framebuffer is capped at 4096 px).
- Strings passed to `ui.text`/`ui.span` are copied into the frame arena, so `fmt.tprintf` is fine.
- In Odin's `fmt`, `{` and `}` are format characters: write `{{` and `}}` for literal braces.
- Text is drawn at physical pixels; never scale a text element with a transform to "zoom" text,
  change `text-*` instead (transforms are fine for animation).
- The renderer is SDL3 GPU (Metal on macOS, Vulkan on Linux) with an OpenGL 3.3 fallback (`VUI_BACKEND=gl`); games with their own renderer can call `ui.begin_frame`,
  build, `ui.end_frame` and draw the returned `Draw_List` (see `vui/app/shaders/` and `vui/app/gl.odin` for the shader).

## Workflow for a new screen

1. Sketch the structure as nested `ui.div`s with layout classes only; screenshot.
2. Add typography and color with tokens; check light and dark (`vui-ctl dark on`).
3. Add states (`hover:`, `focus-visible:`, `disabled:`), check keyboard focus with `vui-ctl key tab`.
4. Resize through breakpoints (`vui-ctl resize 640 900`, `1024`, `1440`).
5. Check `vui-ctl info` for `unknown_classes` and frame time.
6. For more patterns, read the matching page source in `showroom/pages_*.odin`.

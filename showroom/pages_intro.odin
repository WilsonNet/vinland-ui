package showroom

import "core:fmt"
import "core:strings"
import ui "../vui"

register_pages :: proc() {
	page("Getting started", "introduction", "Introduction", "vinland-ui is a utility-first UI framework for Odin. You write UI in Odin, style it with Tailwind-style classes that resolve through design tokens, and a GPU renderer draws it at your display's real pixel density.", page_introduction)
	page("Getting started", "installation", "Installation", "Add vinland-ui to an Odin project and open your first window.", page_installation)
	page("Getting started", "hot-reload", "Hot reload", "Optional: edit, save, and the running window picks up the new code in about a second, keeping its state. A plain odin build stays the default.", page_hot_reload)
	page("Getting started", "agents", "Agent skill & CLI", "Drive a running app from the terminal: navigate, click, type, and take screenshots. Built for AI agents and tests.", page_agents)
	page("Getting started", "testing", "Testing", "Playwright-style end-to-end tests for native apps: click by text, assert on the element tree, diff screenshots against baselines. Headless runs are sandboxed.", page_testing)
	page("Getting started", "showcase", "Component showcase", "Interfaces assembled from utilities only. Nothing on this page is a built-in widget style.", page_showcase)
	page("Core concepts", "utility-classes", "Styling with utility classes", "Build any design by combining single-purpose classes directly in your Odin code.", page_utility_classes)
	page("Core concepts", "states", "Hover, focus and other states", "Prefix a utility with a variant to apply it conditionally.", page_states)
	page("Core concepts", "responsive-design", "Responsive design", "Breakpoint variants adapt a layout to the window width.", page_responsive)
	page("Core concepts", "dark-mode", "Dark mode", "Style for a dark color scheme with the dark: variant, or with tokens that carry both values.", page_dark_mode)
	page("Core concepts", "theme-tokens", "Theme tokens", "Every utility resolves through a Theme. Change the tokens and the whole app follows, without touching component code.", page_tokens)
	page("Core concepts", "colors", "Colors", "The default palette: 26 families with 11 shades each, matching Tailwind CSS v4 converted to sRGB.", page_colors)
	page("Core concepts", "layout-engine", "Layout engine", "How boxes are measured and placed: block flow, flexbox, grid and positioning.", page_layout_engine)
	page("Core concepts", "canvas", "Canvas & charts", "Draw charts, meters and dials with vector primitives inside the layout: lines, arcs, curves and gradient fills.", page_canvas)
	page("Core concepts", "game-ui", "Game UI", "Skeuomorphic HUDs for games: ornate corner shapes, textured materials, orb gauges and inventories, embeddable in a game's own GL context.", page_game_ui)
	page("Core concepts", "text-rendering", "Text rendering", "Why text in vinland-ui looks as sharp as in a browser, and the rules the renderer follows.", page_text_rendering)

	register_layout_examples()
	register_flex_examples()
	register_spacing_examples()
	register_typography_examples()
	register_visual_examples()
	register_motion_examples()
	register_interactivity_examples()

	for rp, i in REF_PAGES {
		page(rp.group, rp.slug, rp.title, rp.desc, nil, i)
	}
}

// Utilities the native renderer accepts but does not draw yet.
UNRENDERED := [?]string{"columns", "break-after", "break-before", "break-inside", "box-decoration-break", "float", "clear", "isolation", "overscroll-behavior", "inline-size", "min-inline-size", "max-inline-size", "block-size", "min-block-size", "max-block-size", "font-smoothing", "font-stretch", "font-feature-settings", "list-style-image", "tab-size", "vertical-align", "hyphens", "content", "background-attachment", "background-clip", "background-origin", "background-position", "background-repeat", "mix-blend-mode", "background-blend-mode", "mask-clip", "mask-composite", "mask-image", "mask-mode", "mask-origin", "mask-position", "mask-repeat", "mask-size", "mask-type", "filter-blur", "backdrop-filter", "backdrop-filter-blur", "backdrop-filter-brightness", "backdrop-filter-contrast", "backdrop-filter-grayscale", "backdrop-filter-hue-rotate", "backdrop-filter-invert", "backdrop-filter-opacity", "backdrop-filter-saturate", "backdrop-filter-sepia", "border-collapse", "border-spacing", "table-layout", "caption-side", "transition-behavior", "backface-visibility", "perspective", "perspective-origin", "transform-style", "zoom", "appearance", "color-scheme", "field-sizing", "resize", "scroll-behavior", "scrollbar-color", "scrollbar-width", "scrollbar-gutter", "scroll-margin", "scroll-padding", "scroll-snap-align", "scroll-snap-stop", "scroll-snap-type", "touch-action", "will-change", "forced-color-adjust", "stroke", "stroke-width"}

ref_page_render :: proc() {
	p := PAGES[s.page]
	rp := REF_PAGES[p.ref]
	rows := make([dynamic]Row, context.temp_allocator)
	text := rp.rows
	for line in strings.split_lines_iterator(&text) {
		tab := strings.index_byte(line, '\t')
		if tab < 0 {
			continue
		}
		append(&rows, Row{line[:tab], line[tab + 1:]})
	}
	if len(rows) > 0 {
		ref_table(rows[:])
	}
	unrendered := false
	for u in UNRENDERED {
		if u == p.slug {
			unrendered = true
		}
	}
	if ex, ok := EXAMPLES[p.slug]; ok {
		h2("Examples")
		ex()
	} else if unrendered {
		note("vinland-ui parses these classes so markup ports cleanly between projects, but the native renderer does not draw this property yet. Unknown or unsupported utilities never crash: they are reported by `vui-ctl info` under `unknown_classes` when they fail to parse.")
	}
}

// ---------------------------------------------------------------------------

page_introduction :: proc() {
	if example("p-10") {
		if ui.div("w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl ring-1 ring-gray-950/5 dark:bg-gray-900 dark:ring-white/10") {
			if ui.div("flex items-center gap-4") {
				if ui.div("flex size-12 shrink-0 items-center justify-center rounded-full bg-violet-100 dark:bg-violet-500/20") {
					ui.icon(IC.sparkles, "size-6 text-violet-600 dark:text-violet-300")
				}
				if ui.div("min-w-0") {
					ui.text("Ship it natively", "text-base font-semibold text-gray-950 dark:text-white")
					ui.text("One binary, no webview, sharp text.", "text-sm text-gray-500 dark:text-gray-400")
				}
			}
			if ui.div("mt-6 flex gap-3") {
				ui.button("Get started", "flex-1 rounded-lg bg-violet-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-sm transition-colors hover:bg-violet-500")
				ui.button("Docs", "rounded-lg px-3 py-2 text-sm font-semibold text-gray-950 ring-1 ring-gray-950/10 transition-colors hover:bg-gray-50 dark:text-white dark:ring-white/15 dark:hover:bg-white/5")
			}
		}
	}
	h2("What it is")
	para("A small set of Odin packages. `vui` holds the element tree, the utility parser, design tokens, layout, text shaping and painting. `vui/app` is a host built on SDL3 GPU (Metal on macOS, Vulkan on Linux) with an OpenGL 3.3 fallback that owns the window, input and the control server. `vui/sdlgpu` draws vui inside another program's SDL3 GPU render pass (games), and `vui/gl` + `vui/raylib` do the same for OpenGL/raylib hosts. `vui/fonts` embeds Inter, IBM Plex Mono and Source Serif 4, and `vui/icons` ships Heroicons.")
	para("The core never draws anything on its own. A `ui.div` is an empty box until you give it classes, so the look of an app lives entirely in your code and in your theme.")
	h2("How it reads")
	para("Containers open with `if ui.div(\"...\") { }` and close automatically at the end of the block. Leaves such as `ui.text`, `ui.icon` and `ui.el` take a class string. Interaction is queried where you build: `ui.clicked()`, `ui.hovered()` and friends refer to the element you are inside.")
	code(`count := 0
for app.next_frame(&a) {
    if ui.div("flex h-full items-center justify-center bg-gray-50") {
        if ui.button(fmt.tprintf("Clicked %d times", count), "rounded-full bg-gray-950 px-4 py-2 text-sm font-semibold text-white hover:bg-gray-800") {
            count += 1
        }
    }
    app.end_frame(&a)
}`)
	h2("Inspiration")
	para("Jetpack Compose showed that UI can live in the host language. Flutter showed the value of owning the renderer end to end. Quickshell showed how good small desktop widgets can feel when animation is cheap. Tailwind CSS supplied the vocabulary: if you know Tailwind, you already know how to style vinland-ui.")
}

page_installation :: proc() {
	h2("Requirements")
	para("Odin (dev-2026-11 or newer), SDL3 development files, and Metal (macOS) or Vulkan (Linux) with automatic OpenGL 3.3 fallback. Fonts and icons are embedded, so there is nothing else to install.")
	code(`# macOS
brew install odin sdl3
# Arch
sudo pacman -S sdl3
# Debian / Ubuntu
sudo apt install libsdl3-dev`, "sh")
	h2("Add the packages")
	para("Clone the repository next to your project (or as a git submodule) and import the packages by path, or register a collection with `-collection:vinland=path/to/vinland-ui`.")
	code(`git clone https://github.com/WilsonNet/vinland-ui
odin build my_app -collection:vinland=vinland-ui`, "sh")
	h2("A first window")
	code(`package my_app

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
}`)
	h2("Or describe the app as a Program")
	para("`app.run` takes the same app as callbacks and owns the context, window and loop. It builds and runs exactly like the loop above, and it is what lets `vui-hot` reload the code without closing the window (see Hot reload).")
	code(`State :: struct { count: int }
s: State

main :: proc() {
    app.run({
        config = {title = "Counter", size = {480, 320}},
        setup  = proc(a: ^app.App) { fonts.register(a.ctx); app.keep(&s) },
        frame  = proc(a: ^app.App) {
            if ui.button(fmt.tprintf("Clicked %d times", s.count), "rounded-lg bg-sky-600 px-4 py-2 text-white") {
                s.count += 1
            }
        },
    })
}`)
	h2("Bring your own renderer")
	para("Games that already own a render loop (raylib, Vulkan, Metal, a custom engine) can skip `vui/app`: call `ui.begin_frame` with your input, build, call `ui.end_frame` and draw the returned `Draw_List`. Each command is one instanced quad; `vui/app/shaders/` (GLSL and MSL) and `vui/app/gl.odin` are the reference implementations of the uber-shader.")
}

page_hot_reload :: proc() {
	para("Odin compiles a whole app in about a second, so rebuilding by hand is already fast. What a rebuild loses is the running state: the page you navigated to, a half-filled form, the scroll position, dark mode. `vui-hot` keeps the process and the window alive and swaps only the code, so a save shows its effect in place. It is a development tool and entirely optional: the same package still builds with `odin build` into a normal executable that contains no reload code.")
	code(`./build.sh                         # builds build/vui-hot too
./build/vui-hot examples/counter   # edit examples/counter/main.odin and save
./build/vui-hot showroom -- --page=colors --dark`, "sh")
	h2("What survives a reload")
	ref_table({
		{"window, GPU device, GL context", "never recreated; the swap itself takes about 2 ms"},
		{"ui.Context", "widget state (scroll offsets, focus, hover, text edits, animations), caches, fonts, icons, images"},
		{"app.keep(&global)", "your state, carried over and migrated when its type changes"},
		{"other package globals", "start from their initial values in the new build (setup fills them again)"},
	})
	para("An app written as an `app.Program` gets all of the above. `setup` runs on every load (the first start and after each reload): register fonts, icons and lookup tables there (vui's register procs are idempotent by name), call `app.keep` on the globals that hold state, and set `a.on_command`. `init` runs once per window, so initial values are not reapplied after a reload. A classic `for app.next_frame` loop also reloads, but its own defers close the window, so it reopens on every reload (kept globals still carry over).")
	h2("Changing types while it runs")
	para("A kept value is copied as-is when its type is unchanged. When the type changed it is migrated instead of thrown away: struct fields are matched by name (recursively), fixed arrays element by element, and integers and floats are converted when only their size changed. New fields keep their default, removed fields are dropped, and a field whose type changed in an incompatible way is reset. A value is never reinterpreted and an integer that does not fit its new type is not wrapped. `vui-hot` prints what happened, and `vui-ctl info` lists it under `hot.notes`.")
	code(`vui-hot: &s migrated: kept 3, added: theme, reset: spare`, "sh")
	para("An edit to vui itself that changes the layout of `App` or `ui.Context` cannot be swapped under a live window: the old build closes it, the new build opens a new one in the same process, and kept globals are still restored.")
	h2("When something goes wrong")
	ref_table({
		{"compile error", "the previous build keeps running; the compiler output is drawn over the app and printed in the terminal"},
		{"crash right after a reload", "the app restarts on the previous good build and shows which build crashed"},
		{"crash later", "the app restarts on the current build; after 3 crashes in 10 s vui-hot waits for the next change"},
		{"edit during a build", "the stale compile is cancelled and the newest code is built"},
		{"vui-hot stops (Ctrl+C, killed)", "the app exits with it; old builds are deleted"},
	})
	note("A restart after a crash starts the app fresh: kept state lives in the crashed process. Element ids come from source locations, so an edit that moves lines above a stateful element (a scroll container, a focused input) can reset that element; give it a `ui.key` to pin it.")
	h2("Options")
	ref_table({
		{"-collection:name=dir", "passed to odin and used to follow imports (vinland is found automatically)"},
		{"-<odin flag>", "any other odin flag, e.g. -o:none or -define:X=1 (default -debug)"},
		{"--watch <path>", "also watch a file or directory"},
		{"--out <dir>", "build directory (default build/hot/<package>)"},
		{"--poll <ms> / --debounce <ms>", "scan interval (100) and quiet period after a change (30)"},
		{"--no-restart / --quiet", "exit when the app crashes / print only errors"},
		{"-- <args>", "arguments for the app"},
		{"VUI_HOT_OVERLAY=0", "hide the in-window build status"},
	})
	para("vui-hot watches the package directory, every local package it imports and every file it pulls in with `#load`; it re-reads imports after each edit, so a newly imported package is watched at once. A save that leaves the bytes unchanged never rebuilds. Polling costs well under 1% of one core.")
	h2("Cost and limits")
	para("A reload costs the compile (about 1.1 s for the showroom, the same as a normal build) plus about 2 ms to swap the library in. Every previous build stays mapped until the app exits, because live state can still point at its string literals and code; the kernel can drop those pages, and each build releases its scratch arenas when it hands over. For the showroom, private memory grows by a few MB per reload at first and levels off (32 MB at start, 76 MB after 12 reloads, 80 MB after 24). Keep the build directory on disk rather than tmpfs (vui-hot warns), where mapped old builds could never be dropped.")
	para("Procedure values stored in kept state keep calling the build that created them until they are assigned again, which `setup` usually does. State shared with another thread should be kept through a pointer so both sides see the same object. Hot reload is verified on Linux; macOS and Windows are pending (see PLATFORMS.md).")
	h2("Driving it from tests and agents")
	para("Under vui-hot, `vui-ctl info` adds a `hot` object: `generation`, `reloads`, `status` (`Idle`, `Building`, `Error`), `error`, `build_ms`, `swap_ms`, `pid` and `notes`. A script can save a file and poll until `generation` increases. `tests/hot/test_hot.py` runs the whole matrix sandboxed (`VUI_HIDDEN=1`).")
	code(`VUI_HIDDEN=1 VUI_PORT=7421 ./build/vui-hot examples/counter &
./build/vui-ctl --port 7421 info | jq .hot`, "sh")
}

page_agents :: proc() {
	para("Every vinland-ui app can expose a local control port. `vui-ctl` speaks to it, which gives agents and tests the same feedback loop a person gets from looking at the screen.")
	h2("Run an app headless")
	code(`# render offscreen at a fixed scale; nothing appears on your desktop
VUI_HIDDEN=1 VUI_SCALE=2 VUI_SIZE=1440x900 ./build/showroom &

./build/vui-ctl info
./build/vui-ctl nav page=box-shadow
./build/vui-ctl dark on
./build/vui-ctl screenshot shadow-dark.png
./build/vui-ctl click-text "Show all"
./build/vui-ctl scroll 600
./build/vui-ctl tree 6 | jq '.nodes[] | select(.t)'`, "sh")
	h2("Drive a visible app without stealing input")
	para("Pointer and key commands are injected inside the app: they never warp or click the real OS pointer, raise the window or request focus. When the window should stay visible while someone else uses the machine, start it with `VUI_BACKGROUND=1`. It is mapped without activation and with the non-focusable hint (plus `SDL_MAC_BACKGROUND_APP=1` on macOS so no Dock icon or focus steal occurs), so a game or editor normally keeps keyboard and pointer focus. X11 window managers and macOS honor the hints; Wayland leaves focus policy to the compositor, where a no-focus rule is the reliable option.")
	code(`VUI_BACKGROUND=1 VUI_PORT=7420 ./build/my_app &
./build/vui-ctl info          # background:true, focusable:false, keyboard_focus:false
./build/vui-ctl click-text "Save"
./build/vui-ctl foreground    # escape hatch: native dialog, IME, human takeover
./build/vui-ctl background    # back to non-focusable driving`, "sh")
	para("A compositor may refuse to make an existing Wayland surface focusable; the foreground response reports that, and restarting without `VUI_BACKGROUND=1` is the fallback for flows that need native focus.")
	h2("Commands")
	ref_table({
		{"info", "viewport, scale, frame time, backend/driver, focus state, node count, unknown classes, hot reload status (hot)"},
		{"screenshot <png> [x y w h]", "writes the last frame (optionally cropped)"},
		{"click <x> <y> [right|double|triple]", "synthetic click in logical px"},
		{"click-text <text> [nth]", "clicks the element whose text matches"},
		{"move / scroll / type / key", "pointer, wheel and keyboard input"},
		{"foreground / background", "opt into OS focus / return to non-focusable driving"},
		{"release", "drop a stuck synthetic button or drag"},
		{"resize <w> <h> / dark [on|off]", "window size and color scheme"},
		{"tree [depth]", "element tree with rects, classes and text as JSON"},
		{"settle / wait [frames]", "block until animations finish"},
		{"<app command> key=value", "forwarded to App.on_command (nav, pages, search...)"},
	})
	h2("Agent skill")
	para("The repository ships `skills/vinland-ui/SKILL.md` (symlinked at `.agents/skills/vinland-ui` for automatic agent discovery). It teaches the element API, the utility vocabulary, the token system and this CLI loop, so an agent can build a screen, screenshot it and iterate without a human in the loop.")
}

// ---------------------------------------------------------------------------

page_utility_classes :: proc() {
	para("Each class does one thing: `p-6` sets padding, `rounded-xl` sets the corner radius, `shadow-lg` adds an elevation shadow. You combine them on the element instead of writing a style sheet.")
	if example() {
		if ui.div("flex w-full max-w-sm items-center gap-x-4 rounded-xl bg-white p-6 shadow-lg outline outline-black/5 dark:bg-slate-800 dark:shadow-none dark:-outline-offset-1 dark:outline-white/10") {
			if ui.div("flex size-12 shrink-0 items-center justify-center rounded-full bg-sky-500") {
				ui.icon(IC.chat_bubble_left, "size-6 text-white")
			}
			if ui.div() {
				ui.text("ChitChat", "text-xl font-medium text-black dark:text-white")
				ui.text("You have a new message!", "text-gray-500 dark:text-gray-400")
			}
		}
	}
	h2("Why it works")
	para("Class strings are parsed once and cached, so a frame costs a hash lookup per element, not a parse. Because styling stays next to structure, you can read a component and know exactly how it looks.")
	h2("Dynamic values")
	para("When a value comes from data, build the string with `ui.cx` or set the style directly after the classes are applied with `ui.style()` or `ui.last_style()`.")
	if example() {
		pct := remember_progress()
		if ui.div("w-full max-w-sm") {
			if ui.div("h-2 w-full overflow-hidden rounded-full bg-gray-200 dark:bg-white/10") {
				ui.el("h-full rounded-full bg-violet-500")
				ui.last_style().width = ui.pct(pct^)
			}
			ui.text(fmt.tprintf("%.0f%% complete", pct^), "mt-2 text-sm text-gray-600 dark:text-gray-400")
		}
	}
}

remember_progress :: proc() -> ^f32 {
	p := ui.remember(f32, 0)
	p^ = f32(int(ui.ctx_get().time * 20) % 101)
	ui.ctx_get().animating = true
	return p
}

page_states :: proc() {
	para("Variants such as `hover:`, `focus-visible:` and `active:` apply a utility only while that state holds. Interaction state comes from the previous frame's hit testing, so there is no event wiring to write.")
	if example() {
		ui.button("Save changes", "rounded-full bg-violet-500 px-5 py-2 text-sm font-semibold text-white transition hover:bg-violet-600 active:scale-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-violet-500")
	}
	h2("Group states")
	para("Mark a parent with `group` and style children with `group-hover:` and friends.")
	if example() {
		if ui.button_box("group block w-full max-w-xs rounded-lg bg-white p-6 shadow-lg ring-1 ring-gray-900/5 transition hover:bg-sky-500 hover:ring-sky-500 dark:bg-white/5 dark:ring-white/10") {
			if ui.div("flex items-center gap-3") {
				ui.icon(IC.bolt, "size-6 text-sky-500 group-hover:text-white")
				ui.text("New project", "text-sm font-semibold text-gray-900 group-hover:text-white dark:text-white")
			}
			ui.text("Create a new project from a variety of starting templates.", "mt-2 text-sm text-gray-500 group-hover:text-white dark:text-gray-400")
		}
	}
	h2("First, last, odd and even")
	if example() {
		if ui.div("w-full max-w-sm divide-y divide-gray-200 overflow-hidden rounded-lg ring-1 ring-gray-200 dark:divide-white/10 dark:ring-white/10") {
			for name in ([]string{"Kristen Ramos", "Floyd Miles", "Courtney Henry", "Ted Fox"}) {
				ui.text(name, "px-4 py-3 text-sm text-gray-700 odd:bg-white even:bg-gray-50 dark:text-gray-300 dark:odd:bg-white/5 dark:even:bg-transparent")
			}
		}
	}
	h2("Application state")
	para("Pass `{.Selected}`, `{.Checked}`, `{.Disabled}` or `{.Open}` flags to light up `aria-selected:`, `checked:`, `disabled:` and `open:` variants from your own state.")
	if example() {
		tab := &s.demo.tab
		if ui.div("flex gap-1 rounded-lg bg-gray-100 p-1 dark:bg-white/5") {
			for label, i in ([]string{"Overview", "Activity", "Settings"}) {
				ui.key(label)
				if ui.button(label, "rounded-md px-3 py-1.5 text-sm font-medium text-gray-600 transition hover:text-gray-950 aria-selected:bg-white aria-selected:text-gray-950 aria-selected:shadow-sm dark:text-gray-400 dark:hover:text-white dark:aria-selected:bg-white/10 dark:aria-selected:text-white", i == tab^ ? {.Selected} : {}) {
					tab^ = i
				}
			}
		}
	}
}

page_responsive :: proc() {
	para("Breakpoint variants apply from a minimum window width up: `sm` (640px), `md` (768px), `lg` (1024px), `xl` (1280px) and `2xl` (1536px). Use `max-md:` to target widths below a breakpoint. Breakpoints are tokens, so a theme can move them.")
	if example("p-6", false) {
		if ui.div("mx-auto max-w-md overflow-hidden rounded-xl bg-white shadow-md md:max-w-2xl dark:bg-gray-800") {
			if ui.div("md:flex") {
				if ui.div("md:shrink-0") {
					ui.image(DEMO_IMAGE, "h-48 w-full object-cover md:h-full md:w-48")
				}
				if ui.div("p-8") {
					ui.text("Company retreat", "text-sm font-semibold tracking-wide text-indigo-500 uppercase")
					ui.text("Incredible accommodation for your team", "mt-1 text-lg font-medium text-black dark:text-white")
					ui.text("Looking to take your team away on a retreat to enjoy awesome food and take in some sunshine? We have a list of places to do just that.", "mt-2 text-gray-500 dark:text-gray-400")
				}
			}
		}
	}
	note("Resize the window (or run `vui-ctl resize 700 900`) to watch the card stack vertically below the `md` breakpoint. The showroom itself hides the sidebar below `lg` and the contents rail below `xl`.")
}

page_dark_mode :: proc() {
	para("Prefix utilities with `dark:` to apply them when the app is in dark mode. Toggle it with `ui.set_dark(true)`; the showroom's sun and moon button does exactly that.")
	if example("p-8", true) {
		if ui.div("grid w-full max-w-lg grid-cols-2 gap-4") {
			for dark in ([]bool{false, true}) {
				ui.key(int(dark))
				was := ui.is_dark()
				ui.set_dark(dark)
				if ui.div("rounded-lg bg-white px-6 py-8 shadow-xl ring ring-gray-900/5 dark:bg-gray-800") {
					if ui.div("inline-flex items-center justify-center rounded-md bg-indigo-500 p-2 shadow-lg") {
						ui.icon(IC.cube, "size-6 text-white")
					}
					ui.text("Writes upside-down", "mt-5 text-base font-medium tracking-tight text-gray-900 dark:text-white")
					ui.text("The Zero Gravity Pen can be used to write in any orientation, including upside-down.", "mt-2 text-sm text-gray-500 dark:text-gray-400")
				}
				ui.set_dark(was)
			}
		}
	}
	h2("Semantic tokens")
	para("A token can hold a light and a dark value. The showroom chrome uses tokens such as `bg-canvas`, `text-ink` and `border-rule`, so it needs no `dark:` variants at all.")
	code(`ui.theme_set_color(&ctx.theme, "canvas", ui.WHITE, ui.rgb(0x030712))
ui.theme_set_color(&ctx.theme, "ink", ui.rgb(0x030712), ui.WHITE)

// later, anywhere:
ui.text("Title", "text-ink")          // switches with ui.set_dark()`)
}

page_tokens :: proc() {
	para("The `Theme` struct is the single source of truth: spacing unit, colors, radii, shadows, type scale, weights, tracking, leading, breakpoints, container widths, blur and easing curves. Utilities read from it at parse time; changing a token invalidates the class cache.")
	h2("Defining tokens in code")
	code(`t := &ctx.theme
ui.theme_set_color(t, "brand", ui.rgb(0x7c3aed), ui.rgb(0xa78bfa))
t.radius["card"] = 14
t.spacing = 4                          // p-1 = 4px
ui.theme_changed()

ui.div("rounded-card bg-brand p-6")`)
	h2("Loading a theme file")
	para("Themes can live outside the binary. `ui.theme_load_json` merges a JSON file into the current theme, which makes it possible to re-skin a shipped app.")
	code(`{
  "name": "dusk",
  "colors": {
    "brand":  { "light": "violet-600", "dark": "#a78bfa" },
    "canvas": { "light": "#ffffff",    "dark": "gray-950" }
  },
  "radius":      { "card": 14 },
  "breakpoints": { "md": 760 },
  "fonts":       { "sans": "Inter" }
}`)
	h2("Live token swap")
	para("This example changes one token, `accent`, which the whole showroom chrome uses. Watch the sidebar marker and the logo change.")
	if example() {
		if ui.div("flex flex-wrap justify-center gap-3") {
			for fam in ([]string{"violet", "sky", "emerald", "rose", "amber"}) {
				ui.key(fam)
				if ui.button_box("flex items-center gap-2 rounded-full py-1.5 pr-4 pl-2 text-sm font-medium text-gray-700 ring-1 ring-gray-950/10 hover:bg-gray-50 dark:text-gray-200 dark:ring-white/15 dark:hover:bg-white/5") {
					ui.el(fmt.tprintf("size-5 rounded-full bg-%s-500", fam))
					ui.text(fam)
					if ui.clicked() {
						t := ui.theme()
						ui.theme_set_color(t, "accent", t.colors[fmt.tprintf("%s-600", fam)].light, t.colors[fmt.tprintf("%s-400", fam)].light)
						ui.theme_set_color(t, "accent-soft", ui.with_alpha(t.colors[fmt.tprintf("%s-500", fam)].light, 0.1), ui.with_alpha(t.colors[fmt.tprintf("%s-400", fam)].light, 0.15))
					}
				}
			}
		}
	}
	h2("Default scales")
	ref_table({
		{"spacing", "4px per step: p-1 = 4px, p-4 = 16px"},
		{"text-xs … text-9xl", "12px … 128px with paired line heights"},
		{"rounded-xs … rounded-4xl", "2px … 32px, rounded-full"},
		{"shadow-2xs … shadow-2xl", "layered elevation shadows"},
		{"sm md lg xl 2xl", "640 768 1024 1280 1536px"},
		{"font-thin … font-black", "100 … 900"},
		{"ease-in / ease-out / ease-in-out", "cubic-bezier curves"},
	})
}

page_colors :: proc() {
	if ui.div("mt-10 flex flex-col gap-4") {
		for fam in PALETTE_FAMILIES {
			ui.key(fam)
			if ui.div("flex items-center gap-3") {
				ui.text(fam, "w-16 shrink-0 font-mono text-xs font-medium text-ink-muted")
				if ui.div("grid flex-1 grid-cols-11 gap-1.5") {
					for shade in ([]int{50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950}) {
						ui.key(shade)
						ui.el(fmt.tprintf("aspect-square rounded-md bg-%s-%d inset-ring inset-ring-gray-950/10 dark:inset-ring-white/10", fam, shade))
					}
				}
			}
		}
	}
	h2("Using colors")
	para("Any color utility takes a palette name: `bg-sky-500`, `text-gray-950`, `border-rose-300`, `ring-violet-500`. Add an opacity modifier with a slash: `bg-black/50`, `ring-gray-950/5`.")
	if example() {
		if ui.div("flex gap-3") {
			for a in ([]int{100, 75, 50, 25, 10}) {
				ui.key(a)
				ui.text(fmt.tprintf("%d%%", a), fmt.tprintf("flex size-16 items-center justify-center rounded-lg bg-sky-500/%d font-mono text-xs font-semibold text-sky-950 dark:text-white", a))
			}
		}
	}
}

PALETTE_FAMILIES := [?]string{"red", "orange", "amber", "yellow", "lime", "green", "emerald", "teal", "cyan", "sky", "blue", "indigo", "violet", "purple", "fuchsia", "pink", "rose", "slate", "gray", "zinc", "neutral", "stone"}

page_layout_engine :: proc() {
	para("Layout runs once per frame after the tree is built. Sizes are in logical pixels; the renderer multiplies by the display scale at the very end. The model follows CSS closely enough that Tailwind layouts port without changes.")
	h2("Box model")
	para("Every box is border-box: `w-64 p-4 border-2` is 256px wide in total. Margins never collapse, and `space-x`/`space-y` and `divide-x`/`divide-y` are applied to children by their parent.")
	h2("Formatting contexts")
	ref_table({
		{"block", "children stack vertically and stretch; inline-level children flow in lines"},
		{"flex", "single-pass flexbox: basis, grow, shrink, wrap, gap, auto margins, align-content"},
		{"grid", "fr/px/auto tracks, spans, explicit lines, row and column auto-flow"},
		{"absolute / fixed", "placed against the nearest positioned ancestor or the window"},
		{"overflow-auto", "becomes a scroll container with momentum and a draggable scrollbar"},
	})
	h2("Intrinsic sizes")
	para("Text reports a min-content width (its longest word) and a max-content width (its unbroken line). Flex items default to `min-width: auto`, so a word never gets crushed. Add `min-w-0` when you want an item to shrink below its content.")
	if example("p-6", false) {
		if ui.div("flex w-full max-w-md gap-3 rounded-lg bg-gray-50 p-3 dark:bg-white/5") {
			ui.el("size-10 shrink-0 rounded-full bg-violet-500")
			if ui.div("min-w-0 flex-1") {
				ui.text("A very long title that would overflow without min-w-0 on its flex parent", "truncate text-sm font-medium text-gray-950 dark:text-white")
				ui.text("Truncated with an ellipsis", "text-sm text-gray-500")
			}
		}
	}
}

page_text_rendering :: proc() {
	para("Blurry UI text in native apps usually has one of three causes: glyphs rasterized at one size and scaled to another, a window rendered at 1x and stretched by the compositor on a fractional-scale display, or pen positions rounded to whole pixels so spacing wobbles.")
	h2("What vinland-ui does")
	ref_table({
		{"Physical-pixel windows", "SDL3 high-density windows; at 1.333x the framebuffer is 1.333x larger, never stretched"},
		{"Exact-size rasterization", "glyphs are rasterized for size × scale, cached per size"},
		{"Subpixel positioning", "4 horizontal phases per glyph keep advances precise"},
		{"Pixel-snapped baselines", "every line sits on a whole physical pixel"},
		{"Snapped box edges", "rects and border widths round to device pixels so 1px lines stay solid"},
		{"Font kerning", "kern and GPOS pair adjustments from the font"},
		{"Same rasterizer for icons", "SVG paths go through the glyph rasterizer and atlas"},
	})
	h2("Weights and sizes")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-3") {
			ui.text("The quick brown fox jumps over the lazy dog", "text-xs text-gray-950 dark:text-white")
			ui.text("The quick brown fox jumps over the lazy dog", "text-sm text-gray-950 dark:text-white")
			ui.text("The quick brown fox jumps over the lazy dog", "text-base font-medium text-gray-950 dark:text-white")
			ui.text("The quick brown fox jumps over", "text-2xl font-semibold tracking-tight text-gray-950 dark:text-white")
			ui.text("Sharp at any scale", "text-5xl font-bold tracking-tight text-gray-950 dark:text-white")
		}
	}
}

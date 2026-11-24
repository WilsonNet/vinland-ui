// WebAssembly entry for the website: every example of the current page is a live canvas.
//   PATH=/usr/lib/llvm20/bin:$PATH odin build showroom -target:js_wasm32 -o:size -out:website/public/vui.wasm
// The page provides <meta id="vui-page" content="<slug>"> and canvases with ids vex-0..vex-N
// (example index in page order, the same numbering as the exported screenshots).
#+build js
package showroom

import "core:strconv"
import "core:strings"
import js "core:sys/wasm/js"
import ui "../vui"
import fonts "../vui/fonts"
import icons "../vui/icons"
import web "../vui/web"
import "demos"

MAX_EXAMPLES :: 32

web_page: int = -1

setup :: proc(ctx: ^ui.Context) {
	fonts.register(ctx)
	IC = icons.register(ctx)
	demos.IC = IC
	LOGO = ui.icon_register(ctx, "vinland-logo", {32, 32}, LOGO_PATHS[:])
	GITHUB = ui.icon_register(ctx, "github", {24, 24}, GITHUB_PATHS[:])
	theme_setup(&ctx.theme)
}

// Build proc shared by all canvases: run the page with only this canvas's example live.
build_example :: proc() {
	id := web.current_id()
	k, _ := strconv.parse_int(strings.trim_prefix(id, "vex-"))
	if web_page < 0 {
		return
	}
	s.page = web_page
	wm = {active = true, target = k}
	// The page is laid out offscreen; the target example is a fixed overlay on the canvas.
	if ui.div("absolute top-0 -left-[20000px] w-[1024px]") {
		p := PAGES[web_page]
		if p.render != nil {
			p.render()
		} else {
			ref_page_render()
		}
	}
	wm = {}
}

main :: proc() {
	web.setup_proc = setup
	register_pages()
	s.demo.slider = 40
	s.demo.radio = 1
	buf: [128]u8
	slug := js.get_element_key_string("vui-page", "content", buf[:])
	web_page = page_index(slug)
	if web_page < 0 {
		return
	}
	for k in 0 ..< MAX_EXAMPLES {
		nb: [8]u8
		id := strings.concatenate({"vex-", strconv.write_int(nb[:], i64(k), 10)})
		if web.mount(id, build_example) {
			js.set_element_style(id, "display", "block")
		}
	}
}

@(export)
step :: proc(dt: f64) -> (keep_going: bool) {
	buf: [64]u8
	cls := js.get_element_key_string("vui-root", "className", buf[:])
	web.frame(dt, strings.contains(cls, "dark"))
	return true
}

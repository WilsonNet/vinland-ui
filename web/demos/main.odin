// WebAssembly build of the showcase components for the website.
//   odin build web/demos -target:js_wasm32 -o:size -out:build/site/demos.wasm
package site_demos

import js "core:sys/wasm/js"
import ui "../../vui"
import fonts "../../vui/fonts"
import icons "../../vui/icons"
import web "../../vui/web"
import demos "../../showroom/demos"

setup :: proc(ctx: ^ui.Context) {
	f := &ctx.fonts
	ui.font_register(f, "Inter", fonts.INTER_REGULAR, 400)
	ui.font_register(f, "Inter", fonts.INTER_MEDIUM, 500)
	ui.font_register(f, "Inter", fonts.INTER_SEMIBOLD, 600)
	ui.font_register(f, "Inter", fonts.INTER_BOLD, 700)
	ui.font_register(f, "IBM Plex Mono", fonts.PLEX_MONO_REGULAR, 400)
	ui.font_register(f, "IBM Plex Mono", fonts.PLEX_MONO_MEDIUM, 500)
	demos.IC = icons.register(ctx)
}

// Each demo sits in the same frame the showroom's example() gives it.
frame_centered :: proc(class: string, body: proc()) {
	if ui.div(ui.cx("flex h-full flex-col items-center justify-center", class)) {
		body()
	}
}

buttons :: proc() {frame_centered("p-8", demos.buttons)}
badges :: proc() {frame_centered("p-8", demos.badges)}
form :: proc() {if ui.div("p-8") {demos.form()}}
tabs :: proc() {if ui.div("p-8") {demos.tabs()}}
stacked_list :: proc() {if ui.div("p-6") {demos.stacked_list()}}
pricing :: proc() {frame_centered("p-10", demos.pricing)}
notification :: proc() {frame_centered("p-8", demos.notification)}
counter :: proc() {frame_centered("p-8", demos.counter)}

Demo :: struct {
	id:    string,
	build: proc(),
}

DEMOS := [?]Demo {
	{"vui-buttons", buttons},
	{"vui-badges", badges},
	{"vui-form", form},
	{"vui-tabs", tabs},
	{"vui-stacked-list", stacked_list},
	{"vui-pricing-card", pricing},
	{"vui-notification", notification},
	{"vui-counter", counter},
}

main :: proc() {
	web.setup_proc = setup
	for d in DEMOS {
		if web.mount(d.id, d.build) {
			js.set_element_style(d.id, "display", "block")
		}
	}
}

@(export)
step :: proc(dt: f64) -> (keep_going: bool) {
	buf: [64]u8
	cls := js.get_element_key_string("vui-root", "className", buf[:])
	dark := false
	for i := 0; i + 4 <= len(cls); i += 1 {
		if cls[i:i + 4] == "dark" {
			dark = true
		}
	}
	web.frame(dt, dark)
	return true
}

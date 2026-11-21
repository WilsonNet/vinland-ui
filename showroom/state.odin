// Shared showroom state, used by the native app (main.odin) and the WebAssembly build
// of the examples for the website (web_main.odin).
package showroom

import ui "../vui"
import icons "../vui/icons"

VERSION :: "0.1"

State :: struct {
	page:          int,
	sidebar_open:  bool,
	search_open:   bool,
	search_query:  [dynamic]u8,
	search_sel:    int,
	theme_mode:    int, // 0 light, 1 dark
	scroll_id:     ui.Id,
	pending_anchor: string,
	nav_count:     int,
	demo:          Demo_State,
}

Demo_State :: struct {
	toggle:      bool,
	checked:     [4]bool,
	radio:       int,
	slider:      f32,
	text:        [dynamic]u8,
	counter:     int,
	tab:         int,
	accordion:   int,
	email:       [dynamic]u8,
}

s: State
IC: icons.Icons
LOGO: ui.Icon
GITHUB: ui.Icon

// Design tokens for the showroom chrome. Pages use plain palette utilities so the
// examples stay copy-pasteable; the shell uses semantic tokens so it re-skins as a unit.
theme_setup :: proc(t: ^ui.Theme) {
	gray := proc(t: ^ui.Theme, name: string) -> ui.Color {
		return t.colors[name].light
	}
	ui.theme_set_color(t, "accent", gray(t, "violet-600"), gray(t, "violet-400"))
	ui.theme_set_color(t, "accent-soft", ui.with_alpha(gray(t, "violet-500"), 0.1), ui.with_alpha(gray(t, "violet-400"), 0.15))
	ui.theme_set_color(t, "canvas", ui.WHITE, gray(t, "gray-950"))
	ui.theme_set_color(t, "ink", gray(t, "gray-950"), ui.WHITE)
	ui.theme_set_color(t, "ink-muted", gray(t, "gray-600"), gray(t, "gray-400"))
	ui.theme_set_color(t, "ink-soft", gray(t, "gray-500"), gray(t, "gray-500"))
	ui.theme_set_color(t, "rule", ui.with_alpha(gray(t, "gray-950"), 0.05), ui.with_alpha(ui.WHITE, 0.1))
	ui.theme_set_color(t, "rule-strong", ui.with_alpha(gray(t, "gray-950"), 0.1), ui.with_alpha(ui.WHITE, 0.15))
	ui.theme_set_color(t, "hatch", ui.with_alpha(gray(t, "gray-950"), 0.05), ui.with_alpha(ui.WHITE, 0.08))
	ui.theme_set_color(t, "well", ui.with_alpha(gray(t, "gray-950"), 0.025), ui.with_alpha(ui.WHITE, 0.05))
	ui.theme_set_color(t, "scrollbar", ui.with_alpha(gray(t, "gray-950"), 0.2), ui.with_alpha(ui.WHITE, 0.2))
}


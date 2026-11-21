package showroom

import "core:fmt"
import ui "../vui"
import "demos"

register_interactivity_examples :: proc() {
	EXAMPLES["accent-color"] = ex_accent
	EXAMPLES["caret-color"] = ex_caret
	EXAMPLES["cursor"] = ex_cursor
	EXAMPLES["pointer-events"] = ex_pointer_events
	EXAMPLES["user-select"] = ex_user_select
	EXAMPLES["fill"] = ex_fill
}

check_box :: proc(value: ^bool, label: string, accent: string, loc := #caller_location) {
	if ui.checkbox(value, "group flex items-center gap-3", loc = loc) {
		if ui.div(ui.cx("flex size-5 items-center justify-center rounded border border-gray-300 bg-white transition-colors dark:border-white/20 dark:bg-white/5", fmt.tprintf("group-aria-selected:bg-%s", accent), value^ ? fmt.tprintf("border-%s bg-%s dark:border-%s dark:bg-%s", accent, accent, accent, accent) : "")) {
			if value^ {
				ui.icon(IC.check, "size-4 text-white")
			}
		}
		ui.text(label, "text-sm text-gray-700 dark:text-gray-300")
	}
}

ex_accent :: proc() {
	h3("Controls styled by state")
	para("Form controls are plain elements with behaviour. `ui.checkbox` toggles a bool and lights up the `checked:` variant; the look is entirely yours.")
	if example() {
		if ui.div("flex flex-col gap-3") {
			check_box(&s.demo.checked[0], "Default", "gray-900")
			check_box(&s.demo.checked[1], "Accent violet", "violet-500")
			check_box(&s.demo.checked[2], "Accent pink", "pink-500")
		}
	}
	h3("Radio groups")
	if example() {
		if ui.div("flex flex-col gap-3") {
			for label, i in ([]string{"Small", "Medium", "Large"}) {
				ui.key(label)
				if ui.radio(&s.demo.radio, i, "group flex items-center gap-3") {
					ui.el("size-4 rounded-full border border-gray-300 bg-white checked:border-[5px] checked:border-violet-500 dark:border-white/20 dark:bg-white/5", s.demo.radio == i ? {.Checked} : {})
					ui.text(label, "text-sm text-gray-700 dark:text-gray-300")
				}
			}
		}
	}
	h3("Sliders")
	if example() {
		if ui.div("flex w-72 flex-col gap-3") {
			ui.slider(&s.demo.slider, 0, 100, "relative h-1.5 w-full rounded-full bg-gray-200 dark:bg-white/10", "rounded-full bg-violet-500", "size-4 rounded-full bg-white shadow ring-1 ring-gray-950/10 focus-visible:ring-2 focus-visible:ring-violet-500", 1)
			ui.text(fmt.tprintf("Volume %.0f", s.demo.slider), "text-sm text-gray-600 dark:text-gray-400")
		}
	}
}

ex_caret :: proc() {
	h3("Basic example")
	para("Use `caret-<color>` to color the text cursor and `selection:bg-*` for the selection highlight. Click into the field and type.")
	if example() {
		ui.text_input(&s.demo.text, "w-80 rounded-lg bg-white px-3 py-2 text-sm text-gray-950 ring-1 ring-gray-300 caret-pink-500 selection:bg-pink-500/25 focus:ring-2 focus:ring-pink-500 dark:bg-gray-900 dark:text-white dark:ring-white/15", "Type something…")
	}
}

ex_cursor :: proc() {
	h3("Basic example")
	para("Hover each button to see the system cursor change.")
	if example() {
		if ui.div("flex flex-wrap justify-center gap-3") {
			for c in ([]string{"cursor-pointer", "cursor-text", "cursor-move", "cursor-wait", "cursor-crosshair", "cursor-not-allowed", "cursor-ew-resize"}) {
				ui.key(c)
				ui.text(c, ui.cx("rounded-md bg-gray-100 px-3 py-2 font-mono text-xs text-gray-700 dark:bg-white/10 dark:text-gray-200", c))
			}
		}
	}
}

ex_pointer_events :: proc() {
	h3("Ignoring pointer events")
	para("Use `pointer-events-none` to let clicks fall through to whatever is below. The icon here does not block the field.")
	if example() {
		if ui.div("relative w-72") {
			ui.text_input(&s.demo.email, "w-full rounded-lg bg-white py-2 pr-3 pl-9 text-sm text-gray-950 ring-1 ring-gray-300 focus:ring-2 focus:ring-violet-500 dark:bg-gray-900 dark:text-white dark:ring-white/15", "Search")
			ui.icon(IC.magnifying_glass, "pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-gray-400")
		}
	}
}

ex_user_select :: proc() {
	h3("Basic example")
	para("`select-none` marks text as not selectable; the cursor stays an arrow over it.")
	if example() {
		ui.text("The quick brown fox jumps over the lazy dog.", "select-none text-sm text-gray-700 dark:text-gray-300")
	}
}

ex_fill :: proc() {
	h3("Coloring icons")
	para("Icons take `text-*` (current color) or an explicit `fill-*`.")
	if example() {
		if ui.div("flex gap-6") {
			ui.icon(IC.heart, "size-10 fill-pink-500")
			ui.icon(IC.star, "size-10 fill-amber-400")
			ui.icon(IC.bolt, "size-10 fill-violet-500")
			ui.icon(IC.fire, "size-10 fill-orange-500")
		}
	}
}

// ---------------------------------------------------------------------------
// Showcase (storybook)
// ---------------------------------------------------------------------------

page_showcase :: proc() {
	h2("Buttons")
	if example() {
		demos.buttons()
	}
	h2("Badges")
	if example() {
		demos.badges()
	}
	h2("Form")
	if example("p-8", false) {
		demos.form()
	}
	h2("Tabs")
	if example("p-8", false) {
		demos.tabs()
	}
	h2("Stacked list")
	if example("p-6", false) {
		demos.stacked_list()
	}
	h2("Pricing card")
	if example("p-10") {
		demos.pricing()
	}
	h2("Notification")
	if example("p-8") {
		demos.notification()
	}
	h2("Counter")
	para("State lives in your own variables; the UI rebuilds from it every frame.")
	if example() {
		demos.counter()
	}
}


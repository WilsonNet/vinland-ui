package showroom

import "core:fmt"
import ui "../vui"

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
		if ui.div("flex flex-wrap items-center gap-3") {
			ui.button("Primary", "rounded-md bg-violet-600 px-3.5 py-2 text-sm font-semibold text-white shadow-xs transition-colors hover:bg-violet-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-violet-600")
			ui.button("Secondary", "rounded-md bg-white px-3.5 py-2 text-sm font-semibold text-gray-900 shadow-xs inset-ring inset-ring-gray-300 transition-colors hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:inset-ring-white/5 dark:hover:bg-white/20")
			ui.button("Soft", "rounded-md bg-violet-50 px-3.5 py-2 text-sm font-semibold text-violet-600 transition-colors hover:bg-violet-100 dark:bg-violet-500/20 dark:text-violet-300 dark:hover:bg-violet-500/30")
			ui.button("Rounded", "rounded-full bg-gray-950 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-gray-800 dark:bg-white dark:text-gray-950 dark:hover:bg-gray-200")
			if ui.button_box("inline-flex items-center gap-1.5 rounded-md bg-violet-600 px-3 py-2 text-sm font-semibold text-white transition-colors hover:bg-violet-500") {
				ui.icon(IC.check_circle, "-ml-0.5 size-5")
				ui.text("With icon")
			}
			ui.button("Disabled", "rounded-md bg-violet-600 px-3.5 py-2 text-sm font-semibold text-white disabled:opacity-50 disabled:cursor-not-allowed", {.Disabled})
		}
	}
	h2("Badges")
	if example() {
		if ui.div("flex flex-wrap gap-2") {
			for b in ([][2]string{{"Gray", "gray"}, {"Red", "red"}, {"Yellow", "yellow"}, {"Green", "green"}, {"Blue", "blue"}, {"Indigo", "indigo"}, {"Purple", "purple"}, {"Pink", "pink"}}) {
				ui.key(b[0])
				ui.text(b[0], fmt.tprintf("rounded-md bg-%s-50 px-2 py-1 text-xs font-medium text-%s-700 inset-ring inset-ring-%s-600/20 dark:bg-%s-400/10 dark:text-%s-400 dark:inset-ring-%s-400/20", b[1], b[1], b[1], b[1], b[1], b[1]))
			}
		}
	}
	h2("Form")
	if example("p-8", false) {
		if ui.div("w-full max-w-md") {
			ui.text("Profile", "text-base font-semibold text-gray-900 dark:text-white")
			ui.text("This information will be displayed publicly.", "mt-1 text-sm/6 text-gray-600 dark:text-gray-400")
			if ui.div("mt-6 flex flex-col gap-2") {
				ui.text("Email address", "text-sm/6 font-medium text-gray-900 dark:text-white")
				ui.text_input(&s.demo.email, "rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-violet-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10", "you@example.com")
			}
			if ui.div("mt-6 flex items-center justify-between") {
				if ui.div("flex flex-col") {
					ui.text("Available to hire", "text-sm/6 font-medium text-gray-900 dark:text-white")
					ui.text("Nulla amet tempus sit accumsan.", "text-sm text-gray-500 dark:text-gray-400")
				}
				toggle(&s.demo.toggle)
			}
			if ui.div("mt-8 flex justify-end gap-3") {
				ui.button("Cancel", "rounded-md px-3 py-2 text-sm font-semibold text-gray-900 hover:bg-gray-50 dark:text-white dark:hover:bg-white/5")
				ui.button("Save", "rounded-md bg-violet-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-violet-500")
			}
		}
	}
	h2("Tabs")
	if example("p-8", false) {
		if ui.div("w-full") {
			if ui.div("flex gap-8 border-b border-gray-200 dark:border-white/10") {
				for label, i in ([]string{"My Account", "Company", "Team Members", "Billing"}) {
					ui.key(label)
					if ui.button(label, "-mb-px border-b-2 border-transparent px-1 py-3 text-sm font-medium text-gray-500 transition-colors hover:border-gray-300 hover:text-gray-700 aria-selected:border-violet-500 aria-selected:text-violet-600 dark:text-gray-400 dark:hover:text-gray-200 dark:aria-selected:text-violet-400", s.demo.accordion == i ? {.Selected} : {}) {
						s.demo.accordion = i
					}
				}
			}
			ui.text(fmt.tprintf("Content for tab %d.", s.demo.accordion + 1), "pt-4 text-sm text-gray-600 dark:text-gray-400")
		}
	}
	h2("Stacked list")
	if example("p-6", false) {
		if ui.div("w-full divide-y divide-gray-100 dark:divide-white/5") {
			people := [?][3]string{{"Leslie Alexander", "Co-Founder / CEO", "violet"}, {"Michael Foster", "Co-Founder / CTO", "sky"}, {"Dries Vincent", "Business Relations", "emerald"}, {"Lindsay Walton", "Front-end Developer", "pink"}}
			for p, i in people {
				ui.key(i)
				if ui.div("flex items-center justify-between gap-x-6 py-4") {
					if ui.div("flex min-w-0 gap-x-4") {
						ui.text(p[0][:1], fmt.tprintf("flex size-11 shrink-0 items-center justify-center rounded-full bg-%s-100 text-sm font-semibold text-%s-700 dark:bg-%s-500/20 dark:text-%s-300", p[2], p[2], p[2], p[2]))
						if ui.div("min-w-0 flex-auto") {
							ui.text(p[0], "text-sm/6 font-semibold text-gray-900 dark:text-white")
							ui.text(p[1], "mt-0.5 truncate text-xs/5 text-gray-500 dark:text-gray-400")
						}
					}
					ui.button("View", "rounded-full bg-white px-2.5 py-1 text-xs font-semibold text-gray-900 shadow-xs inset-ring inset-ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:inset-ring-white/5 dark:hover:bg-white/20")
				}
			}
		}
	}
	h2("Pricing card")
	if example("p-10") {
		if ui.div("w-full max-w-xs rounded-3xl bg-gray-950 p-8 shadow-2xl ring-1 ring-gray-900/10 dark:bg-white/5 dark:ring-white/10") {
			ui.text("Enterprise", "text-base/7 font-semibold text-violet-400")
			if ui.p("mt-4 flex items-baseline") {
				ui.span("$99", "text-5xl font-semibold tracking-tight text-white")
				ui.span(" /month", "text-base text-gray-400")
			}
			ui.text("Dedicated support and infrastructure for your company.", "mt-6 text-base/7 text-gray-300")
			if ui.div("mt-8 flex flex-col gap-3") {
				for f in ([]string{"Unlimited products", "Advanced analytics", "Custom integrations"}) {
					ui.key(f)
					if ui.div("flex gap-3") {
						ui.icon(IC.check, "size-5 shrink-0 text-violet-400")
						ui.text(f, "text-sm/6 text-gray-300")
					}
				}
			}
			ui.button("Get started today", "mt-8 block rounded-md bg-violet-500 px-3.5 py-2.5 text-center text-sm font-semibold text-white shadow-xs transition-colors hover:bg-violet-400")
		}
	}
	h2("Notification")
	if example("p-8") {
		if ui.div("flex w-full max-w-sm gap-3 rounded-lg bg-white p-4 shadow-lg ring-1 ring-black/5 dark:bg-gray-800 dark:ring-white/10") {
			ui.icon(IC.check_circle, "size-6 shrink-0 text-green-400")
			if ui.div("flex-1") {
				ui.text("Successfully saved!", "text-sm font-medium text-gray-900 dark:text-white")
				ui.text("Anyone with a link can now view this file.", "mt-1 text-sm text-gray-500 dark:text-gray-400")
			}
			ui.icon(IC.x_mark, "size-5 shrink-0 text-gray-400")
		}
	}
	h2("Counter")
	para("State lives in your own variables; the UI rebuilds from it every frame.")
	if example() {
		if ui.div("flex items-center gap-4") {
			if ui.button_box("flex size-9 items-center justify-center rounded-full bg-gray-100 text-gray-700 transition-colors hover:bg-gray-200 active:scale-95 dark:bg-white/10 dark:text-white dark:hover:bg-white/15") {
				ui.icon(IC.minus, "size-4")
				if ui.clicked() {
					s.demo.counter -= 1
				}
			}
			ui.text(fmt.tprintf("%d", s.demo.counter), "w-12 text-center text-3xl font-semibold tabular-nums text-gray-950 dark:text-white")
			if ui.button_box("flex size-9 items-center justify-center rounded-full bg-violet-600 text-white transition-colors hover:bg-violet-500 active:scale-95") {
				ui.icon(IC.plus, "size-4")
				if ui.clicked() {
					s.demo.counter += 1
				}
			}
		}
	}
}

toggle :: proc(on: ^bool, loc := #caller_location) {
	if ui.checkbox(on, "relative flex h-6 w-11 shrink-0 rounded-full bg-gray-200 p-0.5 inset-ring inset-ring-gray-900/5 transition-colors duration-200 checked:bg-violet-600 dark:bg-white/10 dark:inset-ring-white/10", loc = loc) {
		ui.el(on^ ? "size-5 translate-x-5 rounded-full bg-white shadow-xs ring-1 ring-gray-900/5 transition-transform duration-200 ease-in-out" : "size-5 rounded-full bg-white shadow-xs ring-1 ring-gray-900/5 transition-transform duration-200 ease-in-out")
	}
}

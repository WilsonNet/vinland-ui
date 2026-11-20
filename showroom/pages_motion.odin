package showroom

import ui "../vui"

register_motion_examples :: proc() {
	EXAMPLES["transition-property"] = ex_transition
	EXAMPLES["transition-duration"] = ex_duration
	EXAMPLES["transition-timing-function"] = ex_easing
	EXAMPLES["transition-delay"] = ex_delay
	EXAMPLES["animation"] = ex_animation
	EXAMPLES["rotate"] = ex_rotate
	EXAMPLES["scale"] = ex_scale
	EXAMPLES["skew"] = ex_skew
	EXAMPLES["translate"] = ex_translate
	EXAMPLES["transform"] = ex_transform
	EXAMPLES["transform-origin"] = ex_origin
}

ex_transition :: proc() {
	h3("Basic example")
	para("Use `transition` to animate color, opacity, shadow and transform changes. Hover the button: background, lift and scale all ease together.")
	if example("p-12") {
		ui.button("Save changes", "rounded-full bg-blue-500 px-5 py-2 text-sm font-semibold text-white shadow-md transition delay-150 duration-300 ease-in-out hover:-translate-y-1 hover:scale-110 hover:bg-indigo-500 hover:shadow-xl")
	}
	h3("Choosing what animates")
	para("`transition-colors`, `transition-opacity`, `transition-shadow` and `transition-transform` limit which properties animate.")
	if example("p-12") {
		if ui.div("flex gap-6") {
			ui.button("colors", "rounded-lg bg-gray-100 px-4 py-2 font-mono text-xs font-medium text-gray-700 transition-colors duration-500 hover:bg-violet-500 hover:text-white hover:scale-110 dark:bg-white/10 dark:text-gray-200")
			ui.button("transform", "rounded-lg bg-gray-100 px-4 py-2 font-mono text-xs font-medium text-gray-700 transition-transform duration-500 hover:bg-violet-500 hover:text-white hover:scale-110 dark:bg-white/10 dark:text-gray-200")
			ui.button("all", "rounded-lg bg-gray-100 px-4 py-2 font-mono text-xs font-medium text-gray-700 transition-all duration-500 hover:bg-violet-500 hover:text-white hover:scale-110 dark:bg-white/10 dark:text-gray-200")
		}
	}
}

ex_duration :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-6") {
			for c in ([]string{"duration-150", "duration-300", "duration-700", "duration-1000"}) {
				ui.key(c)
				ui.button(c, ui.cx("rounded-lg bg-sky-500 px-4 py-2 font-mono text-xs font-medium text-white transition hover:-translate-y-2 hover:bg-indigo-500", c))
			}
		}
	}
}

ex_easing :: proc() {
	h3("Basic example")
	para("Hover each row: the dot travels with `ease-linear`, `ease-in`, `ease-out` and `ease-in-out`.")
	if example("p-8", false) {
		if ui.div("group flex w-full flex-col gap-4 rounded-lg p-2") {
			for c in ([]string{"ease-linear", "ease-in", "ease-out", "ease-in-out"}) {
				ui.key(c)
				if ui.div("flex items-center gap-4") {
					ui.text(c, "w-28 shrink-0 font-mono text-xs text-gray-500 dark:text-gray-400")
					if ui.div("relative h-8 flex-1 rounded-full bg-gray-100 dark:bg-white/5") {
						ui.el(ui.cx("absolute top-1 left-1 size-6 rounded-full bg-violet-500 shadow transition-transform duration-1000 group-hover:translate-x-64", c))
					}
				}
			}
		}
	}
}

ex_delay :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-6") {
			for c in ([]string{"delay-150", "delay-300", "delay-700"}) {
				ui.key(c)
				ui.button(c, ui.cx("rounded-lg bg-sky-500 px-4 py-2 font-mono text-xs font-medium text-white transition duration-300 hover:scale-110 hover:bg-indigo-500", c))
			}
		}
	}
}

ex_animation :: proc() {
	h3("Spin")
	para("Use `animate-spin` for loading indicators.")
	if example() {
		if ui.div("inline-flex items-center gap-3 rounded-md bg-indigo-500 px-4 py-2 text-sm font-semibold text-white") {
			ui.icon(IC.arrow_path, "size-5 animate-spin")
			ui.text("Processing…")
		}
	}
	h3("Ping")
	para("Use `animate-ping` to make an element scale and fade like a radar ping.")
	if example() {
		if ui.div("relative flex size-4") {
			ui.el("absolute inset-0 animate-ping rounded-full bg-sky-400 opacity-75")
			ui.el("relative size-4 rounded-full bg-sky-500")
		}
	}
	h3("Pulse")
	para("Use `animate-pulse` for skeleton loaders.")
	if example("p-8", false) {
		if ui.div("w-full max-w-sm rounded-md border border-blue-300 p-4 dark:border-blue-500/40") {
			if ui.div("flex animate-pulse gap-4") {
				ui.el("size-10 rounded-full bg-gray-200 dark:bg-white/10")
				if ui.div("flex-1 space-y-4 py-1") {
					ui.el("h-2 rounded bg-gray-200 dark:bg-white/10")
					if ui.div("grid grid-cols-3 gap-4") {
						ui.el("col-span-2 h-2 rounded bg-gray-200 dark:bg-white/10")
						ui.el("h-2 rounded bg-gray-200 dark:bg-white/10")
					}
					ui.el("h-2 rounded bg-gray-200 dark:bg-white/10")
				}
			}
		}
	}
	h3("Bounce")
	if example("p-12") {
		if ui.div("flex size-10 animate-bounce items-center justify-center rounded-full bg-white shadow-lg ring-1 ring-gray-900/5 dark:bg-gray-800 dark:ring-white/10") {
			ui.icon(IC.arrow_right, "size-5 rotate-90 text-violet-500")
		}
	}
}

transform_tile :: proc(label, class: string, loc := #caller_location) {
	if ui.div("flex flex-col items-center gap-4", loc = loc) {
		ui.text(label, "font-mono text-xs text-gray-500 dark:text-gray-400")
		if ui.div("size-24 rounded-lg bg-stripes stripes-violet-500/25") {
			ui.image(DEMO_IMAGE, ui.cx("size-24 rounded-lg object-cover shadow-xl", class))
		}
	}
}

ex_rotate :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-10") {
			for c in ([]string{"rotate-45", "rotate-90", "rotate-210", "-rotate-12"}) {
				ui.key(c)
				transform_tile(c, c)
			}
		}
	}
}

ex_scale :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-10") {
			for c in ([]string{"scale-75", "scale-100", "scale-125"}) {
				ui.key(c)
				transform_tile(c, c)
			}
		}
	}
	h3("Applying on hover")
	if example("p-12") {
		ui.button("Hover me", "rounded-lg bg-violet-500 px-5 py-2 text-sm font-semibold text-white shadow-lg transition hover:scale-110 active:scale-95")
	}
}

ex_skew :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-10") {
			for c in ([]string{"skew-3", "skew-6", "skew-12", "-skew-x-12"}) {
				ui.key(c)
				transform_tile(c, c)
			}
		}
	}
}

ex_translate :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-10") {
			for c in ([]string{"-translate-2", "translate-2", "translate-x-4", "-translate-y-4"}) {
				ui.key(c)
				transform_tile(c, c)
			}
		}
	}
	h3("Using percentages")
	para("Percent translations are relative to the element's own size: `-translate-x-1/2`.")
}

ex_transform :: proc() {
	h3("Combining transforms")
	para("Translate, rotate, scale and skew compose in one matrix around `transform-origin`, and hit testing follows the transformed shape.")
	if example("p-12") {
		ui.button("Click me", "rounded-lg bg-indigo-500 px-5 py-2 text-sm font-semibold text-white shadow-lg rotate-6 scale-110 transition hover:rotate-0 hover:scale-100")
	}
}

ex_origin :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-12") {
			for c in ([]string{"origin-center", "origin-top-left", "origin-bottom", "origin-right"}) {
				ui.key(c)
				transform_tile(c, ui.cx("rotate-45", c))
			}
		}
	}
}

package showroom

import ui "../vui"

register_spacing_examples :: proc() {
	EXAMPLES["padding"] = ex_padding
	EXAMPLES["margin"] = ex_margin
	EXAMPLES["width"] = ex_width
	EXAMPLES["min-width"] = ex_min_width
	EXAMPLES["max-width"] = ex_max_width
	EXAMPLES["height"] = ex_height
	EXAMPLES["min-height"] = ex_min_height
	EXAMPLES["max-height"] = ex_max_height
}

// a padded box whose padding area is hatched, like the Tailwind docs
pad_box :: proc(label: string, class: string, loc := #caller_location) {
	if ui.div(ui.cx("rounded-lg bg-violet-500 bg-stripes stripes-white/25", class), loc = loc) {
		ui.text(label, "flex items-center justify-center rounded-lg bg-violet-500 px-3 py-3 font-mono text-sm font-bold text-white")
	}
}

ex_padding :: proc() {
	h3("Basic example")
	para("Use `p-<number>` utilities like `p-4` and `p-8` to control the padding on all sides of an element.")
	if example() {
		pad_box("p-8", "p-8")
	}
	h3("Adding padding to one side")
	para("Use `pt-<number>`, `pr-<number>`, `pb-<number>` and `pl-<number>` to control the padding on one side.")
	if example() {
		if ui.div("flex items-start gap-8") {
			pad_box("pt-6", "pt-6")
			pad_box("pr-4", "pr-4")
			pad_box("pb-8", "pb-8")
			pad_box("pl-2", "pl-2")
		}
	}
	h3("Adding horizontal padding")
	if example() {
		pad_box("px-8", "px-8")
	}
	h3("Adding vertical padding")
	if example() {
		pad_box("py-8", "py-8")
	}
}

margin_box :: proc(label: string, class: string, loc := #caller_location) {
	if ui.div("rounded-lg bg-stripes stripes-violet-500/30 bg-violet-500/5", loc = loc) {
		ui.text(label, ui.cx("flex items-center justify-center rounded-lg bg-violet-500 px-4 py-3 font-mono text-sm font-bold text-white", class))
	}
}

ex_margin :: proc() {
	h3("Basic example")
	para("Use `m-<number>` utilities like `m-4` and `m-8` to control the margin on all sides of an element.")
	if example() {
		margin_box("m-8", "m-8")
	}
	h3("Adding margin to one side")
	if example() {
		if ui.div("flex items-start gap-8") {
			margin_box("mt-6", "mt-6")
			margin_box("mr-4", "mr-4")
			margin_box("mb-8", "mb-8")
			margin_box("ml-2", "ml-2")
		}
	}
	h3("Using negative values")
	para("Prefix a margin utility with a dash to pull an element outward: `-mt-8`.")
	if example() {
		if ui.div("flex w-36 flex-col items-center") {
			ui.el("h-16 w-full rounded-lg bg-sky-400/40")
			ui.text("-mt-8", "relative -mt-8 rounded-lg bg-sky-500 px-4 py-3 font-mono text-sm font-bold text-white shadow-lg")
		}
	}
	h3("Adding space between children")
	para("Use `space-x-<number>` and `space-y-<number>` to space children without a gap.")
	if example() {
		if ui.div("flex space-x-4") {
			tile("01")
			tile("02")
			tile("03")
		}
	}
}

ex_width :: proc() {
	h3("Basic example")
	para("Use `w-<number>` to set a fixed width from the spacing scale.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-3") {
			for w in ([]string{"w-96", "w-80", "w-64", "w-48", "w-40", "w-32", "w-24"}) {
				ui.key(w)
				tile(w, w)
			}
		}
	}
	h3("Using a percentage")
	para("Use fractions like `w-1/2` and `w-2/5`, or `w-full`.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-3") {
			if ui.div("flex gap-3") {
				tile("w-1/2", "w-1/2")
				tile("w-1/2", "w-1/2")
			}
			if ui.div("flex gap-3") {
				tile("w-2/5", "w-2/5")
				tile("w-3/5", "w-3/5")
			}
			tile("w-full", "w-full")
		}
	}
	h3("Setting both width and height")
	para("Use `size-<number>` to set width and height together.")
	if example() {
		if ui.div("flex items-end gap-4") {
			for c in ([]string{"size-16", "size-20", "size-24", "size-32"}) {
				ui.key(c)
				tile(c, c)
			}
		}
	}
}

ex_min_width :: proc() {
	h3("Basic example")
	para("Use `min-w-<number>` to keep an element from shrinking below a size.")
	if example("p-8", false) {
		if ui.div("flex w-full gap-3") {
			tile("min-w-48", "min-w-48 flex-1")
			tile("flex-1", "w-full flex-1")
		}
	}
}

ex_max_width :: proc() {
	h3("Basic example")
	para("Use `max-w-<size>` (`max-w-xs` … `max-w-7xl`, `max-w-prose`) to cap a width.")
	if example("p-8", false) {
		if ui.div("mx-auto w-full max-w-sm overflow-hidden rounded-xl bg-white shadow-lg ring-1 ring-gray-950/5 dark:bg-gray-800") {
			ui.image(DEMO_IMAGE, "h-40 w-full object-cover")
			if ui.div("p-5") {
				ui.text("max-w-sm card", "font-semibold text-gray-950 dark:text-white")
				ui.text("Centered with mx-auto, never wider than 24rem.", "mt-1 text-sm text-gray-600 dark:text-gray-300")
			}
		}
	}
}

ex_height :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex items-end gap-4") {
			for h in ([]string{"h-24", "h-32", "h-40", "h-48", "h-56"}) {
				ui.key(h)
				tile(h, ui.cx("w-14", h))
			}
		}
	}
	h3("Full height")
	para("`h-full` resolves against a parent with a definite height.")
	if example() {
		if ui.div("h-40 w-48 rounded-lg bg-stripes stripes-violet-500/30 p-4") {
			tile("h-full", "h-full")
		}
	}
}

ex_min_height :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex items-start gap-4") {
			tile("min-h-24", "min-h-24 w-24")
			tile("min-h-40", "min-h-40 w-24")
		}
	}
}

ex_max_height :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex h-56 items-start gap-4") {
			tile("max-h-24", "h-full max-h-24 w-24")
			tile("max-h-40", "h-full max-h-40 w-24")
			tile("max-h-full", "h-full max-h-full w-24")
		}
	}
}

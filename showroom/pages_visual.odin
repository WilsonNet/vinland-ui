package showroom

import "core:fmt"
import ui "../vui"

register_visual_examples :: proc() {
	EXAMPLES["background-color"] = ex_bg_color
	EXAMPLES["background-image"] = ex_bg_image
	EXAMPLES["background-size"] = ex_bg_size
	EXAMPLES["border-radius"] = ex_radius
	EXAMPLES["border-width"] = ex_border_width
	EXAMPLES["border-color"] = ex_border_color
	EXAMPLES["border-style"] = ex_border_style
	EXAMPLES["outline-width"] = ex_outline
	EXAMPLES["outline-color"] = ex_outline
	EXAMPLES["outline-style"] = ex_outline
	EXAMPLES["outline-offset"] = ex_outline
	EXAMPLES["box-shadow"] = ex_box_shadow
	EXAMPLES["text-shadow"] = ex_text_shadow
	EXAMPLES["opacity"] = ex_opacity
	EXAMPLES["filter"] = ex_filters
	EXAMPLES["filter-brightness"] = ex_filters
	EXAMPLES["filter-contrast"] = ex_filters
	EXAMPLES["filter-grayscale"] = ex_filters
	EXAMPLES["filter-hue-rotate"] = ex_filters
	EXAMPLES["filter-invert"] = ex_filters
	EXAMPLES["filter-saturate"] = ex_filters
	EXAMPLES["filter-sepia"] = ex_filters
	EXAMPLES["filter-drop-shadow"] = ex_drop_shadow
}

ex_bg_color :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex gap-3") {
			ui.button("Subscribe", "rounded-full bg-sky-500 px-5 py-2 text-sm font-semibold text-white shadow-sm")
			ui.button("Subscribe", "rounded-full bg-pink-500 px-5 py-2 text-sm font-semibold text-white shadow-sm")
			ui.button("Subscribe", "rounded-full bg-indigo-500 px-5 py-2 text-sm font-semibold text-white shadow-sm")
		}
	}
	h3("Changing the opacity")
	if example() {
		if ui.div("flex gap-3") {
			for a in ([]string{"bg-sky-500/100", "bg-sky-500/75", "bg-sky-500/50"}) {
				ui.key(a)
				ui.button("Button", ui.cx("rounded-full px-5 py-2 text-sm font-semibold text-white shadow-sm", a))
			}
		}
	}
	h3("Applying on hover")
	if example() {
		ui.button("Save changes", "rounded-full bg-indigo-500 px-5 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-fuchsia-500")
	}
}

ex_bg_image :: proc() {
	h3("Adding a linear gradient")
	para("Use `bg-linear-to-r` (or an angle like `bg-linear-45`) with `from-*`, `via-*` and `to-*` color stops.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-4") {
			ui.el("h-14 rounded-lg bg-linear-to-r from-cyan-500 to-blue-500")
			ui.el("h-14 rounded-lg bg-linear-to-t from-sky-500 to-indigo-500")
			ui.el("h-14 rounded-lg bg-linear-to-bl from-violet-500 to-fuchsia-500")
			ui.el("h-14 rounded-lg bg-linear-65 from-purple-500 to-pink-500")
		}
	}
	h3("Adding a radial gradient")
	if example() {
		if ui.div("flex gap-6") {
			ui.el("size-24 rounded-full bg-radial from-pink-400 from-40% to-fuchsia-700")
			ui.el("size-24 rounded-full bg-radial from-violet-300 via-violet-500 to-indigo-800")
			ui.el("size-24 rounded-full bg-radial from-sky-200 to-sky-700")
		}
	}
	h3("Adding a conic gradient")
	if example() {
		if ui.div("flex gap-6") {
			ui.el("size-24 rounded-full bg-conic from-blue-600 to-sky-400 to-50%")
			ui.el("size-24 rounded-full bg-conic-180 from-indigo-600 via-indigo-50 to-indigo-600")
		}
	}
	h3("Setting color stop positions")
	if example("p-8", false) {
		ui.el("h-14 rounded-lg bg-linear-to-r from-indigo-500 from-10% via-sky-500 via-30% to-emerald-500 to-90%")
	}
}

ex_bg_size :: proc() {
	h3("Patterns")
	para("`bg-stripes` draws a diagonal hatch in the `stripes-*` color; `bg-stripes-<n>` sets the period. The showroom's gutters use it.")
	if example() {
		if ui.div("flex gap-4") {
			ui.el("size-28 rounded-lg bg-stripes stripes-violet-500/40")
			ui.el("size-28 rounded-lg bg-sky-50 bg-stripes-6 stripes-sky-500/40 dark:bg-sky-500/10")
			ui.el("size-28 rounded-lg bg-gray-950 bg-stripes-16 stripes-white/15")
		}
	}
}

ex_radius :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("grid grid-cols-3 gap-6") {
			for c in ([]string{"rounded-sm", "rounded-md", "rounded-lg", "rounded-xl", "rounded-2xl", "rounded-full"}) {
				ui.key(c)
				if ui.div("flex flex-col items-center gap-2") {
					ui.text(c, "font-mono text-xs text-gray-500 dark:text-gray-400")
					ui.el(ui.cx("size-20 bg-blue-500", c))
				}
			}
		}
	}
	h3("Rounding sides and corners")
	if example() {
		if ui.div("flex gap-6") {
			for c in ([]string{"rounded-t-2xl", "rounded-r-2xl", "rounded-b-2xl", "rounded-l-2xl", "rounded-tl-2xl", "rounded-br-2xl"}) {
				ui.key(c)
				ui.el(ui.cx("size-16 bg-blue-500", c))
			}
		}
	}
}

ex_border_width :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex gap-6") {
			for c in ([]string{"border", "border-2", "border-4", "border-8"}) {
				ui.key(c)
				ui.text(c, ui.cx("flex size-20 items-center justify-center rounded-lg border-indigo-500 font-mono text-xs text-gray-600 dark:text-gray-300", c))
			}
		}
	}
	h3("Individual sides")
	if example() {
		if ui.div("flex gap-6") {
			for c in ([]string{"border-t-4", "border-r-4", "border-b-4", "border-l-4"}) {
				ui.key(c)
				ui.el(ui.cx("size-20 rounded-lg border-indigo-500 bg-indigo-500/10", c))
			}
		}
	}
	h3("Between children")
	para("Use `divide-x` and `divide-y` on the parent.")
	if example() {
		if ui.div("grid w-full max-w-sm grid-cols-3 divide-x divide-gray-300 rounded-lg ring-1 ring-gray-300 dark:divide-white/15 dark:ring-white/15") {
			ui.text("01", "py-4 text-center font-mono text-sm text-gray-700 dark:text-gray-300")
			ui.text("02", "py-4 text-center font-mono text-sm text-gray-700 dark:text-gray-300")
			ui.text("03", "py-4 text-center font-mono text-sm text-gray-700 dark:text-gray-300")
		}
	}
}

ex_border_color :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex gap-6") {
			ui.el("size-20 rounded-lg border-4 border-indigo-500")
			ui.el("size-20 rounded-lg border-4 border-purple-500")
			ui.el("size-20 rounded-lg border-4 border-sky-500")
		}
	}
	h3("Individual sides")
	if example() {
		ui.el("size-24 border-8 border-t-indigo-500 border-r-indigo-300 border-b-indigo-500 border-l-indigo-300")
	}
	h3("Applying on focus")
	if example() {
		ui.text_input(&s.demo.email, "w-72 rounded-lg border-2 border-gray-300 bg-white px-3 py-2 text-sm text-gray-950 transition-colors focus:border-violet-500 dark:border-white/15 dark:bg-gray-900 dark:text-white", "you@example.com")
	}
}

ex_border_style :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("grid grid-cols-3 gap-6") {
			for c in ([]string{"border-solid", "border-dashed", "border-dotted", "border-double"}) {
				ui.key(c)
				ui.text(c, ui.cx("flex h-16 w-32 items-center justify-center rounded-lg border-4 border-indigo-500 font-mono text-xs text-gray-600 dark:text-gray-300", c))
			}
		}
	}
}

ex_outline :: proc() {
	h3("Widths, colors and styles")
	if example() {
		if ui.div("flex flex-wrap gap-6") {
			ui.button("outline", "rounded-md px-4 py-2 text-sm font-medium text-gray-900 outline outline-sky-500 dark:text-white")
			ui.button("outline-2", "rounded-md px-4 py-2 text-sm font-medium text-gray-900 outline-2 outline-sky-500 dark:text-white")
			ui.button("outline-dashed", "rounded-md px-4 py-2 text-sm font-medium text-gray-900 outline-2 outline-pink-500 outline-dashed dark:text-white")
		}
	}
	h3("Offset")
	if example() {
		if ui.div("flex gap-8") {
			for c in ([]string{"outline-offset-0", "outline-offset-2", "outline-offset-4"}) {
				ui.key(c)
				ui.button(c, ui.cx("rounded-md bg-indigo-500 px-4 py-2 font-mono text-xs font-medium text-white outline-2 outline-indigo-500", c))
			}
		}
	}
	h3("Focus rings")
	para("Press Tab while the preview is on screen: buttons show `focus-visible:` outlines only for keyboard focus.")
	if example() {
		if ui.div("flex gap-4") {
			ui.button("First", "rounded-md bg-gray-900 px-4 py-2 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-violet-500 dark:bg-white dark:text-gray-950")
			ui.button("Second", "rounded-md bg-gray-900 px-4 py-2 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-violet-500 dark:bg-white dark:text-gray-950")
		}
	}
}

shadow_card :: proc(label, class: string, loc := #caller_location) {
	if ui.div("flex flex-col items-center gap-3", loc = loc) {
		ui.text(label, "font-mono text-xs text-gray-500 dark:text-gray-400")
		ui.el(ui.cx("size-24 rounded-lg bg-white dark:bg-gray-800", class))
	}
}

ex_box_shadow :: proc() {
	h3("Basic example")
	para("Use `shadow-sm` … `shadow-2xl` for layered elevation shadows. Shadows are analytic gaussians computed per pixel, so large blurs cost the same as small ones.")
	if example("p-12") {
		if ui.div("grid grid-cols-3 gap-10") {
			for c in ([]string{"shadow-sm", "shadow-md", "shadow-lg", "shadow-xl", "shadow-2xl", "shadow-none"}) {
				ui.key(c)
				shadow_card(c, c)
			}
		}
	}
	h3("Setting the shadow color")
	if example("p-12") {
		if ui.div("flex gap-10") {
			ui.button("Subscribe", "rounded-lg bg-cyan-500 px-5 py-2 text-sm font-semibold text-white shadow-lg shadow-cyan-500/50")
			ui.button("Subscribe", "rounded-lg bg-blue-500 px-5 py-2 text-sm font-semibold text-white shadow-lg shadow-blue-500/50")
			ui.button("Subscribe", "rounded-lg bg-indigo-500 px-5 py-2 text-sm font-semibold text-white shadow-lg shadow-indigo-500/50")
		}
	}
	h3("Adding an inset shadow")
	if example("p-12") {
		if ui.div("flex gap-10") {
			for c in ([]string{"inset-shadow-2xs", "inset-shadow-xs", "inset-shadow-sm"}) {
				ui.key(c)
				shadow_card(c, ui.cx("bg-gray-50 ring-1 ring-gray-950/5 dark:bg-white/5", c))
			}
		}
	}
	h3("Adding a ring")
	if example("p-12") {
		if ui.div("flex gap-10") {
			ui.button("ring", "rounded-md bg-white px-4 py-2 text-sm font-medium text-gray-900 ring dark:bg-gray-800 dark:text-white")
			ui.button("ring-2", "rounded-md bg-white px-4 py-2 text-sm font-medium text-gray-900 ring-2 ring-sky-500 dark:bg-gray-800 dark:text-white")
			ui.button("ring-4", "rounded-md bg-white px-4 py-2 text-sm font-medium text-gray-900 ring-4 ring-pink-300 dark:bg-gray-800 dark:text-white")
		}
	}
	h3("Adding an inset ring")
	if example("p-12") {
		if ui.div("flex gap-10") {
			ui.button("inset-ring", "rounded-md bg-white px-4 py-2 text-sm font-medium text-gray-900 inset-ring inset-ring-gray-950/15 dark:bg-gray-800 dark:text-white dark:inset-ring-white/20")
			ui.button("inset-ring-2", "rounded-md bg-sky-50 px-4 py-2 text-sm font-medium text-sky-700 inset-ring-2 inset-ring-sky-500")
		}
	}
	h3("Ring offset")
	if example("p-12") {
		ui.button("ring-offset-2", "rounded-md bg-violet-500 px-4 py-2 text-sm font-medium text-white ring-2 ring-violet-500 ring-offset-2 ring-offset-white dark:ring-offset-gray-950")
	}
}

ex_text_shadow :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-4") {
			for c in ([]string{"text-shadow-2xs", "text-shadow-xs", "text-shadow-sm", "text-shadow-md", "text-shadow-lg"}) {
				ui.key(c)
				specimen(c, ui.cx("text-2xl font-semibold", c))
			}
		}
	}
}

ex_opacity :: proc() {
	h3("Basic example")
	if example() {
		if ui.div("flex gap-6") {
			for c in ([]string{"opacity-100", "opacity-75", "opacity-50", "opacity-25"}) {
				ui.key(c)
				if ui.div("flex flex-col items-center gap-2") {
					ui.text(c, "font-mono text-xs text-gray-500 dark:text-gray-400")
					ui.el(ui.cx("size-20 rounded-lg bg-indigo-500 shadow-lg", c))
				}
			}
		}
	}
	h3("Disabled state")
	if example() {
		ui.button("Disabled", "rounded-md bg-indigo-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 disabled:cursor-not-allowed", {.Disabled})
	}
}

ex_filters :: proc() {
	h3("Color filters")
	para("Color filters compile into a 4×5 color matrix applied by the shader to the element and its children: `grayscale`, `sepia`, `invert`, `brightness-*`, `contrast-*`, `saturate-*`, `hue-rotate-*`.")
	if example("p-8") {
		if ui.div("grid grid-cols-4 gap-4") {
			for c in ([]string{"", "grayscale", "sepia", "invert", "brightness-125", "contrast-150", "saturate-200", "hue-rotate-90"}) {
				ui.key(c)
				if ui.div("flex flex-col items-center gap-2") {
					ui.image(DEMO_IMAGE, ui.cx("size-28 rounded-lg object-cover", c))
					ui.text(c == "" ? "none" : c, "font-mono text-xs text-gray-500 dark:text-gray-400")
				}
			}
		}
	}
	h3("Applying on hover")
	if example() {
		ui.image(DEMO_IMAGE, "h-40 w-64 rounded-lg object-cover grayscale transition hover:grayscale-0")
	}
}

ex_drop_shadow :: proc() {
	h3("Basic example")
	if example("p-12") {
		if ui.div("flex gap-10") {
			for c in ([]string{"drop-shadow-md", "drop-shadow-lg", "drop-shadow-xl"}) {
				ui.key(c)
				shadow_card(c, c)
			}
		}
	}
	_ = fmt.tprint
}

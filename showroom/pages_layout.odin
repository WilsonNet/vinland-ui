package showroom

import "core:math"
import ui "../vui"

// Synthetic landscape used by image examples (generated at startup, no external asset).
DEMO_IMAGE: ui.Image_Id

make_demo_image :: proc(ctx: ^ui.Context) {
	W :: 960
	H :: 640
	pix := make([]u8, W * H * 4, context.temp_allocator)
	for y in 0 ..< H {
		for x in 0 ..< W {
			fx := f32(x) / W
			fy := f32(y) / H
			// dusk sky
			r := 0.98 - fy * 0.5
			g := 0.62 - fy * 0.25
			b := 0.55 + fy * 0.25
			// sun
			dx := fx - 0.68
			dy := fy - 0.42
			d := math.sqrt(dx * dx * 1.5 + dy * dy)
			sun := clamp(1 - d * 9, 0, 1)
			r += sun * 0.4
			g += sun * 0.35
			b += sun * 0.1
			// far ridge
			ridge1 := 0.55 + 0.06 * math.sin(fx * 9) + 0.03 * math.sin(fx * 23 + 1)
			if fy > ridge1 {
				r, g, b = 0.42, 0.36, 0.55
			}
			// near ridge
			ridge2 := 0.68 + 0.08 * math.sin(fx * 5 + 2) + 0.02 * math.sin(fx * 31)
			if fy > ridge2 {
				r, g, b = 0.22, 0.2, 0.36
			}
			// fjord water
			if fy > 0.82 {
				k := (fy - 0.82) / 0.18
				glow := clamp(1 - abs(fx - 0.68) * 5, 0, 1) * (1 - k)
				r = 0.24 - k * 0.08 + glow * 0.35
				g = 0.24 - k * 0.06 + glow * 0.22
				b = 0.46 - k * 0.1 + glow * 0.08
			}
			i := (y * W + x) * 4
			pix[i + 0] = u8(clamp(r, 0, 1) * 255)
			pix[i + 1] = u8(clamp(g, 0, 1) * 255)
			pix[i + 2] = u8(clamp(b, 0, 1) * 255)
			pix[i + 3] = 255
		}
	}
	DEMO_IMAGE = ui.image_register(ctx, pix, W, H)
}

register_layout_examples :: proc() {
	make_demo_image(ui.ctx_get())
	EXAMPLES["aspect-ratio"] = ex_aspect_ratio
	EXAMPLES["box-sizing"] = ex_box_sizing
	EXAMPLES["display"] = ex_display
	EXAMPLES["object-fit"] = ex_object_fit
	EXAMPLES["object-position"] = ex_object_position
	EXAMPLES["overflow"] = ex_overflow
	EXAMPLES["position"] = ex_position
	EXAMPLES["top-right-bottom-left"] = ex_inset
	EXAMPLES["visibility"] = ex_visibility
	EXAMPLES["z-index"] = ex_z_index
}

ex_aspect_ratio :: proc() {
	h3("Basic example")
	para("Use `aspect-<ratio>` utilities like `aspect-3/2` to give an element a specific aspect ratio.")
	if example() {
		ui.image(DEMO_IMAGE, "aspect-3/2 w-full max-w-sm rounded-lg object-cover")
	}
	h3("Using a video aspect ratio")
	para("Use `aspect-video` for 16:9 and `aspect-square` for 1:1.")
	if example() {
		if ui.div("flex w-full items-start gap-4") {
			ui.text("aspect-video", "flex aspect-video flex-1 items-center justify-center rounded-lg bg-sky-500 font-mono text-sm font-bold text-white")
			ui.text("square", "flex aspect-square w-24 items-center justify-center rounded-lg bg-pink-500 font-mono text-sm font-bold text-white")
		}
	}
}

ex_box_sizing :: proc() {
	h3("Including borders and padding")
	para("Every vinland-ui box is border-box: padding and borders are inside the declared size. Use `box-content` to add them on top.")
	if example() {
		if ui.div("flex gap-8") {
			if ui.div("box-border size-32 border-4 border-violet-400 bg-violet-500/20 p-4") {
				ui.text("box-border", "font-mono text-xs font-bold text-violet-700 dark:text-violet-300")
			}
			if ui.div("box-content size-32 border-4 border-sky-400 bg-sky-500/20 p-4") {
				ui.text("box-content", "font-mono text-xs font-bold text-sky-700 dark:text-sky-300")
			}
		}
	}
}

ex_display :: proc() {
	h3("Block and inline")
	para("Text runs inside `ui.p` flow inline and wrap together; boxes such as `ui.div` are block-level and start on their own line.")
	if example("p-8", false) {
		if ui.div("max-w-md text-sm/7 text-gray-700 dark:text-gray-300") {
			if ui.p() {
				ui.span("When controlling the flow of text, an ")
				ui.span("inline", "rounded bg-sky-500 px-1.5 font-mono text-white")
				ui.span(" run wraps with the words around it, so it can break across lines like this sentence does when the column gets narrow.")
			}
			ui.text("block", "mt-3 rounded bg-violet-500 px-2 py-1 font-mono text-white")
			ui.text("A block element fills the width and starts a new line.", "mt-3")
		}
	}
	h3("Flex, grid and hidden")
	para("Use `flex` and `grid` to create flex and grid containers, and `hidden` to remove an element from the layout.")
	if example() {
		if ui.div("flex items-center gap-4") {
			tile("01")
			ui.el("hidden size-14 bg-red-500")
			tile("02")
			tile("03")
		}
	}
}

ex_object_fit :: proc() {
	note("The landscape in these examples is generated in code at startup (synthetic), so the binary carries no image assets.")
	h3("Resizing to cover")
	para("Use `object-cover` to fill the box while keeping the image's aspect ratio, cropping what does not fit.")
	if example() {
		ui.image(DEMO_IMAGE, "h-48 w-96 rounded-lg bg-gray-200 object-cover dark:bg-white/5")
	}
	h3("Containing within")
	if example() {
		ui.image(DEMO_IMAGE, "h-48 w-96 rounded-lg bg-gray-200 object-contain dark:bg-white/5")
	}
	h3("Stretching to fit")
	if example() {
		ui.image(DEMO_IMAGE, "h-48 w-96 rounded-lg bg-gray-200 object-fill dark:bg-white/5")
	}
}

ex_object_position :: proc() {
	h3("Basic example")
	para("Use `object-top-left`, `object-center`, `object-bottom-right` and friends to choose which part of a covered image stays visible.")
	if example() {
		if ui.div("grid grid-cols-3 gap-4") {
			for c in ([]string{"object-top-left", "object-top", "object-top-right", "object-left", "object-center", "object-right", "object-bottom-left", "object-bottom", "object-bottom-right"}) {
				ui.key(c)
				ui.image(DEMO_IMAGE, ui.cx("size-24 rounded-md bg-gray-200 object-none dark:bg-white/5", c))
			}
		}
	}
}

ex_overflow :: proc() {
	h3("Hiding content that overflows")
	para("Use `overflow-hidden` to clip children to the padding box, including rounded corners.")
	if example() {
		if ui.div("w-64 overflow-hidden rounded-xl bg-white shadow-lg ring-1 ring-gray-950/5 dark:bg-gray-800") {
			ui.image(DEMO_IMAGE, "h-32 w-full object-cover")
			ui.text("The image is clipped by the card's corners.", "p-4 text-sm text-gray-600 dark:text-gray-300")
		}
	}
	h3("Scrolling if needed")
	para("Use `overflow-auto` (or `overflow-y-auto`) to make an element scroll when its content is larger than its box. Wheel input is smooth and the scrollbar can be dragged.")
	if example() {
		if ui.div("h-48 w-72 overflow-y-auto rounded-lg bg-gray-50 ring-1 ring-gray-950/5 dark:bg-white/5 dark:ring-white/10") {
			for name, i in ([]string{"Andrew Alfred", "Debra Houston", "Jane White", "Ray Flint", "Mindy Albrect", "David Arnold", "Erin Lee", "Caleb Price", "Lina Moss", "Owen Hart"}) {
				ui.key(i)
				if ui.div("flex items-center gap-3 px-4 py-2.5") {
					ui.el(i % 2 == 0 ? "size-8 rounded-full bg-violet-400" : "size-8 rounded-full bg-sky-400")
					ui.text(name, "text-sm font-medium text-gray-900 dark:text-gray-200")
				}
			}
		}
	}
	h3("Scrolling horizontally")
	if example() {
		if ui.div("w-full max-w-md overflow-x-auto rounded-lg bg-gray-50 dark:bg-white/5") {
			if ui.div("flex w-max gap-4 p-4") {
				for i in 0 ..< 10 {
					ui.key(i)
					ui.el("h-20 w-28 shrink-0 rounded-lg bg-linear-to-br from-violet-400 to-fuchsia-500")
				}
			}
		}
	}
}

ex_position :: proc() {
	h3("Relative and absolute")
	para("Use `relative` to make an element the reference for its `absolute` children.")
	if example() {
		if ui.div("relative h-40 w-72 rounded-lg bg-stripes stripes-violet-500/30 bg-violet-500/10 p-4") {
			ui.text("Relative parent", "font-mono text-xs font-bold text-violet-700 dark:text-violet-300")
			if ui.div("absolute right-0 bottom-0 rounded-lg bg-violet-500 p-4") {
				ui.text("Absolute child", "font-mono text-xs font-bold text-white")
			}
		}
	}
	h3("Fixed")
	para("Use `fixed` to position an element relative to the window. The search palette and the mobile navigation drawer in this app are fixed overlays.")
}

ex_inset :: proc() {
	h3("Basic example")
	para("Combine `top-*`, `right-*`, `bottom-*`, `left-*` and `inset-*` with absolute positioning.")
	if example() {
		if ui.div("grid grid-cols-3 gap-4") {
			for c in ([]string{"top-0 left-0", "inset-x-0 top-0", "top-0 right-0", "inset-y-0 left-0", "inset-0", "inset-y-0 right-0", "bottom-0 left-0", "inset-x-0 bottom-0", "right-0 bottom-0"}) {
				ui.key(c)
				if ui.div("relative size-24 rounded-lg bg-stripes stripes-violet-500/30 bg-violet-500/10") {
					ui.el(ui.cx("absolute rounded-lg bg-violet-500", c, c == "inset-0" ? "" : (c == "inset-x-0 top-0" || c == "inset-x-0 bottom-0" ? "h-8" : (c == "inset-y-0 left-0" || c == "inset-y-0 right-0" ? "w-8" : "size-8"))))
				}
			}
		}
	}
	h3("Centering with negative translate")
	if example() {
		if ui.div("relative h-32 w-64 rounded-lg bg-stripes stripes-sky-500/30 bg-sky-500/10") {
			ui.el("absolute top-1/2 left-1/2 size-12 -translate-x-1/2 -translate-y-1/2 rounded-full bg-sky-500 shadow-lg")
		}
	}
}

ex_visibility :: proc() {
	h3("Making elements invisible")
	para("Use `invisible` to hide an element while it still takes up space.")
	if example() {
		if ui.div("grid grid-cols-3 gap-4") {
			tile("01")
			tile("02", "invisible")
			tile("03")
		}
	}
}

ex_z_index :: proc() {
	h3("Basic example")
	para("Use `z-<number>` to control the stack order of positioned siblings.")
	if example() {
		if ui.div("flex") {
			for z, i in ([]string{"z-40", "z-30", "z-20", "z-10", "z-0"}) {
				ui.key(z)
				colors := [?]string{"bg-blue-500", "bg-indigo-500", "bg-violet-500", "bg-purple-500", "bg-fuchsia-500"}
				ui.text(z, ui.cx("relative flex size-16 items-center justify-center rounded-full font-mono text-xs font-bold text-white shadow-lg ring-2 ring-white dark:ring-gray-900", colors[i], z, i > 0 ? "-ml-3" : ""))
			}
		}
	}
}

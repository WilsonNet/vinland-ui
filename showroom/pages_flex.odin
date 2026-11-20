package showroom

import "core:fmt"
import ui "../vui"

register_flex_examples :: proc() {
	EXAMPLES["flex-basis"] = ex_flex_basis
	EXAMPLES["flex-direction"] = ex_flex_direction
	EXAMPLES["flex-wrap"] = ex_flex_wrap
	EXAMPLES["flex"] = ex_flex
	EXAMPLES["flex-grow"] = ex_flex_grow
	EXAMPLES["flex-shrink"] = ex_flex_shrink
	EXAMPLES["order"] = ex_order
	EXAMPLES["grid-template-columns"] = ex_grid_cols
	EXAMPLES["grid-column"] = ex_grid_column
	EXAMPLES["grid-template-rows"] = ex_grid_rows
	EXAMPLES["grid-row"] = ex_grid_row
	EXAMPLES["grid-auto-flow"] = ex_grid_flow
	EXAMPLES["grid-auto-columns"] = ex_grid_auto
	EXAMPLES["grid-auto-rows"] = ex_grid_auto
	EXAMPLES["gap"] = ex_gap
	EXAMPLES["justify-content"] = ex_justify_content
	EXAMPLES["justify-items"] = ex_justify_items
	EXAMPLES["justify-self"] = ex_justify_self
	EXAMPLES["align-content"] = ex_align_content
	EXAMPLES["align-items"] = ex_align_items
	EXAMPLES["align-self"] = ex_align_self
	EXAMPLES["place-content"] = ex_place_content
	EXAMPLES["place-items"] = ex_place_items
	EXAMPLES["place-self"] = ex_place_self
}

ex_flex_basis :: proc() {
	h3("Using the spacing scale")
	para("Use `basis-<number>` to set the initial main size of flex items.")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "basis-16")
			tile("02", "basis-32")
			tile("03", "basis-64")
		}
	}
	h3("Using fractions")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "basis-1/3")
			tile("02", "basis-2/3")
		}
	}
}

ex_flex_direction :: proc() {
	h3("Row")
	para("Use `flex-row` to position flex items horizontally in the same direction as text.")
	if example() {
		if ui.div("flex flex-row gap-4") {
			tile("01")
			tile("02")
			tile("03")
		}
	}
	h3("Row reversed")
	if example() {
		if ui.div("flex flex-row-reverse gap-4") {
			tile("01")
			tile("02")
			tile("03")
		}
	}
	h3("Column")
	if example() {
		if ui.div("flex w-48 flex-col gap-4") {
			tile("01")
			tile("02")
			tile("03")
		}
	}
	h3("Column reversed")
	if example() {
		if ui.div("flex w-48 flex-col-reverse gap-4") {
			tile("01")
			tile("02")
			tile("03")
		}
	}
}

ex_flex_wrap :: proc() {
	h3("Don't wrap")
	para("Use `flex-nowrap` to keep items on one line, shrinking them if needed.")
	if example("p-8", false) {
		if ui.div("flex flex-nowrap gap-4") {
			tile("01", "w-2/5 shrink-0")
			tile("02", "w-2/5 shrink-0")
			tile("03", "w-2/5")
		}
	}
	h3("Wrap normally")
	if example("p-8", false) {
		if ui.div("flex flex-wrap gap-4") {
			tile("01", "w-2/5")
			tile("02", "w-2/5")
			tile("03", "w-2/5")
		}
	}
	h3("Wrap reversed")
	if example("p-8", false) {
		if ui.div("flex h-44 flex-wrap-reverse content-start gap-4") {
			tile("01", "w-2/5")
			tile("02", "w-2/5")
			tile("03", "w-2/5")
		}
	}
}

ex_flex :: proc() {
	h3("Basic example")
	para("Use `flex-1` to let an item grow and shrink as needed, ignoring its initial size.")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "w-14 flex-none")
			tile("02", "w-64 flex-1")
			tile("03", "w-32 flex-1")
		}
	}
	h3("Initial")
	para("Use `flex-initial` to allow shrinking but not growing.")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "w-14 flex-none")
			tile("02", "w-64 flex-initial")
			tile("03", "w-32 flex-initial")
		}
	}
	h3("Auto")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "w-14 flex-none")
			tile("02", "w-64 flex-auto")
			tile("03", "w-32 flex-auto")
		}
	}
}

ex_flex_grow :: proc() {
	h3("Allowing items to grow")
	para("Use `grow` to let an item fill any available space.")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "size-14 flex-none")
			tile("02", "h-14 grow")
			tile("03", "size-14 flex-none")
		}
	}
	h3("Growing items based on factor")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "h-14 w-12 grow")
			tile("02", "h-14 w-12 grow-3")
			tile("03", "h-14 w-12 grow-7")
		}
	}
}

ex_flex_shrink :: proc() {
	h3("Allowing items to shrink")
	para("Use `shrink` to allow an item to shrink if needed, and `shrink-0` to prevent it.")
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "h-16 w-14 flex-none")
			tile("02", "h-16 w-64 shrink")
			tile("03", "h-16 w-14 flex-none")
		}
	}
	if example("p-8", false) {
		if ui.div("flex gap-4") {
			tile("01", "h-16 flex-1")
			tile("02", "h-16 w-64 shrink-0")
			tile("03", "h-16 flex-1")
		}
	}
}

ex_order :: proc() {
	h3("Explicitly setting a sort order")
	para("Use `order-<number>` to render items in a different order than they appear in code.")
	if example() {
		if ui.div("flex justify-between gap-4") {
			tile("01", "order-3")
			tile("02", "order-1")
			tile("03", "order-2")
		}
	}
	h3("Ordering items first or last")
	if example() {
		if ui.div("flex justify-between gap-4") {
			tile("01", "order-last")
			tile("02")
			tile("03", "order-first")
		}
	}
}

ex_grid_cols :: proc() {
	h3("Specifying the grid columns")
	para("Use `grid-cols-<number>` to create a grid with n equally sized columns.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-4 gap-4") {
			for i in 1 ..= 9 {
				ui.key(i)
				tile(fmt.tprintf("%02d", i))
			}
		}
	}
	h3("Using a custom value")
	para("Use arbitrary track lists like `grid-cols-[200px_minmax(0,1fr)_100px]`.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-[120px_minmax(0,1fr)_80px] gap-4") {
			tile("120px")
			tile("1fr")
			tile("80px")
		}
	}
}

ex_grid_column :: proc() {
	h3("Spanning columns")
	para("Use `col-span-<number>` to make an element span n columns.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-3 gap-4") {
			tile("01")
			tile("02")
			tile("03")
			tile("04", "col-span-2")
			tile("05")
			tile("06")
			tile("07", "col-span-2")
		}
	}
	h3("Starting and ending lines")
	if example("p-8", false) {
		if ui.div("grid grid-cols-6 gap-4") {
			tile("01", "col-span-4 col-start-2")
			tile("02", "col-start-1 col-end-3")
			tile("03", "col-span-2 col-end-7")
			tile("04", "col-start-1 col-end-7")
		}
	}
}

ex_grid_rows :: proc() {
	h3("Specifying the grid rows")
	para("Use `grid-rows-<number>` with `grid-flow-col` to fill rows first.")
	if example("p-8", false) {
		if ui.div("grid h-56 grid-flow-col grid-rows-4 gap-4") {
			for i in 1 ..= 9 {
				ui.key(i)
				tile(fmt.tprintf("%02d", i))
			}
		}
	}
}

ex_grid_row :: proc() {
	h3("Spanning rows")
	if example("p-8", false) {
		if ui.div("grid grid-flow-col grid-rows-3 gap-4") {
			tile("01", "row-span-3")
			tile("02", "col-span-2")
			tile("03", "col-span-2 row-span-2")
		}
	}
}

ex_grid_flow :: proc() {
	h3("Basic example")
	para("Use `grid-flow-row` or `grid-flow-col` to control how auto-placed items fill the grid.")
	if example("p-8", false) {
		if ui.div("grid grid-flow-row grid-cols-3 gap-4") {
			tile("01", "col-span-2")
			tile("02")
			tile("03")
			tile("04", "col-span-2")
			tile("05")
		}
	}
}

ex_grid_auto :: proc() {
	h3("Sizing implicit tracks")
	para("Use `auto-cols-*` and `auto-rows-*` to size tracks the grid creates implicitly.")
	if example("p-8", false) {
		if ui.div("grid grid-flow-col auto-cols-fr gap-4") {
			tile("01")
			tile("02")
			tile("03")
		}
	}
}

ex_gap :: proc() {
	h3("Basic example")
	para("Use `gap-<number>` to change the gutter between rows and columns.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-2 gap-4") {
			tile("01")
			tile("02")
			tile("03")
			tile("04")
		}
	}
	h3("Changing row and column gaps independently")
	if example("p-8", false) {
		if ui.div("grid grid-cols-3 gap-x-8 gap-y-4") {
			for i in 1 ..= 6 {
				ui.key(i)
				tile(fmt.tprintf("%02d", i))
			}
		}
	}
}

justify_demo :: proc(class: string, loc := #caller_location) {
	if ui.div(ui.cx("flex gap-4 rounded-lg bg-stripes stripes-violet-500/25", class), loc = loc) {
		tile("01", "w-14")
		tile("02", "w-14")
		tile("03", "w-14")
	}
}

ex_justify_content :: proc() {
	h3("Start")
	if example("p-8", false) {
		justify_demo("justify-start")
	}
	h3("Center")
	if example("p-8", false) {
		justify_demo("justify-center")
	}
	h3("End")
	if example("p-8", false) {
		justify_demo("justify-end")
	}
	h3("Space between")
	if example("p-8", false) {
		justify_demo("justify-between")
	}
	h3("Space around")
	if example("p-8", false) {
		justify_demo("justify-around")
	}
	h3("Space evenly")
	if example("p-8", false) {
		justify_demo("justify-evenly")
	}
}

ex_justify_items :: proc() {
	h3("Start, center and end")
	para("Use `justify-items-*` to align grid items along their inline axis.")
	for c in ([]string{"justify-items-start", "justify-items-center", "justify-items-end", "justify-items-stretch"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			if ui.div(ui.cx("grid grid-cols-3 gap-4 rounded-lg bg-stripes stripes-violet-500/25", c)) {
				for i in 1 ..= 6 {
					ui.key(i)
					tile(fmt.tprintf("%02d", i), c == "justify-items-stretch" ? "" : "w-14")
				}
			}
		}
	}
}

ex_justify_self :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("grid grid-cols-3 gap-4") {
			tile("01")
			if ui.div("rounded-lg bg-stripes stripes-violet-500/25 grid") {
				tile("02", "w-14 justify-self-center")
			}
			tile("03")
			tile("04")
			if ui.div("rounded-lg bg-stripes stripes-violet-500/25 grid") {
				tile("05", "w-14 justify-self-end")
			}
			tile("06")
		}
	}
}

ex_align_content :: proc() {
	for c in ([]string{"content-start", "content-center", "content-end", "content-between", "content-around", "content-evenly"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			if ui.div(ui.cx("grid h-56 grid-cols-3 gap-4 rounded-lg bg-stripes stripes-violet-500/25", c)) {
				for i in 1 ..= 5 {
					ui.key(i)
					tile(fmt.tprintf("%02d", i))
				}
			}
		}
	}
}

ex_align_items :: proc() {
	for c in ([]string{"items-stretch", "items-start", "items-center", "items-end", "items-baseline"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			if ui.div(ui.cx("flex gap-4 rounded-lg bg-stripes stripes-violet-500/25", c)) {
				tile("01", "pt-6 pb-12")
				tile("02", "pt-12 pb-6")
				tile("03", "pt-8 pb-8")
			}
		}
	}
}

ex_align_self :: proc() {
	for c in ([]string{"self-auto", "self-start", "self-center", "self-end", "self-stretch"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			if ui.div("flex h-40 items-stretch gap-4 rounded-lg bg-stripes stripes-violet-500/25") {
				tile("01", "flex-1")
				tile("02", ui.cx("flex-1", c))
				tile("03", "flex-1")
			}
		}
	}
}

ex_place_content :: proc() {
	for c in ([]string{"place-content-center", "place-content-start", "place-content-end", "place-content-between"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			if ui.div(ui.cx("grid h-48 grid-cols-2 gap-4 rounded-lg bg-stripes stripes-violet-500/25", c)) {
				for i in 1 ..= 4 {
					ui.key(i)
					tile(fmt.tprintf("%02d", i), "w-16")
				}
			}
		}
	}
}

ex_place_items :: proc() {
	for c in ([]string{"place-items-start", "place-items-center", "place-items-end", "place-items-stretch"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			if ui.div(ui.cx("grid h-56 grid-cols-3 gap-4 rounded-lg bg-stripes stripes-violet-500/25", c)) {
				for i in 1 ..= 6 {
					ui.key(i)
					tile(fmt.tprintf("%02d", i), c == "place-items-stretch" ? "" : "size-14")
				}
			}
		}
	}
}

ex_place_self :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("grid h-48 grid-cols-3 gap-4") {
			for c in ([]string{"place-self-start", "place-self-center", "place-self-end"}) {
				ui.key(c)
				if ui.div("grid rounded-lg bg-stripes stripes-violet-500/25") {
					tile("", ui.cx("size-14", c))
				}
			}
		}
	}
}

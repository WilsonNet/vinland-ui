// Fixture: a classic `for app.next_frame` loop (no app.run). Under vui-hot it still reloads,
// reopening its window each time; `app.keep` globals still carry over.
package plain

import "core:fmt"
import ui "vinland:vui"
import "vinland:vui/app"
import "vinland:vui/fonts"

clicks: int

MARKER :: "plain-1" // EDIT:marker

main :: proc() {
	ctx: ui.Context
	ui.init(&ctx)
	defer ui.destroy(&ctx)
	fonts.register(&ctx)
	a: app.App
	if !app.init(&a, {title = "plain fixture", size = {480, 320}, control_port = 7498}, &ctx) {
		return
	}
	defer app.shutdown(&a)
	app.keep(&clicks)
	for app.next_frame(&a) {
		if ui.div("flex h-full flex-col gap-2 bg-white p-6") {
			ui.text(MARKER, "text-lg font-semibold")
			if ui.button(fmt.tprintf("clicks %d", clicks), "rounded bg-sky-600 px-3 py-1 text-white") {
				clicks += 1
			}
		}
		app.end_frame(&a)
	}
}

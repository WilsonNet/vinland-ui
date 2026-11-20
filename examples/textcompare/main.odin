// Renders a fixed text specimen used to compare vinland-ui text against a browser.
package textcompare

import ui "../../vui"
import "../../vui/app"
import "../../vui/fonts"

main :: proc() {
	ctx: ui.Context
	ui.init(&ctx)
	defer ui.destroy(&ctx)
	fonts.register(&ctx)
	a: app.App
	if !app.init(&a, {title = "textcompare", size = {640, 360}, control_port = 7421}, &ctx) do return
	defer app.shutdown(&a)
	for app.next_frame(&a) {
		if ui.div("flex h-full flex-col") {
			if ui.div("flex-1 bg-white p-6") {
				ui.text("Utilities for controlling an element's padding.", "text-base text-gray-600")
				ui.text("The quick brown fox jumps over the lazy dog 0123456789", "mt-2 text-sm text-gray-950")
				ui.text("Hover, focus and other states", "mt-2 text-sm font-semibold text-gray-950")
				ui.text("padding-inline: calc(var(--spacing) * 4);", "mt-2 font-mono text-xs text-sky-700")
			}
			if ui.div("flex-1 bg-gray-950 p-6") {
				ui.text("Utilities for controlling an element's padding.", "text-base text-gray-400")
				ui.text("The quick brown fox jumps over the lazy dog 0123456789", "mt-2 text-sm text-white")
				ui.text("Hover, focus and other states", "mt-2 text-sm font-semibold text-white")
				ui.text("padding-inline: calc(var(--spacing) * 4);", "mt-2 font-mono text-xs text-sky-300")
			}
		}
		app.end_frame(&a)
	}
}

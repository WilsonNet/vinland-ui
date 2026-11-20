package hello

import "core:fmt"
import ui "../../vui"
import "../../vui/app"
import "../../vui/fonts"

main :: proc() {
	ctx: ui.Context
	ui.init(&ctx)
	fonts.register(&ctx)

	a: app.App
	if !app.init(&a, {title = "vinland-ui · hello", size = {900, 600}, control_port = 7420}, &ctx) {
		return
	}
	defer app.shutdown(&a)

	count := 0
	for app.next_frame(&a) {
		if ui.div("flex h-full flex-col items-center justify-center gap-6 bg-gray-50 dark:bg-gray-950") {
			if ui.div("w-96 rounded-2xl bg-white p-8 shadow-xl ring-1 ring-gray-950/5 dark:bg-gray-900 dark:ring-white/10") {
				ui.text("vinland-ui", "font-mono text-xs font-medium tracking-widest text-sky-600 uppercase dark:text-sky-400")
				ui.text("Crisp native UI for Odin", "mt-2 text-2xl font-semibold tracking-tight text-gray-950 dark:text-white")
				ui.text("Utility classes, design tokens and a renderer that draws text at your display's real pixel density.", "mt-3 text-sm/6 text-gray-600 dark:text-gray-400")
				if ui.div("mt-6 flex items-center gap-3") {
					if ui.button(fmt.tprintf("Clicked %d times", count), "rounded-full bg-gray-950 px-4 py-2 text-sm font-semibold text-white transition hover:bg-gray-800 dark:bg-white dark:text-gray-950 dark:hover:bg-gray-200") {
						count += 1
					}
					if ui.button("Toggle dark", "rounded-full px-4 py-2 text-sm font-semibold text-gray-950 ring-1 ring-gray-950/10 hover:bg-gray-50 dark:text-white dark:ring-white/15 dark:hover:bg-white/5") {
						ui.set_dark(!ui.is_dark())
					}
				}
			}
		}
		app.end_frame(&a)
	}
}

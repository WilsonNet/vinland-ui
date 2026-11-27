// A counter written as an app.Program. It builds and runs like any app:
//
//     odin build examples/counter -out:build/counter && ./build/counter
//
// and, unchanged, under hot reload:
//
//     ./build/vui-hot examples/counter
//
// Edit the text or the classes below and save: the window updates in about a second and the
// count (kept with app.keep) survives the reload.
package counter

import "core:fmt"
import ui "../../vui"
import "../../vui/app"
import "../../vui/fonts"

State :: struct {
	count: int,
	step:  int,
}

s: State

main :: proc() {
	app.run({
		config = {title = "vinland-ui · counter", size = {560, 360}, control_port = 7421},
		setup = proc(a: ^app.App) {
			fonts.register(a.ctx)
			app.keep(&s)
		},
		init = proc(a: ^app.App) {
			s.step = 1
		},
		frame = frame,
	})
}

frame :: proc(a: ^app.App) {
	if ui.div("flex h-full flex-col items-center justify-center gap-5 bg-gray-50 dark:bg-gray-950") {
		ui.text("Counter", "text-sm font-medium tracking-wide text-sky-700 uppercase dark:text-sky-400")
		ui.text(fmt.tprintf("%d", s.count), "text-6xl font-semibold tabular-nums text-gray-950 dark:text-white")
		if ui.div("flex gap-3") {
			if ui.button("−", "size-10 rounded-full bg-white text-lg font-semibold text-gray-900 ring-1 ring-gray-950/10 hover:bg-gray-100") {
				s.count -= s.step
			}
			if ui.button(fmt.tprintf("+%d", s.step), "h-10 rounded-full bg-sky-600 px-5 text-sm font-semibold text-white hover:bg-sky-500") {
				s.count += s.step
			}
		}
	}
}

// Fixture for tests/hot/test_hot.py. The tests copy this package to a temporary directory,
// start it under vui-hot (sandboxed: VUI_HIDDEN=1) and edit the copy. Markers in comments
// (EDIT:...) are the spots the tests rewrite.
package fixture

import "core:fmt"
import "core:os"
import "core:strings"
import ui "vinland:vui"
import "vinland:vui/app"
import "vinland:vui/fonts"

State :: struct {
	count: int,
	label: string,
	items: [dynamic]int,
	spare: [2]int,
	inits: int,
	// EDIT:fields
}

s: State
frames: int // not kept: resets on every load

MARKER :: "marker-1" // EDIT:marker
DATA :: #load("data.txt", string) // an asset: editing data.txt must rebuild
FLAG :: #config(FIXTURE_FLAG, false)

main :: proc() {
	app.run({
		config = {title = "hot fixture", size = {640, 480}, control_port = 7499},
		setup = proc(a: ^app.App) {
			fonts.register(a.ctx)
			app.keep(&s)
			a.on_command = on_command
		},
		init = proc(a: ^app.App) {
			s.label = "alpha"
			s.inits += 1
		},
		frame = frame,
	})
}

frame :: proc(a: ^app.App) {
	frames += 1
	if ui.div("flex h-full flex-col gap-3 bg-white p-6") {
		ui.text(MARKER, "text-lg font-semibold text-gray-950")
		ui.text(fmt.tprintf("count %d", s.count), "text-sm text-gray-700")
		if ui.button("increment", "rounded bg-sky-600 px-3 py-1 text-sm text-white") {
			s.count += 1
		}
		if ui.button("add item", "rounded bg-gray-200 px-3 py-1 text-sm") {
			append(&s.items, len(s.items))
		}
		// EDIT:frame
		if ui.div("h-48 overflow-y-auto rounded ring-1 ring-gray-200") {
			for i in 0 ..< 60 {
				ui.text(fmt.tprintf("row %d", i), "px-3 py-1 text-sm")
			}
		}
	}
}

on_command :: proc(a: ^app.App, cmd: string, args: map[string]string) -> string {
	switch cmd {
	case "state":
		sb := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&sb, `{{"ok":true,"count":%d,"label":"%s","items":%d,"marker":"%s","frames":%d,"inits":%d,"data":"%s","flag":%v,"args":[`, s.count, s.label, len(s.items), MARKER, frames, s.inits, strings.trim_space(DATA), FLAG)
		for arg, i in os.args {
			if i > 0 {
				strings.write_string(&sb, ",")
			}
			fmt.sbprintf(&sb, `"%s"`, arg)
		}
		strings.write_string(&sb, "]}")
		return strings.to_string(sb)
	case "crash":
		p: ^int
		p^ = 1 // deliberate segfault for the crash-restart tests
		return `{"ok":true}`
	}
	return ""
}

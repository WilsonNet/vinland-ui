// raylib bridge for vinland-ui: run a vui HUD inside a raylib game.
//
// The game keeps its window, GL context and frame loop; vui builds the UI and draws it over
// the finished frame with vinland:vui/gl.
//
//     host: vrl.Host
//     vrl.init(&host, &ctx)                   // after rl.InitWindow
//     for !rl.WindowShouldClose() {
//         handle_world_input(!vrl.pointer_over_ui(&host))
//         vrl.begin(&host, vrl.input())        // or patch the Input first (synthetic mice)
//         draw_hud()
//         vrl.end(&host)
//         rl.BeginDrawing(); draw_world(); vrl.render(&host); rl.EndDrawing()
//     }
//
// Keyboard: input() leaves keys out by default so game hotkeys (Space, letters) never
// activate a focused vui button. Pass keyboard = true for menus with text fields.
package vui_raylib

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import ui ".."
import vgl "../gl"

Host :: struct {
	ctx:   ^ui.Context,
	r:     vgl.Renderer,
	ready: bool,
	draw:  ^ui.Draw_List,
}

init :: proc(h: ^Host, ctx: ^ui.Context) -> bool {
	h.ctx = ctx
	h.ready = vgl.init(&h.r)
	return h.ready
}

destroy :: proc(h: ^Host) {
	if h.ready {
		vgl.destroy(&h.r, h.ctx)
	}
	h.ready = false
}

// Logical window size and display scale (raylib with FLAG_WINDOW_HIGHDPI).
viewport :: proc() -> (size: [2]f32, scale: f32) {
	size = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	scale = rl.GetWindowScaleDPI().x
	if scale <= 0 {
		scale = 1
	}
	return
}

@(private)
KEY_MAP := [?]struct {
	rk: rl.KeyboardKey,
	vk: ui.Key,
}{
	{.TAB, .Tab}, {.ENTER, .Enter}, {.ESCAPE, .Escape}, {.BACKSPACE, .Backspace}, {.DELETE, .Delete},
	{.LEFT, .Left}, {.RIGHT, .Right}, {.UP, .Up}, {.DOWN, .Down}, {.HOME, .Home}, {.END, .End},
	{.PAGE_UP, .Page_Up}, {.PAGE_DOWN, .Page_Down}, {.SPACE, .Space}, {.A, .A}, {.C, .C}, {.V, .V},
	{.X, .X}, {.Z, .Z}, {.Y, .Y}, {.K, .K}, {.F1, .F1}, {.F5, .F5}, {.F12, .F12}, {.SLASH, .Slash},
}

// Samples raylib's mouse (and optionally keyboard) state for this frame.
input :: proc(keyboard := false) -> (in_: ui.Input) {
	in_.mouse = rl.GetMousePosition()
	in_.mouse_inside = rl.IsCursorOnScreen()
	BUTTONS := [3]struct {
		rb: rl.MouseButton,
		vb: ui.Mouse_Button,
	}{{.LEFT, .Left}, {.RIGHT, .Right}, {.MIDDLE, .Middle}}
	for b in BUTTONS {
		if rl.IsMouseButtonDown(b.rb) {
			in_.buttons += {b.vb}
		}
		if rl.IsMouseButtonPressed(b.rb) {
			in_.pressed += {b.vb}
		}
		if rl.IsMouseButtonReleased(b.rb) {
			in_.released += {b.vb}
		}
	}
	in_.click_count = .Left in in_.pressed ? 1 : 0
	wheel := rl.GetMouseWheelMoveV()
	in_.wheel = {-wheel.x * 48, -wheel.y * 48}
	if !keyboard {
		return
	}
	for m in KEY_MAP {
		if rl.IsKeyPressed(m.rk) || rl.IsKeyPressedRepeat(m.rk) {
			in_.keys_pressed += {m.vk}
		}
		if rl.IsKeyDown(m.rk) {
			in_.keys_down += {m.vk}
		}
	}
	if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
		in_.mods += {.Shift}
	}
	if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
		in_.mods += {.Ctrl}
	}
	if rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT) {
		in_.mods += {.Alt}
	}
	if rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER) {
		in_.mods += {.Super}
	}
	buf: [64]u8
	n := 0
	for r := rl.GetCharPressed(); r != 0 && n + 4 <= len(buf); r = rl.GetCharPressed() {
		bytes, w := encode_rune(r)
		copy(buf[n:], bytes[:w])
		n += w
	}
	if n > 0 {
		in_.text = string(buf[:n])
		in_.text = clone_temp(in_.text)
	}
	return
}

begin :: proc(h: ^Host, in_: ui.Input) {
	size, scale := viewport()
	ui.begin_frame(h.ctx, in_, size, scale, rl.GetTime())
}

end :: proc(h: ^Host) -> ^ui.Draw_List {
	h.draw = ui.end_frame(h.ctx)
	return h.draw
}

// Draws the last built UI over the current raylib frame (call before rl.EndDrawing).
render :: proc(h: ^Host) {
	if !h.ready || h.draw == nil {
		return
	}
	rlgl.DrawRenderBatchActive()
	vgl.render(&h.r, h.ctx, h.draw, rl.GetRenderWidth(), rl.GetRenderHeight())
}

// True when the mouse is over UI (or a press that began on UI is still held): route world
// clicks only when this is false. Safe to call before this frame's UI is built.
pointer_over_ui :: proc(h: ^Host, mouse: Maybe([2]f32) = nil) -> bool {
	if !h.ready {
		return false
	}
	p := mouse.? or_else rl.GetMousePosition()
	return ui.pointer_over_ui(h.ctx, p)
}

// Shows a raylib texture (render target, minimap) inside the layout via ui.image.
texture_image :: proc(h: ^Host, tex: rl.Texture2D, render_target := false) -> ui.Image_Id {
	return ui.image_register_external(h.ctx, u64(tex.id), int(tex.width), int(tex.height), flip_y = render_target)
}

texture_update :: proc(h: ^Host, img: ui.Image_Id, tex: rl.Texture2D) {
	ui.image_external_update(h.ctx, img, u64(tex.id), int(tex.width), int(tex.height))
}

@(private)
encode_rune :: proc(r: rune) -> (b: [4]u8, n: int) {
	c := u32(r)
	switch {
	case c < 0x80:
		b[0] = u8(c)
		return b, 1
	case c < 0x800:
		b[0] = u8(0xC0 | (c >> 6))
		b[1] = u8(0x80 | (c & 0x3F))
		return b, 2
	case c < 0x10000:
		b[0] = u8(0xE0 | (c >> 12))
		b[1] = u8(0x80 | ((c >> 6) & 0x3F))
		b[2] = u8(0x80 | (c & 0x3F))
		return b, 3
	}
	b[0] = u8(0xF0 | (c >> 18))
	b[1] = u8(0x80 | ((c >> 12) & 0x3F))
	b[2] = u8(0x80 | ((c >> 6) & 0x3F))
	b[3] = u8(0x80 | (c & 0x3F))
	return b, 4
}

@(private)
clone_temp :: proc(s: string) -> string {
	out := make([]u8, len(s), context.temp_allocator)
	copy(out, s)
	return string(out)
}

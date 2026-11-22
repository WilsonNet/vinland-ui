package vui_app

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import vui ".."

// SDL3 + OpenGL host for vui. Owns the window, translates input, renders and runs the
// optional control server (see control.odin).
//
//     app: vui_app.App
//     vui_app.init(&app, {title = "Hello", size = {1200, 800}}, &ctx)
//     for vui_app.next_frame(&app) {
//         if ui.div("p-8") { ui.text("Hello", "text-2xl font-semibold") }
//         vui_app.end_frame(&app)
//     }
//     vui_app.shutdown(&app)

Config :: struct {
	title:        string,
	size:         [2]i32, // logical size
	min_size:     [2]i32,
	hidden:       bool, // render offscreen only (agents / tests)
	background:   bool, // visible but not activated on show; drive it through the control server (compositor still decides focus)
	scale:        f32, // force UI scale (0 = use display scale)
	control_port: int, // 0 = disabled
	vsync:        bool,
	app_id:       string, // Wayland app id / X11 class (window rules); "" = SDL default
}

Backend :: enum u8 {
	GPU, // SDL3 GPU API: Vulkan on Linux (Metal/D3D12 elsewhere)
	GL, // OpenGL 3.3 fallback
}

Synthetic_Kind :: enum u8 {
	Move,
	Down,
	Up,
	Wheel,
	Text,
	Key,
}

Synthetic :: struct {
	kind:   Synthetic_Kind,
	pos:    [2]f32,
	button: vui.Mouse_Button,
	wheel:  [2]f32,
	text:   string,
	key:    vui.Key,
	mods:   vui.Mods,
	clicks: int,
}

App :: struct {
	cfg:           Config,
	ctx:           ^vui.Context,
	window:        ^sdl.Window,
	gl_ctx:        sdl.GLContext,
	backend:       Backend,
	renderer:      Renderer, // OpenGL fallback
	gpu:           Gpu_Renderer, // SDL GPU (Vulkan)
	running:       bool,
	input:         vui.Input,
	mouse:         [2]f32,
	mouse_inside:  bool,
	keyboard_focus: bool,
	cursor_applied: bool,
	pointer_synthetic: bool, // last pointer event came from vui-ctl, not the real mouse
	buttons:       vui.Mouse_Buttons, // synthetic buttons held by vui-ctl
	real_buttons:  vui.Mouse_Buttons, // physical buttons held by the user
	text_buf:      strings.Builder,
	scale:         f32,
	logical:       [2]f32,
	pixels:        [2]i32,
	start_tick:    u64,
	dirty_frames:  int,
	cursors:       [vui.Cursor]^sdl.Cursor,
	cur_cursor:    vui.Cursor,
	text_input_on: bool,
	synthetic:     [dynamic]Synthetic,
	control:       ^Control,
	frame_ms:      f32,
	last_frame_t:  u64,
	user_event:    u32,
	// app hook for custom control commands: return JSON (or "" if unknown)
	on_command:    proc(app: ^App, cmd: string, args: map[string]string) -> string,
	user_data:     rawptr,
	// raw SDL event hook (keyboard shortcuts, drag-and-drop...): return true to consume the event
	on_event:      proc(app: ^App, e: ^sdl.Event) -> bool,
	clear_color:   vui.Color,
	screenshot_requests: [dynamic]^Control_Request,
	synthetic_mods: bool, // a synthetic key set modifiers; clear them next frame
	synthetic_held: vui.Mods, // modifiers held by a synthetic pointer gesture
	sandboxed:     bool, // headless on the offscreen driver + software GL (cannot touch the GPU)
	gl_renderer:   string,
	wait_requests: [dynamic]Wait_Request,
}

Wait_Request :: struct {
	req:    ^Control_Request,
	frames: int,
}

@(private)
g_app: ^App

@(private)
is_software_renderer :: proc(r: string) -> bool {
	l := strings.to_lower(r, context.temp_allocator)
	return strings.contains(l, "llvmpipe") || strings.contains(l, "softpipe") || strings.contains(l, "swrast") || strings.contains(l, "swiftshader")
}

// Runs a clipboard helper and returns its stdout. Public so apps and tests can
// use the same fallback path; no shell is involved.
clipboard_from_argv :: proc(argv: []string, allocator: mem.Allocator) -> (string, bool) {
	state, out, err, exec_err := os.process_exec(os.Process_Desc{command = argv}, context.allocator)
	defer delete(err)
	if exec_err != nil || !state.exited || state.exit_code != 0 {
		delete(out)
		return "", false
	}
	text := strings.clone(string(out), allocator)
	delete(out)
	return text, true
}

// SDL's clipboard can be empty on some Wayland/X11 combinations even while the
// desktop clipboard has data. Fall back to the standard utilities so text
// inputs stay usable in every session.
clipboard_read :: proc(allocator: mem.Allocator) -> string {
	t := sdl.GetClipboardText()
	if t != nil {
		s := string(cstring(t))
		if s != "" {
			// Clone before freeing SDL's buffer.
			result := strings.clone(s, allocator)
			sdl.free(rawptr(t))
			return result
		}
		sdl.free(rawptr(t))
	}
	wayland := os.get_env("WAYLAND_DISPLAY", context.temp_allocator)
	if wayland != "" {
		if text, ok := clipboard_from_argv([]string{"wl-paste"}, allocator); ok && text != "" {
			return text
		} else if ok {
			delete(text)
		}
	}
	display := os.get_env("DISPLAY", context.temp_allocator)
	if display != "" {
		if text, ok := clipboard_from_argv([]string{"xclip", "-selection", "clipboard", "-o"}, allocator); ok && text != "" {
			return text
		} else if ok {
			delete(text)
		}
		if text, ok := clipboard_from_argv([]string{"xsel", "--clipboard", "--output"}, allocator); ok && text != "" {
			return text
		} else if ok {
			delete(text)
		}
	}
	return ""
}

@(private)
clipboard_get :: proc(allocator: mem.Allocator) -> string {
	return clipboard_read(allocator)
}

@(private)
clipboard_set :: proc(s: string) {
	cs := strings.clone_to_cstring(s, context.temp_allocator)
	_ = sdl.SetClipboardText(cs)
}

init :: proc(app: ^App, config: Config, ctx: ^vui.Context) -> bool {
	app.cfg = config
	app.ctx = ctx
	g_app = app
	// environment overrides (handy for agents and CI)
	if v := os.get_env("VUI_HIDDEN", context.temp_allocator); v == "1" || v == "true" {
		app.cfg.hidden = true
	}
	// Background mode keeps the window visible but does not ask the compositor
	// to activate it on show, so an agent can drive it with vui-ctl while the
	// user keeps typing/clicking in another app (a game, an editor, a call).
	// The control server is the only input path: synthetic clicks never warp the
	// OS pointer. On X11 the non-focusable hint is honored by most WMs; on
	// Wayland the compositor decides, so VUI_HIDDEN=1 remains the hard
	// no-desktop-contact mode and a compositor no-focus rule is the belt-and-
	// braces option.
	if v := os.get_env("VUI_BACKGROUND", context.temp_allocator); v == "1" || v == "true" {
		app.cfg.background = true
	}
	if app.cfg.background {
		// Wayland uses this hint at map time; without it the compositor may
		// activate a newly shown window even though it is not focusable.
		_ = sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_SHOWN, "0")
	}
	if v := os.get_env("VUI_SCALE", context.temp_allocator); v != "" {
		if f, ok := strconv.parse_f32(v); ok && f > 0 {
			app.cfg.scale = f
		}
	}
	if v := os.get_env("VUI_PORT", context.temp_allocator); v != "" {
		if n, ok := strconv.parse_int(v); ok {
			app.cfg.control_port = n
		}
	}
	if v := os.get_env("VUI_SIZE", context.temp_allocator); v != "" {
		if x := strings.index_byte(v, 'x'); x > 0 {
			w, _ := strconv.parse_int(v[:x])
			h, _ := strconv.parse_int(v[x + 1:])
			if w > 0 && h > 0 {
				app.cfg.size = {i32(w), i32(h)}
			}
		}
	}
	if app.cfg.scale > 0 {
		// a wild scale (VUI_SCALE=1e9, inf) would mean wild framebuffer math
		app.cfg.scale = clamp(app.cfg.scale, 0.25, 8)
	}
	cfg := app.cfg
	if app.cfg.size == {0, 0} {
		app.cfg.size = {1280, 800}
	}
	_ = sdl.SetHint(sdl.HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "0")
	if cfg.app_id != "" {
		_ = sdl.SetHint(sdl.HINT_APP_ID, strings.clone_to_cstring(cfg.app_id, context.temp_allocator))
	}
	// Headless runs (tests, agents, site capture) are sandboxed by default, the way headless
	// browsers use SwiftShader: SDL's offscreen video driver (no compositor connection at all)
	// and Mesa's llvmpipe software rasterizer (no GPU memory). A headless run can never
	// starve or crash the user's desktop. VUI_HIDDEN_GPU=1 opts back into the real GPU.
	app.sandboxed = cfg.hidden && os.get_env("VUI_HIDDEN_GPU", context.temp_allocator) != "1"
	if app.sandboxed {
		_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "offscreen")
		_ = os.set_env("LIBGL_ALWAYS_SOFTWARE", "1")
		_ = os.set_env("GALLIUM_DRIVER", "llvmpipe")
		_ = os.set_env("MESA_LOADER_DRIVER_OVERRIDE", "swrast")
	}
	if !sdl.Init({.VIDEO, .EVENTS}) {
		fmt.eprintln("vui: SDL_Init failed:", sdl.GetError())
		return false
	}
	// Prefer the SDL GPU API (Vulkan); fall back to OpenGL 3.3. VUI_BACKEND=gl forces GL.
	want_gl := os.get_env("VUI_BACKEND", context.temp_allocator) == "gl" || app.sandboxed
	dev: ^sdl.GPUDevice
	if !want_gl {
		dev = sdl.CreateGPUDevice({.SPIRV}, false, nil)
	}
	app.backend = dev != nil ? .GPU : .GL
	title := strings.clone_to_cstring(cfg.title != "" ? cfg.title : "vinland-ui", context.temp_allocator)
	for attempt in 0 ..< 2 {
		flags: sdl.WindowFlags = {.RESIZABLE, .HIGH_PIXEL_DENSITY}
		if cfg.hidden {
			flags += {.HIDDEN}
		}
		if cfg.background {
			flags += {.NOT_FOCUSABLE}
		}
		if app.backend == .GL {
			_ = sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
			_ = sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
			_ = sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(transmute(u32)sdl.GL_CONTEXT_PROFILE_CORE))
			_ = sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
			_ = sdl.GL_SetAttribute(.DEPTH_SIZE, 0)
			flags += {.OPENGL}
		}
		app.window = sdl.CreateWindow(title, app.cfg.size.x, app.cfg.size.y, flags)
		if app.window == nil {
			fmt.eprintln("vui: CreateWindow failed:", sdl.GetError())
			return false
		}
		if app.backend == .GPU {
			if sdl.ClaimWindowForGPUDevice(dev, app.window) && gpu_init(&app.gpu, dev, app.window, !cfg.hidden) {
				break
			}
			fmt.eprintln("vui: GPU backend unavailable, falling back to OpenGL:", sdl.GetError())
			sdl.DestroyWindow(app.window)
			sdl.DestroyGPUDevice(dev)
			app.backend = .GL
			_ = attempt
			continue
		}
		app.gl_ctx = sdl.GL_CreateContext(app.window)
		if app.gl_ctx == nil {
			fmt.eprintln("vui: GL context failed:", sdl.GetError())
			return false
		}
		_ = sdl.GL_MakeCurrent(app.window, app.gl_ctx)
		gl.load_up_to(3, 3, sdl.gl_set_proc_address)
		if app.sandboxed {
			// refuse to run headless on hardware: that is how compositors get starved
			r := string(gl.GetString(gl.RENDERER))
			app.gl_renderer = strings.clone(r)
			if !is_software_renderer(r) {
				fmt.eprintfln("vui: headless run refused: GL renderer %q is hardware, expected llvmpipe/softpipe. Install mesa, or set VUI_HIDDEN_GPU=1 to use the GPU deliberately.", r)
				return false
			}
		}
		_ = sdl.GL_SetSwapInterval(app.cfg.hidden ? 0 : 1)
		if !renderer_init(&app.renderer) {
			return false
		}
		break
	}
	initial_focus := sdl.GetKeyboardFocus() == app.window
	if initial_focus {
		app.keyboard_focus = true
	}
	if cfg.min_size != {0, 0} {
		_ = sdl.SetWindowMinimumSize(app.window, cfg.min_size.x, cfg.min_size.y)
	}
	if os.get_env("VUI_QUIET", context.temp_allocator) == "" {
		fmt.eprintfln("vui: renderer %v%s%s", app.backend, app.backend == .GPU ? fmt.tprintf(" (%s)", app.gpu.driver) : "", app.sandboxed ? fmt.tprintf(" sandboxed: %s", app.gl_renderer) : "")
	}
	app.running = true
	app.start_tick = sdl.GetTicksNS()
	app.text_buf = strings.builder_make()
	app.user_event = sdl.RegisterEvents(1)
	ctx.clipboard_get = clipboard_get
	ctx.clipboard_set = clipboard_set
	update_metrics(app)
	if cfg.control_port > 0 {
		app.control = control_start(app, cfg.control_port)
	}
	app.dirty_frames = 3
	return true
}

shutdown :: proc(app: ^App) {
	if app.control != nil {
		control_stop(app.control)
	}
	if app.backend == .GPU {
		gpu_destroy(&app.gpu, app.ctx)
	} else {
		renderer_destroy(&app.renderer)
	}
	for c in app.cursors {
		if c != nil {
			sdl.DestroyCursor(c)
		}
	}
	strings.builder_destroy(&app.text_buf)
	delete(app.synthetic)
	delete(app.screenshot_requests)
	delete(app.wait_requests)
	if app.backend == .GL {
		_ = sdl.GL_DestroyContext(app.gl_ctx)
	}
	sdl.DestroyWindow(app.window)
	sdl.Quit()
}

// Largest framebuffer edge we render (offscreen targets for agents/tests are capped so a
// careless resize cannot exhaust the GPU memory shared with the desktop compositor).
MAX_FRAMEBUFFER :: 4096

@(private)
update_metrics :: proc(app: ^App) {
	defer {
		app.pixels.x = clamp(app.pixels.x, 0, MAX_FRAMEBUFFER)
		app.pixels.y = clamp(app.pixels.y, 0, MAX_FRAMEBUFFER)
		app.logical = {f32(app.pixels.x) / app.scale, f32(app.pixels.y) / app.scale}
	}
	pw, ph: i32
	_ = sdl.GetWindowSizeInPixels(app.window, &pw, &ph)
	app.pixels = {pw, ph}
	scale := sdl.GetWindowDisplayScale(app.window)
	if scale <= 0 {
		scale = 1
	}
	if app.cfg.scale > 0 {
		scale = app.cfg.scale
	}
	if app.cfg.hidden && app.cfg.scale > 0 {
		// hidden windows may report density 1: size the framebuffer explicitly
		ww, wh: i32
		_ = sdl.GetWindowSize(app.window, &ww, &wh)
		density := sdl.GetWindowPixelDensity(app.window)
		_ = density
		app.pixels = {i32(math.round(f32(ww) * scale)), i32(math.round(f32(wh) * scale))}
		app.logical = {f32(ww), f32(wh)}
		app.scale = scale
		return
	}
	app.scale = scale
	app.logical = {f32(pw) / scale, f32(ph) / scale}
}

// window point -> logical px
@(private)
to_logical :: proc(app: ^App, x, y: f32) -> [2]f32 {
	density := sdl.GetWindowPixelDensity(app.window)
	if density <= 0 {
		density = 1
	}
	return {x * density / app.scale, y * density / app.scale}
}

@(private)
map_key :: proc(k: sdl.Keycode) -> (vui.Key, bool) {
	switch k {
	case sdl.K_TAB:
		return .Tab, true
	case sdl.K_RETURN, sdl.K_KP_ENTER:
		return .Enter, true
	case sdl.K_ESCAPE:
		return .Escape, true
	case sdl.K_BACKSPACE:
		return .Backspace, true
	case sdl.K_DELETE:
		return .Delete, true
	case sdl.K_LEFT:
		return .Left, true
	case sdl.K_RIGHT:
		return .Right, true
	case sdl.K_UP:
		return .Up, true
	case sdl.K_DOWN:
		return .Down, true
	case sdl.K_HOME:
		return .Home, true
	case sdl.K_END:
		return .End, true
	case sdl.K_PAGEUP:
		return .Page_Up, true
	case sdl.K_PAGEDOWN:
		return .Page_Down, true
	case sdl.K_SPACE:
		return .Space, true
	case sdl.K_A:
		return .A, true
	case sdl.K_C:
		return .C, true
	case sdl.K_V:
		return .V, true
	case sdl.K_X:
		return .X, true
	case sdl.K_Z:
		return .Z, true
	case sdl.K_Y:
		return .Y, true
	case sdl.K_K:
		return .K, true
	case sdl.K_F1:
		return .F1, true
	case sdl.K_F5:
		return .F5, true
	case sdl.K_F12:
		return .F12, true
	case sdl.K_SLASH:
		return .Slash, true
	}
	return .Tab, false
}

@(private)
map_mods :: proc(m: sdl.Keymod) -> vui.Mods {
	r: vui.Mods
	if .LSHIFT in m || .RSHIFT in m {
		r += {.Shift}
	}
	if .LCTRL in m || .RCTRL in m {
		r += {.Ctrl}
	}
	if .LALT in m || .RALT in m {
		r += {.Alt}
	}
	if .LGUI in m || .RGUI in m {
		r += {.Super}
	}
	return r
}

@(private)
handle_event :: proc(app: ^App, e: ^sdl.Event) {
	in_ := &app.input
	if e.type == .KEY_DOWN || e.type == .KEY_UP {
		in_.mods = map_mods(e.key.mod) // keep modifiers current even when the app consumes keys
	}
	if app.on_event != nil && app.on_event(app, e) {
		return
	}
	#partial switch e.type {
	case .QUIT, .WINDOW_CLOSE_REQUESTED:
		app.running = false
	case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_DISPLAY_SCALE_CHANGED:
		update_metrics(app)
	case .WINDOW_MOUSE_LEAVE:
		app.mouse_inside = false
		// Re-apply the cursor on the next enter: SDL may have replaced it while
		// another window owned the pointer.
		app.cursor_applied = false
	case .WINDOW_MOUSE_ENTER:
		app.mouse_inside = true
		app.pointer_synthetic = false
		app.buttons = {}
	case .WINDOW_FOCUS_GAINED:
		app.keyboard_focus = true
	case .WINDOW_FOCUS_LOST:
		app.keyboard_focus = false
		app.cursor_applied = false
	case .MOUSE_MOTION:
		app.mouse = to_logical(app, e.motion.x, e.motion.y)
		app.mouse_inside = true
		app.pointer_synthetic = false
		// The real pointer takes over immediately: abandon a synthetic drag so a
		// stale down from a script cannot turn the user's motion into a drag.
		app.buttons = {}
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		app.mouse = to_logical(app, e.button.x, e.button.y)
		app.pointer_synthetic = false
		app.buttons = {}
		b: vui.Mouse_Button
		switch e.button.button {
		case 1:
			b = .Left
		case 2:
			b = .Middle
		case 3:
			b = .Right
		case:
			return
		}
		if e.button.down {
			app.real_buttons += {b}
			in_.pressed += {b}
			in_.click_count = int(e.button.clicks)
		} else {
			app.real_buttons -= {b}
			in_.released += {b}
		}
	case .MOUSE_WHEEL:
		dir: f32 = e.wheel.direction == .FLIPPED ? -1 : 1
		in_.wheel += {-e.wheel.x * 48 * dir, -e.wheel.y * 48 * dir}
	case .KEY_DOWN:
		if k, ok := map_key(e.key.key); ok {
			in_.keys_pressed += {k}
			in_.keys_down += {k}
		}
		in_.mods = map_mods(e.key.mod)
	case .KEY_UP:
		if k, ok := map_key(e.key.key); ok {
			in_.keys_down -= {k}
		}
		in_.mods = map_mods(e.key.mod)
	case .TEXT_INPUT:
		strings.write_string(&app.text_buf, string(e.text.text))
	}
}

@(private)
apply_synthetic :: proc(app: ^App) -> bool {
	if len(app.synthetic) == 0 {
		return false
	}
	s := app.synthetic[0]
	ordered_remove(&app.synthetic, 0)
	in_ := &app.input
	switch s.kind {
	case .Move:
		app.mouse = s.pos
		app.mouse_inside = true
		app.pointer_synthetic = true
	case .Down:
		app.mouse = s.pos
		app.mouse_inside = true
		app.pointer_synthetic = true
		app.buttons += {s.button}
		in_.pressed += {s.button}
		in_.click_count = max(s.clicks, 1)
	case .Up:
		app.mouse = s.pos
		app.pointer_synthetic = true
		app.buttons -= {s.button}
		in_.released += {s.button}
	case .Wheel:
		app.mouse = s.pos
		app.mouse_inside = true
		app.pointer_synthetic = true
		in_.wheel += s.wheel
	case .Text:
		strings.write_string(&app.text_buf, s.text)
		delete(s.text)
		// A typed run from vui-ctl is explicit: do not let a physically held
		// Shift/Ctrl leak into the app's interpretation of it.
		in_.mods = {}
		app.synthetic_mods = true
	case .Key:
		in_.keys_pressed += {s.key}
	}
	if s.kind == .Key || s.mods != {} {
		in_.mods = s.mods
		app.synthetic_mods = true
	}
	// modifiers sent with pointer steps stay held until the button is released, so the
	// idle frames between drag steps still see them (shift-drag)
	if s.kind == .Down || s.kind == .Move || s.kind == .Wheel {
		app.synthetic_held = s.mods
	}
	if s.kind == .Up {
		app.synthetic_held = {}
	}
	return true
}

now_seconds :: proc(app: ^App) -> f64 {
	return f64(sdl.GetTicksNS() - app.start_tick) / 1e9
}

// Pumps events and starts a UI frame. Returns false when the app should quit.
next_frame :: proc(app: ^App) -> bool {
	ctx := app.ctx
	app.input.pressed = {}
	app.input.released = {}
	app.input.wheel = {}
	app.input.keys_pressed = {}
	app.input.text = ""
	strings.builder_reset(&app.text_buf)
	if app.synthetic_mods {
		app.input.mods = app.synthetic_held
		app.synthetic_mods = app.synthetic_held != {}
	}

	busy := ctx.animating || app.dirty_frames > 0 || len(app.synthetic) > 0 || len(app.wait_requests) > 0 || len(app.screenshot_requests) > 0
	e: sdl.Event
	got := false
	if !busy {
		// idle: block until something happens (saves CPU), but wake periodically
		if sdl.WaitEventTimeout(&e, 500) {
			handle_event(app, &e)
			got = true
		}
	}
	for sdl.PollEvent(&e) {
		handle_event(app, &e)
		got = true
	}
	if app.control != nil {
		control_poll(app)
	}
	if apply_synthetic(app) {
		got = true
	}
	if got {
		app.dirty_frames = max(app.dirty_frames, 2)
	}
	if app.dirty_frames > 0 {
		app.dirty_frames -= 1
	}

	app.input.mouse = app.mouse
	app.input.mouse_inside = app.mouse_inside
	app.input.buttons = app.real_buttons + app.buttons
	app.input.text = strings.to_string(app.text_buf)
	if app.input.mods == {} && !app.synthetic_mods {
		app.input.mods = map_mods(sdl.GetModState())
	}
	vui.begin_frame(ctx, app.input, app.logical, app.scale, now_seconds(app))
	return app.running
}

@(private)
sdl_cursor :: proc(c: vui.Cursor) -> sdl.SystemCursor {
	#partial switch c {
	case .Pointer:
		return .POINTER
	case .Text:
		return .TEXT
	case .Move, .Grab, .Grabbing:
		return .MOVE
	case .Wait:
		return .WAIT
	case .Progress:
		return .PROGRESS
	case .Not_Allowed:
		return .NOT_ALLOWED
	case .Crosshair:
		return .CROSSHAIR
	case .Col_Resize, .EW_Resize:
		return .EW_RESIZE
	case .Row_Resize, .NS_Resize:
		return .NS_RESIZE
	case .NESW_Resize:
		return .NESW_RESIZE
	case .NWSE_Resize:
		return .NWSE_RESIZE
	}
	return .DEFAULT
}

// Lays out, renders and presents the frame.
end_frame :: proc(app: ^App) {
	ctx := app.ctx
	t0 := sdl.GetTicksNS()
	d := vui.end_frame(ctx)
	clear := app.clear_color
	if clear.a == 0 {
		clear = d.clear.a > 0 ? d.clear : (ctx.dark ? vui.Color{0.01, 0.03, 0.07, 1} : vui.WHITE)
	}
	if app.backend == .GPU {
		gpu_render(&app.gpu, ctx, d, app.pixels.x, app.pixels.y, clear, !app.cfg.hidden)
	} else {
		render(&app.renderer, ctx, d, app.pixels.x, app.pixels.y, clear)
	}
	app.frame_ms = f32(sdl.GetTicksNS() - t0) / 1e6

	// cursor
	//
	// Synthetic hover must never drive the OS cursor: on X11 ShowCursor applies
	// to every window in this process, and on Wayland it applies to the seat's
	// pointer focus. Gate on real pointer state and skip entirely while the last
	// pointer event came from vui-ctl. This keeps a script from leaving the app's
	// cursor hidden or stale for the user's next real entry.
	app.keyboard_focus = sdl.GetKeyboardFocus() == app.window
	if !app.mouse_inside {
		// Another window owns the pointer; do not touch its cursor. Mark dirty so
		// the normal cursor is restored when the pointer comes back.
		app.cursor_applied = false
	} else if !app.pointer_synthetic && (ctx.cursor != app.cur_cursor || !app.cursor_applied) {
		app.cur_cursor = ctx.cursor
		app.cursor_applied = true
		if ctx.cursor == .None {
			_ = sdl.HideCursor()
		} else {
			if app.cursors[ctx.cursor] == nil {
				app.cursors[ctx.cursor] = sdl.CreateSystemCursor(sdl_cursor(ctx.cursor))
			}
			_ = sdl.ShowCursor()
			_ = sdl.SetCursor(app.cursors[ctx.cursor])
		}
	}
	// text input (IME): only a window with real keyboard focus may enable it.
	// A synthetic click on a text field must not start IME; a user who focuses
	// a background window with a real click can still type normally.
	want_text_input := ctx.text_input_wanted && app.keyboard_focus && !app.cfg.hidden
	if want_text_input != app.text_input_on {
		app.text_input_on = want_text_input
		if app.text_input_on {
			_ = sdl.StartTextInput(app.window)
		} else {
			_ = sdl.StopTextInput(app.window)
		}
	}
	if app.control != nil {
		control_after_frame(app)
	}
	if !app.cfg.hidden {
		if app.backend == .GL {
			_ = sdl.GL_SwapWindow(app.window)
		}
		if app.backend == .GPU && app.gpu.occluded {
			// occluded windows get no vsync; pace them instead of spinning the GPU
			sdl.Delay(16)
		} else {
			// safety net when vsync is not honored (swap interval refused, compositor
			// not throttling): never present faster than 250 fps
			MIN_FRAME_NS :: 4_000_000
			now := sdl.GetTicksNS()
			if app.last_frame_t != 0 && now - app.last_frame_t < MIN_FRAME_NS {
				sdl.DelayNS(MIN_FRAME_NS - (now - app.last_frame_t))
			}
		}
		app.last_frame_t = sdl.GetTicksNS()
	} else {
		// no vsync offscreen: always pace at ~60 fps. An unpaced offscreen loop can
		// queue GPU work faster than it retires and exhaust shared VRAM.
		sdl.Delay(16)
	}
	free_all(context.temp_allocator)
	_ = time.Duration(0)
}

// Wakes the event loop (thread-safe).
wake :: proc(app: ^App) {
	e: sdl.Event
	e.type = sdl.EventType(app.user_event)
	_ = sdl.PushEvent(&e)
}

request_redraw :: proc(app: ^App) {
	app.dirty_frames = max(app.dirty_frames, 2)
	// Cross-thread callers (audio meters, jobs) must wake the idle wait, which
	// otherwise blocks for up to 500 ms.
	wake(app)
}

// Reads the last rendered frame as RGBA8 (top-down, straight alpha).
read_frame :: proc(app: ^App, allocator := context.allocator) -> (pixels: []u8, w, h: i32) {
	if app.backend == .GPU {
		return gpu_read_pixels(&app.gpu, allocator)
	}
	return read_pixels(&app.renderer, allocator)
}

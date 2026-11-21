package vui_app

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"
import vui ".."

// Control server: lets a CLI (tools/vui-ctl) or test script drive a running app.
// Protocol: connect to 127.0.0.1:<port>, send one JSON object per line, read one JSON line back.
//
//   {"cmd":"screenshot","path":"out.png"}
//   {"cmd":"click","x":120,"y":40}            logical px
//   {"cmd":"click_text","text":"Padding"}     clicks the first element whose text matches
//   {"cmd":"move","x":..,"y":..}  {"cmd":"scroll","x":..,"y":..,"dy":300}
//   {"cmd":"type","text":"hello"} {"cmd":"key","key":"tab","mods":"shift"}
//   {"cmd":"resize","w":1280,"h":800}  {"cmd":"dark","on":true}
//   {"cmd":"tree","depth":8}  {"cmd":"info"}  {"cmd":"wait","frames":10}  {"cmd":"settle"}
//   {"cmd":"gamma","value":1.0}  {"cmd":"quit"}
//   {"cmd":"down","x":..,"y":..} {"cmd":"up","x":..,"y":..}   drags: down, move..., up
//   {"cmd":"find","text":"Save","nth":0,"exact":true}   -> found, count, rect, text
//   click_text and find match case-insensitive substrings; "exact":true matches the whole text
// Any other command is forwarded to App.on_command.

Control_Request :: struct {
	line:     string,
	response: string,
	done:     sync.Sema,
}

Control :: struct {
	app:      ^App,
	port:     int,
	sock:     net.TCP_Socket,
	thread:   ^thread.Thread,
	mutex:    sync.Mutex,
	queue:    [dynamic]^Control_Request,
	stopping: bool,
}

control_start :: proc(app: ^App, port: int) -> ^Control {
	c := new(Control)
	c.app = app
	c.port = port
	sock, err := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = port})
	if err != nil {
		fmt.eprintfln("vui: control server could not listen on 127.0.0.1:%d (%v)", port, err)
		free(c)
		return nil
	}
	c.sock = sock
	c.thread = thread.create_and_start_with_poly_data(c, control_thread)
	fmt.eprintfln("vui: control server on 127.0.0.1:%d", port)
	return c
}

control_stop :: proc(c: ^Control) {
	c.stopping = true
	// accept() is not interrupted by close() on Linux; shut the socket down and let the
	// thread die with the process instead of joining it.
	net.shutdown(c.sock, .Both)
	net.close(c.sock)
}

@(private)
control_thread :: proc(c: ^Control) {
	for !c.stopping {
		client, _, err := net.accept_tcp(c.sock)
		if err != nil {
			if c.stopping {
				return
			}
			continue
		}
		handle_client(c, client)
		net.close(client)
	}
}

@(private)
handle_client :: proc(c: ^Control, client: net.TCP_Socket) {
	buf: [65536]u8
	acc := make([dynamic]u8, context.temp_allocator)
	defer free_all(context.temp_allocator)
	for {
		n, err := net.recv_tcp(client, buf[:])
		if err != nil || n <= 0 {
			return
		}
		append(&acc, ..buf[:n])
		for {
			nl := -1
			for b, i in acc {
				if b == '\n' {
					nl = i
					break
				}
			}
			if nl < 0 {
				break
			}
			line := strings.clone(string(acc[:nl]))
			remove_range(&acc, 0, nl + 1)
			req := new(Control_Request)
			req.line = line
			sync.mutex_lock(&c.mutex)
			append(&c.queue, req)
			sync.mutex_unlock(&c.mutex)
			wake(c.app)
			sync.sema_wait(&req.done)
			resp := strings.concatenate({req.response, "\n"}, context.temp_allocator)
			net.send_tcp(client, transmute([]u8)resp)
			delete(req.response)
			delete(req.line)
			free(req)
		}
	}
}

@(private)
respond :: proc(req: ^Control_Request, s: string) {
	req.response = strings.clone(s)
	sync.sema_post(&req.done)
}

@(private)
respond_ok :: proc(req: ^Control_Request) {
	respond(req, `{"ok":true}`)
}

@(private)
respond_err :: proc(req: ^Control_Request, msg: string) {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, `{"ok":false,"error":`)
	vui.json_str(&sb, msg)
	strings.write_string(&sb, "}")
	respond(req, strings.to_string(sb))
}

@(private)
arg_f :: proc(obj: json.Object, k: string, def: f32 = 0) -> f32 {
	#partial switch v in obj[k] {
	case json.Float:
		return f32(v)
	case json.Integer:
		return f32(v)
	case json.String:
		f, ok := strconv.parse_f32(v)
		if ok {
			return f
		}
	}
	return def
}

@(private)
arg_s :: proc(obj: json.Object, k: string) -> string {
	#partial switch v in obj[k] {
	case json.String:
		return v
	case json.Integer:
		return fmt.tprint(v)
	case json.Float:
		return fmt.tprint(v)
	case json.Boolean:
		return v ? "true" : "false"
	}
	return ""
}

@(private)
arg_b :: proc(obj: json.Object, k: string, def := false) -> bool {
	#partial switch v in obj[k] {
	case json.Boolean:
		return v
	case json.String:
		return v == "true" || v == "1" || v == "on"
	case json.Integer:
		return v != 0
	}
	return def
}

@(private)
key_from_name :: proc(s: string) -> (vui.Key, bool) {
	switch strings.to_lower(s, context.temp_allocator) {
	case "tab":
		return .Tab, true
	case "enter", "return":
		return .Enter, true
	case "escape", "esc":
		return .Escape, true
	case "backspace":
		return .Backspace, true
	case "delete", "del":
		return .Delete, true
	case "left":
		return .Left, true
	case "right":
		return .Right, true
	case "up":
		return .Up, true
	case "down":
		return .Down, true
	case "home":
		return .Home, true
	case "end":
		return .End, true
	case "pageup":
		return .Page_Up, true
	case "pagedown":
		return .Page_Down, true
	case "space":
		return .Space, true
	case "a":
		return .A, true
	case "c":
		return .C, true
	case "v":
		return .V, true
	case "x":
		return .X, true
	case "z":
		return .Z, true
	case "k":
		return .K, true
	case "/", "slash":
		return .Slash, true
	case "f1":
		return .F1, true
	}
	return .Tab, false
}

@(private)
push_click :: proc(app: ^App, p: [2]f32, button: vui.Mouse_Button, clicks: int) {
	append(&app.synthetic, Synthetic{kind = .Move, pos = p})
	append(&app.synthetic, Synthetic{kind = .Down, pos = p, button = button, clicks = 1})
	append(&app.synthetic, Synthetic{kind = .Up, pos = p, button = button})
	if clicks >= 2 {
		append(&app.synthetic, Synthetic{kind = .Down, pos = p, button = button, clicks = 2})
		append(&app.synthetic, Synthetic{kind = .Up, pos = p, button = button})
	}
}

@(private)
wait_then_respond :: proc(app: ^App, req: ^Control_Request, frames: int) {
	append(&app.wait_requests, Wait_Request{req = req, frames = frames})
}

// Called on the main thread before a frame is built (the previous layout is still valid).
control_poll :: proc(app: ^App) {
	c := app.control
	sync.mutex_lock(&c.mutex)
	reqs := make([]^Control_Request, len(c.queue), context.temp_allocator)
	copy(reqs, c.queue[:])
	clear(&c.queue)
	sync.mutex_unlock(&c.mutex)
	for req in reqs {
		control_handle(app, req)
	}
}

@(private)
control_handle :: proc(app: ^App, req: ^Control_Request) {
	ctx := app.ctx
	root, err := json.parse(transmute([]u8)req.line, allocator = context.temp_allocator)
	if err != nil {
		respond_err(req, "invalid json")
		return
	}
	obj, ok := root.(json.Object)
	if !ok {
		respond_err(req, "expected object")
		return
	}
	cmd := arg_s(obj, "cmd")
	switch cmd {
	case "ping":
		respond(req, `{"ok":true,"pong":true}`)
	case "info":
		unknown := vui.unknown_classes(ctx)
		sb := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&sb, `{{"ok":true,"logical":[%.1f,%.1f],"pixels":[%d,%d],"scale":%.4f,"dark":%v,"frame":%d,"frame_ms":%.2f,"nodes":%d,"draw_cmds":%d,"atlas":[%d,%d],"text_gamma":%.3f,"backend":"%v","sandboxed":%v,"gl_renderer":"%s","unknown_classes":[`, app.logical.x, app.logical.y, app.pixels.x, app.pixels.y, app.scale, ctx.dark, ctx.frame, app.frame_ms, len(ctx.nodes), len(ctx.draw.cmds), ctx.atlas.w, ctx.atlas.h, ctx.text_gamma, app.backend, app.sandboxed, app.gl_renderer)
		for u, i in unknown {
			if i > 0 {
				strings.write_string(&sb, ",")
			}
			vui.json_str(&sb, u)
		}
		strings.write_string(&sb, "]}")
		respond(req, strings.to_string(sb))
	case "tree":
		depth := int(arg_f(obj, "depth", 64))
		sb := strings.builder_make(context.temp_allocator)
		strings.write_string(&sb, `{"ok":true,"nodes":`)
		vui.debug_tree(ctx, &sb, depth)
		strings.write_string(&sb, "}")
		respond(req, strings.to_string(sb))
	case "screenshot":
		append(&app.screenshot_requests, req)
		app.dirty_frames = max(app.dirty_frames, 1)
	case "move":
		append(&app.synthetic, Synthetic{kind = .Move, pos = {arg_f(obj, "x"), arg_f(obj, "y")}})
		wait_then_respond(app, req, 2)
	case "click":
		b := vui.Mouse_Button.Left
		switch arg_s(obj, "button") {
		case "right":
			b = .Right
		case "middle":
			b = .Middle
		}
		push_click(app, {arg_f(obj, "x"), arg_f(obj, "y")}, b, int(arg_f(obj, "clicks", 1)))
		wait_then_respond(app, req, 3)
	case "down", "up":
		b := vui.Mouse_Button.Left
		switch arg_s(obj, "button") {
		case "right":
			b = .Right
		case "middle":
			b = .Middle
		}
		pos := [2]f32{arg_f(obj, "x", app.mouse.x), arg_f(obj, "y", app.mouse.y)}
		append(&app.synthetic, Synthetic{kind = .Move, pos = pos})
		append(&app.synthetic, Synthetic{kind = .Down if cmd == "down" else .Up, pos = pos, button = b, clicks = 1})
		wait_then_respond(app, req, 2)
	case "find":
		// {"cmd":"find","text":"Save","nth":0} -> rect of the nth visible text match and the match count
		needle := strings.to_lower(arg_s(obj, "text"), context.temp_allocator)
		nth := int(arg_f(obj, "nth", 0))
		exact, _ := obj["exact"].(json.Boolean)
		count := 0
		hit: vui.Rect
		hit_text := ""
		for &n in ctx.nodes {
			if n.para < 0 || n.style.display == .None || n.rect.w <= 0 {
				continue
			}
			b := strings.builder_make(context.temp_allocator)
			for sp in ctx.paras[n.para].spans {
				strings.write_string(&b, sp.text)
			}
			t := strings.to_string(b)
			lt := strings.to_lower(t, context.temp_allocator)
			if (bool(exact) && strings.trim_space(lt) == needle) || (!bool(exact) && strings.contains(lt, needle)) {
				if count == nth {
					hit = n.rect
					hit_text = t
				}
				count += 1
			}
		}
		sb := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&sb, `{{"ok":true,"found":%v,"count":%d,"x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f,"text":`, count > nth, count, hit.x, hit.y, hit.w, hit.h)
		vui.json_str(&sb, hit_text)
		strings.write_string(&sb, "}")
		respond(req, strings.to_string(sb))
	case "click_text":
		exact, _ := obj["exact"].(json.Boolean)
		p, found := vui.find_text(ctx, arg_s(obj, "text"), int(arg_f(obj, "nth", 0)), bool(exact))
		if !found {
			respond_err(req, "text not found")
			return
		}
		push_click(app, p, .Left, 1)
		app.synthetic[0].pos = p
		sb := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&sb, `{{"ok":true,"x":%.1f,"y":%.1f}}`, p.x, p.y)
		req_resp := strings.to_string(sb)
		_ = req_resp
		wait_then_respond(app, req, 3)
	case "scroll":
		p := [2]f32{arg_f(obj, "x", app.logical.x / 2), arg_f(obj, "y", app.logical.y / 2)}
		append(&app.synthetic, Synthetic{kind = .Move, pos = p})
		append(&app.synthetic, Synthetic{kind = .Wheel, pos = p, wheel = {arg_f(obj, "dx"), arg_f(obj, "dy")}})
		wait_then_respond(app, req, 20)
	case "type":
		append(&app.synthetic, Synthetic{kind = .Text, text = strings.clone(arg_s(obj, "text"))})
		wait_then_respond(app, req, 2)
	case "key":
		k, kok := key_from_name(arg_s(obj, "key"))
		if !kok {
			respond_err(req, "unknown key")
			return
		}
		mods: vui.Mods
		ms := arg_s(obj, "mods")
		if strings.contains(ms, "shift") {
			mods += {.Shift}
		}
		if strings.contains(ms, "ctrl") {
			mods += {.Ctrl}
		}
		if strings.contains(ms, "alt") {
			mods += {.Alt}
		}
		append(&app.synthetic, Synthetic{kind = .Key, key = k, mods = mods})
		wait_then_respond(app, req, 2)
	case "resize":
		w := i32(arg_f(obj, "w", f32(app.cfg.size.x)))
		h := i32(arg_f(obj, "h", f32(app.cfg.size.y)))
		_ = sdl.SetWindowSize(app.window, w, h)
		if app.cfg.hidden {
			app.cfg.size = {w, h}
		}
		update_metrics(app)
		wait_then_respond(app, req, 4)
	case "dark":
		ctx.dark = arg_b(obj, "on", !ctx.dark)
		wait_then_respond(app, req, 2)
	case "gamma":
		ctx.text_gamma = arg_f(obj, "value", 1)
		wait_then_respond(app, req, 2)
	case "wait":
		wait_then_respond(app, req, int(arg_f(obj, "frames", 2)))
	case "settle":
		wait_then_respond(app, req, -int(arg_f(obj, "max", 240)))
	case "quit":
		app.running = false
		respond_ok(req)
	case:
		if app.on_command != nil {
			args := make(map[string]string, 8, context.temp_allocator)
			for k, _ in obj {
				args[k] = arg_s(obj, k)
			}
			r := app.on_command(app, cmd, args)
			if r != "" {
				// let the app's change render before answering
				append(&app.wait_requests, Wait_Request{req = req, frames = 3})
				req.response = strings.clone(r)
				return
			}
		}
		respond_err(req, fmt.tprintf("unknown command: %s", cmd))
	}
}

// Called after rendering (before swap): screenshots and frame-count waits.
control_after_frame :: proc(app: ^App) {
	if len(app.screenshot_requests) > 0 && len(app.synthetic) == 0 {
		pixels, w, h := read_frame(app, context.temp_allocator)
		for req in app.screenshot_requests {
			root, _ := json.parse(transmute([]u8)req.line, allocator = context.temp_allocator)
			obj, _ := root.(json.Object)
			path := arg_s(obj, "path")
			if path == "" {
				path = "screenshot.png"
			}
			cpath := strings.clone_to_cstring(path, context.temp_allocator)
			// optional crop in logical px
			x := int(arg_f(obj, "x", 0) * app.scale)
			y := int(arg_f(obj, "y", 0) * app.scale)
			cw := int(arg_f(obj, "w", 0) * app.scale)
			ch := int(arg_f(obj, "h", 0) * app.scale)
			ok: i32
			if cw > 0 && ch > 0 {
				x = clamp(x, 0, int(w) - 1)
				y = clamp(y, 0, int(h) - 1)
				cw = min(cw, int(w) - x)
				ch = min(ch, int(h) - y)
				ok = stbi.write_png(cpath, i32(cw), i32(ch), 4, &pixels[(y * int(w) + x) * 4], w * 4)
			} else {
				ok = stbi.write_png(cpath, w, h, 4, raw_data(pixels), w * 4)
			}
			if ok == 0 {
				respond_err(req, "png write failed")
			} else {
				sb := strings.builder_make(context.temp_allocator)
				strings.write_string(&sb, `{"ok":true,"path":`)
				vui.json_str(&sb, path)
				fmt.sbprintf(&sb, `,"width":%d,"height":%d,"scale":%.4f}}`, cw > 0 ? cw : int(w), ch > 0 ? ch : int(h), app.scale)
				respond(req, strings.to_string(sb))
			}
		}
		clear(&app.screenshot_requests)
	}
	if len(app.wait_requests) > 0 && len(app.synthetic) == 0 {
		i := 0
		for i < len(app.wait_requests) {
			w := &app.wait_requests[i]
			done := false
			if w.frames < 0 {
				// settle: until nothing animates (or max frames)
				w.frames += 1
				done = !app.ctx.animating || w.frames >= 0
			} else {
				w.frames -= 1
				done = w.frames <= 0
			}
			if done {
				if w.req.response != "" {
					sync.sema_post(&w.req.done)
				} else {
					respond_ok(w.req)
				}
				ordered_remove(&app.wait_requests, i)
			} else {
				i += 1
			}
		}
	}
}

#+build js
// Browser host for vinland-ui: WebGL2 renderer + DOM input, one UI per <canvas>.
// Build with `odin build <pkg> -target:js_wasm32` and load with Odin's odin.js runtime.
package vui_web

import "core:fmt"
import "core:math"
import "core:strings"
import js "core:sys/wasm/js"
import gl "vendor:wasm/WebGL"
import vui ".."

VS_HEAD :: `#version 300 es
precision highp float;
layout(location=0) in vec4 a_size;
layout(location=1) in vec4 a_radii;
layout(location=2) in vec4 a_fill0;
layout(location=3) in vec4 a_fill1;
layout(location=4) in vec4 a_fill2;
layout(location=5) in vec4 a_bw;
layout(location=6) in vec4 a_bc;
layout(location=7) in vec4 a_grad;
layout(location=8) in vec4 a_params;
layout(location=9) in vec4 a_uv;
layout(location=10) in vec4 a_clip;
layout(location=11) in vec4 a_clipr;
layout(location=12) in vec4 a_xf;
layout(location=13) in vec4 a_xt;
layout(location=14) in vec4 a_extra;
uniform vec2 u_viewport;
out vec2 v_local;
out vec2 v_world;
flat out vec4 f_size, f_radii, f_fill0, f_fill1, f_fill2, f_bw, f_bc, f_grad, f_params, f_uv, f_clip, f_clipr, f_xt, f_extra;
`

FS_HEAD :: `#version 300 es
precision highp float;
precision highp int;
in vec2 v_local;
in vec2 v_world;
flat in vec4 f_size, f_radii, f_fill0, f_fill1, f_fill2, f_bw, f_bc, f_grad, f_params, f_uv, f_clip, f_clipr, f_xt, f_extra;
uniform sampler2D u_atlas;
uniform sampler2D u_image;
uniform vec2 u_atlas_size;
uniform mat4 u_filters[16];
uniform vec4 u_filter_off[16];
uniform float u_text_gamma;
uniform float u_text_contrast;
uniform vec4 u_grade;
uniform vec4 u_grade_tint;
out vec4 o_color;
`

VS_BODY :: #load("../app/shaders/ui_vs_body.glsl", string)
FS_BODY :: #load("../app/shaders/ui_fs_body.glsl", string)

Surface :: struct {
	id:        string,
	ctx:       vui.Context,
	build:     proc(),
	ok:        bool,
	program:   gl.Program,
	vao:       gl.VertexArrayObject,
	vbo:       gl.Buffer,
	vbo_cap:   int,
	atlas:     gl.Texture,
	atlas_gen: u32,
	atlas_w:   int,
	atlas_h:   int,
	white:     gl.Texture,
	images:    [dynamic]gl.Texture,
	u:         struct {
		viewport, atlas, image, atlas_size, gamma, contrast, filter_off, grade, grade_tint: i32,
		filters: [16]i32,
	},
	// input
	input:     vui.Input,
	mouse:     [2]f32,
	inside:    bool,
	buttons:   vui.Mouse_Buttons,
	text:      strings.Builder,
	dirty:     int,
	cursor:    vui.Cursor,
	size:      [2]f32,
	dpr:       f32,
	time:      f64,
}

surfaces: [dynamic]^Surface

// Optional hook run once per context (register fonts, icons, theme tokens).
setup_proc: proc(ctx: ^vui.Context)

@(private)
compile :: proc(kind: gl.Enum, head, body: string) -> (gl.Shader, bool) {
	sh := gl.CreateShader(kind)
	gl.ShaderSource(sh, {head, body})
	gl.CompileShader(sh)
	if gl.GetShaderiv(sh, gl.COMPILE_STATUS) == 0 {
		buf: [2048]u8
		fmt.println(gl.GetShaderInfoLog(sh, buf[:]))
		return sh, false
	}
	return sh, true
}

// Attaches a UI to the canvas with the given element id. Returns false when the canvas
// does not exist or WebGL2 is unavailable (the page keeps its static fallback).
mount :: proc(id: string, build: proc()) -> bool {
	s := new(Surface)
	s.id = id
	s.build = build
	if !gl.CreateCurrentContextById(id, {.stencil}) {
		free(s)
		return false
	}
	major, minor: i32
	gl.GetWebGLVersion(&major, &minor)
	if major < 2 {
		free(s)
		return false
	}
	vs, vok := compile(gl.VERTEX_SHADER, VS_HEAD, VS_BODY)
	fs, fok := compile(gl.FRAGMENT_SHADER, FS_HEAD, FS_BODY)
	if !vok || !fok {
		free(s)
		return false
	}
	s.program = gl.CreateProgram()
	gl.AttachShader(s.program, vs)
	gl.AttachShader(s.program, fs)
	gl.LinkProgram(s.program)
	if gl.GetProgramParameter(s.program, gl.LINK_STATUS) == 0 {
		buf: [2048]u8
		fmt.println(gl.GetProgramInfoLog(s.program, buf[:]))
		free(s)
		return false
	}
	s.u.viewport = gl.GetUniformLocation(s.program, "u_viewport")
	s.u.atlas = gl.GetUniformLocation(s.program, "u_atlas")
	s.u.image = gl.GetUniformLocation(s.program, "u_image")
	s.u.atlas_size = gl.GetUniformLocation(s.program, "u_atlas_size")
	s.u.gamma = gl.GetUniformLocation(s.program, "u_text_gamma")
	s.u.contrast = gl.GetUniformLocation(s.program, "u_text_contrast")
	s.u.grade = gl.GetUniformLocation(s.program, "u_grade")
	s.u.grade_tint = gl.GetUniformLocation(s.program, "u_grade_tint")
	s.u.filter_off = gl.GetUniformLocation(s.program, "u_filter_off")
	for i in 0 ..< 16 {
		name := strings.concatenate({"u_filters[", digits(i), "]"}, context.temp_allocator)
		s.u.filters[i] = gl.GetUniformLocation(s.program, name)
	}
	s.vao = gl.CreateVertexArray()
	gl.BindVertexArray(s.vao)
	s.vbo = gl.CreateBuffer()
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vbo)
	for i in 0 ..< 15 {
		gl.EnableVertexAttribArray(i32(i))
		gl.VertexAttribDivisor(u32(i), 1)
	}
	white := [4]u8{255, 255, 255, 255}
	s.white = gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, s.white)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, 4, &white[0])
	// the default min filter wants mipmaps: without these the texture is incomplete
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))

	vui.init(&s.ctx)
	if setup_proc != nil {
		setup_proc(&s.ctx)
	}
	s.text = strings.builder_make()
	s.dirty = 3
	listen(s)
	append(&surfaces, s)
	s.ok = true
	return true
}

@(private)
digits :: proc(n: int) -> string {
	DIG := [10]string{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
	return n < 10 ? DIG[n] : strings.concatenate({digits(n / 10), digits(n % 10)}, context.temp_allocator)
}

@(private)
map_key :: proc(k: string) -> (vui.Key, bool) {
	switch k {
	case "Tab":
		return .Tab, true
	case "Enter":
		return .Enter, true
	case "Escape":
		return .Escape, true
	case "Backspace":
		return .Backspace, true
	case "Delete":
		return .Delete, true
	case "ArrowLeft":
		return .Left, true
	case "ArrowRight":
		return .Right, true
	case "ArrowUp":
		return .Up, true
	case "ArrowDown":
		return .Down, true
	case "Home":
		return .Home, true
	case "End":
		return .End, true
	case " ":
		return .Space, true
	case "a", "A":
		return .A, true
	case "c", "C":
		return .C, true
	case "v", "V":
		return .V, true
	case "x", "X":
		return .X, true
	}
	return .Tab, false
}

@(private)
listen :: proc(s: ^Surface) {
	on :: proc(e: js.Event) {
		s := cast(^Surface)e.user_data
		s.dirty = max(s.dirty, 2)
		#partial switch e.kind {
		case .Mouse_Move:
			s.mouse = {f32(e.mouse.offset.x), f32(e.mouse.offset.y)}
			s.inside = true
		case .Mouse_Out:
			// only trust leave events whose position is really outside the canvas
			p := [2]f32{f32(e.mouse.offset.x), f32(e.mouse.offset.y)}
			if p.x < 0 || p.y < 0 || p.x >= s.size.x || p.y >= s.size.y {
				s.inside = false
			}
		case .Mouse_Down:
			s.mouse = {f32(e.mouse.offset.x), f32(e.mouse.offset.y)}
			s.inside = true
			b: vui.Mouse_Button = e.mouse.button == 2 ? .Right : (e.mouse.button == 1 ? .Middle : .Left)
			s.buttons += {b}
			s.input.pressed += {b}
			s.input.click_count = 1
		case .Mouse_Up:
			s.mouse = {f32(e.mouse.offset.x), f32(e.mouse.offset.y)}
			s.inside = true
			b: vui.Mouse_Button = e.mouse.button == 2 ? .Right : (e.mouse.button == 1 ? .Middle : .Left)
			s.buttons -= {b}
			s.input.released += {b}
		case .Double_Click:
			s.input.click_count = 2
		case .Wheel:
			s.input.wheel += {f32(e.wheel.delta[0]), f32(e.wheel.delta[1])}
		case .Key_Down:
			key := e.key.key
			mods: vui.Mods
			if e.key.shift {
				mods += {.Shift}
			}
			if e.key.ctrl {
				mods += {.Ctrl}
			}
			if e.key.alt {
				mods += {.Alt}
			}
			if e.key.meta {
				mods += {.Super}
			}
			s.input.mods = mods
			if k, ok := map_key(key); ok {
				s.input.keys_pressed += {k}
				if k == .Tab || k == .Space || k == .Backspace {
					js.event_prevent_default()
				}
			}
			if len(key) > 0 && e.key.char != 0 && !e.key.ctrl && !e.key.meta && key != "Enter" && key != "Tab" {
				strings.write_rune(&s.text, e.key.char)
			}
		case .Focus_Out, .Blur:
			s.inside = false
		}
	}
	kinds := [?]js.Event_Kind{.Mouse_Move, .Mouse_Out, .Mouse_Down, .Mouse_Up, .Double_Click, .Wheel, .Key_Down, .Blur}
	for k in kinds {
		js.add_event_listener(s.id, k, s, on)
	}
}

@(private)
css_cursor :: proc(c: vui.Cursor) -> string {
	#partial switch c {
	case .Pointer:
		return "pointer"
	case .Text:
		return "text"
	case .Not_Allowed:
		return "not-allowed"
	case .Move, .Grab:
		return "grab"
	case .Grabbing:
		return "grabbing"
	case .Crosshair:
		return "crosshair"
	case .Wait:
		return "wait"
	case .EW_Resize, .Col_Resize:
		return "ew-resize"
	case .NS_Resize, .Row_Resize:
		return "ns-resize"
	}
	return "default"
}

// Draws every mounted surface that needs it. Call from `step`.
frame :: proc(dt: f64, dark: bool) {
	for s in surfaces {
		s.time += dt
		r := js.get_bounding_client_rect(s.id)
		dpr := f32(js.device_pixel_ratio())
		size := [2]f32{f32(r.width), f32(r.height)}
		// skip offscreen canvases
		// getBoundingClientRect is viewport-relative; window_get_rect reports the screen size
		win := js.window_get_rect()
		if r.y > win.height || r.y + r.height < 0 || size.x <= 0 || size.y <= 0 {
			continue
		}
		// same framebuffer cap as the native host (vui_app.MAX_FRAMEBUFFER)
		if dpr <= 0 || dpr != dpr {
			dpr = 1
		}
		dpr = min(dpr, 4096 / max(size.x, size.y, 1))
		if size != s.size || dpr != s.dpr || s.ctx.dark != dark {
			s.size = size
			s.dpr = dpr
			s.dirty = max(s.dirty, 2)
			js.set_element_key_f64(s.id, "width", f64(math.round(size.x * dpr)))
			js.set_element_key_f64(s.id, "height", f64(math.round(size.y * dpr)))
		}
		if s.dirty <= 0 && !s.ctx.animating {
			continue
		}
		s.dirty -= 1
		draw_surface(s, dark)
	}
}

// Canvas id of the surface being built (lets one build proc serve many canvases).
current_id :: proc() -> string {
	return building.id if building != nil else ""
}

@(private)
building: ^Surface

@(private)
draw_surface :: proc(s: ^Surface, dark: bool) {
	gl.SetCurrentContextById(s.id)
	s.input.mouse = s.mouse
	s.input.mouse_inside = s.inside
	s.input.buttons = s.buttons
	s.input.text = strings.to_string(s.text)
	s.ctx.dark = dark
	vui.begin_frame(&s.ctx, s.input, s.size, s.dpr, s.time)
	building = s
	s.build()
	building = nil
	d := vui.end_frame(&s.ctx)
	s.input.pressed = {}
	s.input.released = {}
	s.input.wheel = {}
	s.input.keys_pressed = {}
	s.input.click_count = 0
	strings.builder_reset(&s.text)
	if s.ctx.cursor != s.cursor {
		s.cursor = s.ctx.cursor
		js.set_element_style(s.id, "cursor", css_cursor(s.cursor))
	}
	render(s, d)
	free_all(context.temp_allocator)
}

@(private)
render :: proc(s: ^Surface, d: ^vui.Draw_List) {
	ctx := &s.ctx
	fw := gl.DrawingBufferWidth()
	fh := gl.DrawingBufferHeight()
	// atlas
	a := &ctx.atlas
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	if s.atlas == 0 || s.atlas_gen != a.generation || s.atlas_w != a.w || s.atlas_h != a.h {
		if s.atlas == 0 {
			s.atlas = gl.CreateTexture()
		}
		gl.BindTexture(gl.TEXTURE_2D, s.atlas)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R8, i32(a.w), i32(a.h), 0, gl.RED, gl.UNSIGNED_BYTE, len(a.pixels), raw_data(a.pixels))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
		s.atlas_gen = a.generation
		s.atlas_w = a.w
		s.atlas_h = a.h
		a.dirty = false
	} else if a.dirty {
		y0 := clamp(a.dirty_y0, 0, a.h)
		y1 := clamp(a.dirty_y1, 0, a.h)
		gl.BindTexture(gl.TEXTURE_2D, s.atlas)
		if y1 > y0 {
			gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, i32(y0), i32(a.w), i32(y1 - y0), gl.RED, gl.UNSIGNED_BYTE, (y1 - y0) * a.w, &a.pixels[y0 * a.w])
		}
		a.dirty = false
	}
	// images
	for &img, i in ctx.images {
		for len(s.images) <= i {
			append(&s.images, gl.Texture(0))
		}
		if !img.dirty {
			continue
		}
		img.dirty = false
		if img.w <= 0 || img.h <= 0 || len(img.pixels) < img.w * img.h * 4 {
			continue
		}
		if s.images[i] == 0 {
			s.images[i] = gl.CreateTexture()
		}
		gl.BindTexture(gl.TEXTURE_2D, s.images[i])
		gl.PixelStorei(gl.UNPACK_ALIGNMENT, 4)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(img.w), i32(img.h), 0, gl.RGBA, gl.UNSIGNED_BYTE, len(img.pixels), raw_data(img.pixels))
		gl.GenerateMipmap(gl.TEXTURE_2D)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR_MIPMAP_LINEAR))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
	}

	gl.Viewport(0, 0, fw, fh)
	gl.ClearColor(0, 0, 0, 0)
	gl.Clear(u32(gl.COLOR_BUFFER_BIT))
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
	gl.UseProgram(s.program)
	gl.Uniform2f(s.u.viewport, f32(fw), f32(fh))
	gl.Uniform2f(s.u.atlas_size, f32(a.w), f32(a.h))
	gl.Uniform1i(s.u.atlas, 0)
	gl.Uniform1i(s.u.image, 1)
	gl.Uniform1f(s.u.gamma, ctx.text_gamma > 0 ? ctx.text_gamma : 1)
	gl.Uniform1f(s.u.contrast, 1)
	gr, gt := vui.grade_uniforms(ctx.grade, ctx.scale)
	gl.Uniform4f(s.u.grade, gr[0], gr[1], gr[2], gr[3])
	gl.Uniform4f(s.u.grade_tint, gt[0], gt[1], gt[2], gt[3])
	offs: [16][4]f32
	for i in 0 ..< min(len(d.filters), 16) {
		gl.UniformMatrix4fv(s.u.filters[i], d.filters[i].m)
		offs[i] = d.filters[i].o
	}
	gl.Uniform4fv(s.u.filter_off, offs[:])

	gl.BindVertexArray(s.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vbo)
	n := min(len(d.cmds), vui.MAX_DRAW_CMDS)
	if n > s.vbo_cap {
		s.vbo_cap = clamp(n + n / 2, 1024, vui.MAX_DRAW_CMDS)
		gl.BufferData(gl.ARRAY_BUFFER, s.vbo_cap * size_of(vui.Draw_Cmd), nil, gl.DYNAMIC_DRAW)
	}
	if n > 0 {
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, n * size_of(vui.Draw_Cmd), raw_data(d.cmds))
	}
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, s.atlas)
	stride := size_of(vui.Draw_Cmd)
	for b in d.batches {
		if b.count <= 0 || int(b.first) >= n {
			continue
		}
		count := min(int(b.count), n - int(b.first))
		gl.ActiveTexture(gl.TEXTURE1)
		tex := s.white
		if b.image != 0 && int(b.image) <= len(s.images) && s.images[b.image - 1] != 0 {
			tex = s.images[b.image - 1]
		}
		gl.BindTexture(gl.TEXTURE_2D, tex)
		base := uintptr(int(b.first) * stride)
		for i in 0 ..< 15 {
			gl.VertexAttribPointer(i32(i), 4, gl.FLOAT, false, stride, base + uintptr(i * 16))
		}
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count)
	}
}

// Embeddable OpenGL 3.3 renderer for vui draw lists.
//
// Use this when another engine owns the window, the GL context and the frame loop (a game on
// raylib, GLFW or SDL_GL): build the UI with ui.begin_frame / ui.end_frame as usual, then call
// `render` after the game has drawn its world. It draws straight into whatever framebuffer is
// bound, never clears it, and restores the GL state it touches, so the host's own renderer
// keeps working. All UI is one instanced draw per texture batch.
//
// The shader bodies are the same files the vui_app GL/Vulkan backends use
// (vui/app/shaders/ui_{vs,fs}_body.glsl), so the embedded UI renders pixel-identically.
package vui_gl

import "core:dynlib"
import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import vui ".."

MAX_FILTERS :: vui.MAX_DRAW_FILTERS

Renderer :: struct {
	program:         u32,
	vao:             u32,
	vbo:             u32,
	vbo_cap:         int,
	atlas_tex:       u32,
	atlas_gen:       u32,
	atlas_w:         int,
	atlas_h:         int,
	white_tex:       u32,
	u_viewport:      i32,
	u_atlas:         i32,
	u_image:         i32,
	u_atlas_size:    i32,
	u_filters:       i32,
	u_filter_off:    i32,
	u_text_gamma:    i32,
	u_text_contrast: i32,
	u_grade:         i32,
	u_grade_tint:    i32,
	lib:             dynlib.Library,
	// stats for the host's profiler / control API
	last_cmds:       int,
	last_batches:    int,
}

VS :: `#version 330 core
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
` + #load("../app/shaders/ui_vs_body.glsl", string)

FS :: `#version 330 core
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

` + #load("../app/shaders/ui_fs_body.glsl", string)

// Loads the GL entry points from the system GL library. Hosts that already have a loader
// (SDL_GL_GetProcAddress, glfwGetProcAddress) can call gl.load_up_to themselves and skip this.
load_gl :: proc(r: ^Renderer) -> bool {
	for path in gl_library_paths() {
		if lib, ok := dynlib.load_library(path); ok {
			r.lib = lib
			break
		}
	}
	if r.lib == nil {
		fmt.eprintln("vui_gl: could not open the system OpenGL library")
		return false
	}
	@(static) lib_for_loader: dynlib.Library
	lib_for_loader = r.lib
	gl.load_up_to(3, 3, proc(p: rawptr, name: cstring) {
		(^rawptr)(p)^ = gl_lookup(lib_for_loader, string(name))
	})
	return gl.CreateShader != nil && gl.DrawArraysInstanced != nil
}

@(private)
compile_shader :: proc(kind: u32, src: string) -> (u32, bool) {
	sh := gl.CreateShader(kind)
	cs := strings.clone_to_cstring(src, context.temp_allocator)
	gl.ShaderSource(sh, 1, &cs, nil)
	gl.CompileShader(sh)
	ok: i32
	gl.GetShaderiv(sh, gl.COMPILE_STATUS, &ok)
	if ok == 0 {
		buf: [4096]u8
		n: i32
		gl.GetShaderInfoLog(sh, len(buf), &n, &buf[0])
		fmt.eprintln("vui_gl: shader compile error:", string(buf[:n]))
		return 0, false
	}
	return sh, true
}

// Call once, with the host's GL context current.
init :: proc(r: ^Renderer, load := true) -> bool {
	if load && !load_gl(r) {
		return false
	}
	prev_vao, prev_buf, prev_tex: i32
	gl.GetIntegerv(gl.VERTEX_ARRAY_BINDING, &prev_vao)
	gl.GetIntegerv(gl.ARRAY_BUFFER_BINDING, &prev_buf)
	gl.GetIntegerv(gl.TEXTURE_BINDING_2D, &prev_tex)
	defer {
		gl.BindVertexArray(u32(prev_vao))
		gl.BindBuffer(gl.ARRAY_BUFFER, u32(prev_buf))
		gl.BindTexture(gl.TEXTURE_2D, u32(prev_tex))
	}

	vs, vok := compile_shader(gl.VERTEX_SHADER, VS)
	fs, fok := compile_shader(gl.FRAGMENT_SHADER, FS)
	if !vok || !fok {
		return false
	}
	r.program = gl.CreateProgram()
	gl.AttachShader(r.program, vs)
	gl.AttachShader(r.program, fs)
	gl.LinkProgram(r.program)
	ok: i32
	gl.GetProgramiv(r.program, gl.LINK_STATUS, &ok)
	gl.DeleteShader(vs)
	gl.DeleteShader(fs)
	if ok == 0 {
		buf: [4096]u8
		n: i32
		gl.GetProgramInfoLog(r.program, len(buf), &n, &buf[0])
		fmt.eprintln("vui_gl: program link error:", string(buf[:n]))
		return false
	}
	r.u_viewport = gl.GetUniformLocation(r.program, "u_viewport")
	r.u_atlas = gl.GetUniformLocation(r.program, "u_atlas")
	r.u_image = gl.GetUniformLocation(r.program, "u_image")
	r.u_atlas_size = gl.GetUniformLocation(r.program, "u_atlas_size")
	r.u_filters = gl.GetUniformLocation(r.program, "u_filters")
	r.u_filter_off = gl.GetUniformLocation(r.program, "u_filter_off")
	r.u_text_gamma = gl.GetUniformLocation(r.program, "u_text_gamma")
	r.u_text_contrast = gl.GetUniformLocation(r.program, "u_text_contrast")
	r.u_grade = gl.GetUniformLocation(r.program, "u_grade")
	r.u_grade_tint = gl.GetUniformLocation(r.program, "u_grade_tint")

	gl.GenVertexArrays(1, &r.vao)
	gl.BindVertexArray(r.vao)
	gl.GenBuffers(1, &r.vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	r.vbo_cap = 4096
	gl.BufferData(gl.ARRAY_BUFFER, r.vbo_cap * size_of(vui.Draw_Cmd), nil, gl.STREAM_DRAW)
	stride := i32(size_of(vui.Draw_Cmd))
	for i in 0 ..< 15 {
		gl.EnableVertexAttribArray(u32(i))
		gl.VertexAttribPointer(u32(i), 4, gl.FLOAT, false, stride, uintptr(i * 16))
		gl.VertexAttribDivisor(u32(i), 1)
	}

	white := [4]u8{255, 255, 255, 255}
	gl.GenTextures(1, &r.white_tex)
	gl.BindTexture(gl.TEXTURE_2D, r.white_tex)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &white[0])
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	return true
}

destroy :: proc(r: ^Renderer, ctx: ^vui.Context = nil) {
	if r.program == 0 {
		return
	}
	if ctx != nil {
		for &img in ctx.images {
			if img.handle != 0 && !img.external {
				tex := u32(img.handle)
				gl.DeleteTextures(1, &tex)
				img.handle = 0
			}
		}
	}
	gl.DeleteProgram(r.program)
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteVertexArrays(1, &r.vao)
	if r.atlas_tex != 0 {
		gl.DeleteTextures(1, &r.atlas_tex)
	}
	gl.DeleteTextures(1, &r.white_tex)
	r.program = 0
	if r.lib != nil {
		dynlib.unload_library(r.lib)
		r.lib = nil
	}
}

@(private)
sync_atlas :: proc(r: ^Renderer, a: ^vui.Atlas) {
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	if r.atlas_tex == 0 || r.atlas_gen != a.generation || r.atlas_w != a.w || r.atlas_h != a.h {
		if r.atlas_tex == 0 {
			gl.GenTextures(1, &r.atlas_tex)
		}
		gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R8, i32(a.w), i32(a.h), 0, gl.RED, gl.UNSIGNED_BYTE, raw_data(a.pixels))
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		r.atlas_gen = a.generation
		r.atlas_w = a.w
		r.atlas_h = a.h
		a.dirty = false
		return
	}
	if a.dirty {
		gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
		y0 := clamp(a.dirty_y0, 0, a.h)
		y1 := clamp(a.dirty_y1, 0, a.h)
		if y1 > y0 {
			gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, i32(y0), i32(a.w), i32(y1 - y0), gl.RED, gl.UNSIGNED_BYTE, &a.pixels[y0 * a.w])
		}
		a.dirty = false
	}
}

@(private)
sync_images :: proc(ctx: ^vui.Context) {
	for &img in ctx.images {
		if !img.dirty || img.freed || img.external {
			continue
		}
		img.dirty = false
		if img.w <= 0 || img.h <= 0 || len(img.pixels) < img.w * img.h * 4 {
			continue
		}
		tex := u32(img.handle)
		if tex == 0 {
			gl.GenTextures(1, &tex)
			img.handle = u64(tex)
		}
		gl.BindTexture(gl.TEXTURE_2D, tex)
		gl.PixelStorei(gl.UNPACK_ALIGNMENT, 4)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(img.w), i32(img.h), 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(img.pixels))
		gl.GenerateMipmap(gl.TEXTURE_2D)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	}
}

@(private)
Saved_State :: struct {
	program, vao, array_buf, active_tex: i32,
	tex0, tex1:                          i32,
	viewport:                            [4]i32,
	blend, depth, cull, scissor:         bool,
	src_rgb, dst_rgb, src_a, dst_a:      i32,
}

@(private)
save_state :: proc() -> (s: Saved_State) {
	gl.GetIntegerv(gl.CURRENT_PROGRAM, &s.program)
	gl.GetIntegerv(gl.VERTEX_ARRAY_BINDING, &s.vao)
	gl.GetIntegerv(gl.ARRAY_BUFFER_BINDING, &s.array_buf)
	gl.GetIntegerv(gl.ACTIVE_TEXTURE, &s.active_tex)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.GetIntegerv(gl.TEXTURE_BINDING_2D, &s.tex0)
	gl.ActiveTexture(gl.TEXTURE1)
	gl.GetIntegerv(gl.TEXTURE_BINDING_2D, &s.tex1)
	gl.GetIntegerv(gl.VIEWPORT, &s.viewport[0])
	s.blend = gl.IsEnabled(gl.BLEND)
	s.depth = gl.IsEnabled(gl.DEPTH_TEST)
	s.cull = gl.IsEnabled(gl.CULL_FACE)
	s.scissor = gl.IsEnabled(gl.SCISSOR_TEST)
	gl.GetIntegerv(gl.BLEND_SRC_RGB, &s.src_rgb)
	gl.GetIntegerv(gl.BLEND_DST_RGB, &s.dst_rgb)
	gl.GetIntegerv(gl.BLEND_SRC_ALPHA, &s.src_a)
	gl.GetIntegerv(gl.BLEND_DST_ALPHA, &s.dst_a)
	return
}

@(private)
set_cap :: proc(cap: u32, on: bool) {
	if on {
		gl.Enable(cap)
	} else {
		gl.Disable(cap)
	}
}

@(private)
restore_state :: proc(s: Saved_State) {
	gl.UseProgram(u32(s.program))
	gl.BindVertexArray(u32(s.vao))
	gl.BindBuffer(gl.ARRAY_BUFFER, u32(s.array_buf))
	gl.ActiveTexture(gl.TEXTURE1)
	gl.BindTexture(gl.TEXTURE_2D, u32(s.tex1))
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, u32(s.tex0))
	gl.ActiveTexture(u32(s.active_tex))
	gl.Viewport(s.viewport[0], s.viewport[1], s.viewport[2], s.viewport[3])
	set_cap(gl.BLEND, s.blend)
	set_cap(gl.DEPTH_TEST, s.depth)
	set_cap(gl.CULL_FACE, s.cull)
	set_cap(gl.SCISSOR_TEST, s.scissor)
	gl.BlendFuncSeparate(u32(s.src_rgb), u32(s.dst_rgb), u32(s.src_a), u32(s.dst_a))
}

// Draws the frame's UI over whatever is in the bound framebuffer (fb_w x fb_h physical px).
// The host must flush its own batched geometry first (raylib: rlgl.DrawRenderBatchActive()).
render :: proc(r: ^Renderer, ctx: ^vui.Context, d: ^vui.Draw_List, fb_w, fb_h: i32) {
	if fb_w <= 0 || fb_h <= 0 || r.program == 0 {
		return
	}
	saved := save_state()
	defer restore_state(saved)

	sync_atlas(r, &ctx.atlas)
	sync_images(ctx)

	gl.Viewport(0, 0, fb_w, fb_h)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.SCISSOR_TEST)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(r.program)
	gl.Uniform2f(r.u_viewport, f32(fb_w), f32(fb_h))
	gl.Uniform2f(r.u_atlas_size, f32(ctx.atlas.w), f32(ctx.atlas.h))
	gl.Uniform1i(r.u_atlas, 0)
	gl.Uniform1i(r.u_image, 1)
	gl.Uniform1f(r.u_text_gamma, ctx.text_gamma > 0 ? ctx.text_gamma : 1)
	gl.Uniform1f(r.u_text_contrast, 1)
	gr, gt := vui.grade_uniforms(ctx.grade, ctx.scale)
	gl.Uniform4f(r.u_grade, gr[0], gr[1], gr[2], gr[3])
	gl.Uniform4f(r.u_grade_tint, gt[0], gt[1], gt[2], gt[3])
	mats: [MAX_FILTERS]matrix[4, 4]f32
	offs: [MAX_FILTERS][4]f32
	for i in 0 ..< min(len(d.filters), MAX_FILTERS) {
		mats[i] = d.filters[i].m
		offs[i] = d.filters[i].o
	}
	gl.UniformMatrix4fv(r.u_filters, MAX_FILTERS, false, &mats[0][0, 0])
	gl.Uniform4fv(r.u_filter_off, MAX_FILTERS, &offs[0][0])

	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	n := min(len(d.cmds), vui.MAX_DRAW_CMDS)
	if n > r.vbo_cap {
		r.vbo_cap = clamp(n + n / 2, 4096, vui.MAX_DRAW_CMDS)
	}
	gl.BufferData(gl.ARRAY_BUFFER, r.vbo_cap * size_of(vui.Draw_Cmd), nil, gl.STREAM_DRAW) // orphan
	if n > 0 {
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, n * size_of(vui.Draw_Cmd), raw_data(d.cmds))
	}
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
	batches := 0
	stride := i32(size_of(vui.Draw_Cmd))
	for b in d.batches {
		if b.count <= 0 || int(b.first) >= n {
			continue
		}
		count := i32(min(int(b.count), n - int(b.first)))
		gl.ActiveTexture(gl.TEXTURE1)
		tex := r.white_tex
		if b.image != 0 && int(b.image) <= len(ctx.images) && ctx.images[b.image - 1].handle != 0 {
			tex = u32(ctx.images[b.image - 1].handle)
		}
		gl.BindTexture(gl.TEXTURE_2D, tex)
		base := uintptr(int(b.first) * size_of(vui.Draw_Cmd))
		for i in 0 ..< 15 {
			gl.VertexAttribPointer(u32(i), 4, gl.FLOAT, false, stride, base + uintptr(i * 16))
		}
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count)
		batches += 1
	}
	r.last_cmds = n
	r.last_batches = batches
}

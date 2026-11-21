package vui_app

import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import vui ".."

// OpenGL 3.3 renderer for vui draw lists. Everything is one instanced quad per command
// drawn by an uber-shader; rendering goes to an offscreen framebuffer so screenshots
// read exactly what is shown (and hidden windows still render).

MAX_FILTERS :: vui.MAX_DRAW_FILTERS

Renderer :: struct {
	program:     u32,
	vao:         u32,
	vbo:         u32,
	vbo_cap:     int,
	atlas_tex:   u32,
	atlas_gen:   u32,
	atlas_w:     int,
	atlas_h:     int,
	fbo:         u32,
	fbo_tex:     u32,
	fbo_size:    [2]i32,
	u_viewport:  i32,
	u_atlas:     i32,
	u_image:     i32,
	u_atlas_size: i32,
	u_filters:   i32,
	u_filter_off: i32,
	u_text_gamma: i32,
	u_text_contrast: i32,
	white_tex:   u32,
	// fence of the previous frame: at most one frame in flight (mirrors the GPU backend),
	// so orphaned instance buffers cannot pile up when nothing (no swap) throttles us
	frame_fence: gl.sync_t,
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
` + #load("shaders/ui_vs_body.glsl", string)

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
out vec4 o_color;

` + #load("shaders/ui_fs_body.glsl", string)

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
		fmt.eprintln("vui: shader compile error:", string(buf[:n]))
		return 0, false
	}
	return sh, true
}

renderer_init :: proc(r: ^Renderer) -> bool {
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
	if ok == 0 {
		buf: [4096]u8
		n: i32
		gl.GetProgramInfoLog(r.program, len(buf), &n, &buf[0])
		fmt.eprintln("vui: program link error:", string(buf[:n]))
		return false
	}
	gl.DeleteShader(vs)
	gl.DeleteShader(fs)
	r.u_viewport = gl.GetUniformLocation(r.program, "u_viewport")
	r.u_atlas = gl.GetUniformLocation(r.program, "u_atlas")
	r.u_image = gl.GetUniformLocation(r.program, "u_image")
	r.u_atlas_size = gl.GetUniformLocation(r.program, "u_atlas_size")
	r.u_filters = gl.GetUniformLocation(r.program, "u_filters")
	r.u_filter_off = gl.GetUniformLocation(r.program, "u_filter_off")
	r.u_text_gamma = gl.GetUniformLocation(r.program, "u_text_gamma")
	r.u_text_contrast = gl.GetUniformLocation(r.program, "u_text_contrast")

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
	gl.BindVertexArray(0)

	white := [4]u8{255, 255, 255, 255}
	gl.GenTextures(1, &r.white_tex)
	gl.BindTexture(gl.TEXTURE_2D, r.white_tex)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &white[0])
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	return true
}

@(private)
gl_wait_frame :: proc(r: ^Renderer) {
	if r.frame_fence == nil {
		return
	}
	res := gl.ClientWaitSync(r.frame_fence, gl.SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000)
	if res == gl.TIMEOUT_EXPIRED || res == gl.WAIT_FAILED {
		gl.Finish()
	}
	gl.DeleteSync(r.frame_fence)
	r.frame_fence = nil
}

renderer_destroy :: proc(r: ^Renderer) {
	gl_wait_frame(r)
	gl.DeleteProgram(r.program)
	gl.DeleteBuffers(1, &r.vbo)
	gl.DeleteVertexArrays(1, &r.vao)
	if r.atlas_tex != 0 {
		gl.DeleteTextures(1, &r.atlas_tex)
	}
	if r.fbo != 0 {
		gl.DeleteFramebuffers(1, &r.fbo)
		gl.DeleteTextures(1, &r.fbo_tex)
	}
	gl.DeleteTextures(1, &r.white_tex)
}

@(private)
sync_atlas :: proc(r: ^Renderer, a: ^vui.Atlas) {
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	if r.atlas_tex != 0 && r.atlas_gen != a.generation && r.atlas_w == a.w && r.atlas_h == a.h {
		// cleared (same size): refill the existing storage instead of re-allocating it
		gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
		gl.TexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, i32(a.w), i32(a.h), gl.RED, gl.UNSIGNED_BYTE, raw_data(a.pixels))
		r.atlas_gen = a.generation
		a.dirty = false
		return
	}
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
		if !img.dirty || img.freed {
			continue
		}
		img.dirty = false // upload once; invalid images are skipped, not retried
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
ensure_fbo :: proc(r: ^Renderer, w, h: i32) {
	if r.fbo != 0 && r.fbo_size == {w, h} {
		return
	}
	if r.fbo == 0 {
		gl.GenFramebuffers(1, &r.fbo)
		gl.GenTextures(1, &r.fbo_tex)
	}
	gl.BindTexture(gl.TEXTURE_2D, r.fbo_tex)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.BindFramebuffer(gl.FRAMEBUFFER, r.fbo)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, r.fbo_tex, 0)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	r.fbo_size = {w, h}
}

// Renders the draw list into the offscreen target and blits it to the window.
render :: proc(r: ^Renderer, ctx: ^vui.Context, d: ^vui.Draw_List, fb_w, fb_h: i32, clear_color: vui.Color) {
	if fb_w <= 0 || fb_h <= 0 {
		return
	}
	gl_wait_frame(r)
	ensure_fbo(r, fb_w, fb_h)
	sync_atlas(r, &ctx.atlas)
	sync_images(ctx)

	gl.BindFramebuffer(gl.FRAMEBUFFER, r.fbo)
	gl.Viewport(0, 0, fb_w, fb_h)
	cc := clear_color
	gl.ClearColor(cc.r * cc.a, cc.g * cc.a, cc.b * cc.a, cc.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)

	gl.UseProgram(r.program)
	gl.Uniform2f(r.u_viewport, f32(fb_w), f32(fb_h))
	gl.Uniform2f(r.u_atlas_size, f32(ctx.atlas.w), f32(ctx.atlas.h))
	gl.Uniform1i(r.u_atlas, 0)
	gl.Uniform1i(r.u_image, 1)
	gl.Uniform1f(r.u_text_gamma, ctx.text_gamma > 0 ? ctx.text_gamma : 1)
	gl.Uniform1f(r.u_text_contrast, 1)
	// filters
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
	gl.BufferData(gl.ARRAY_BUFFER, r.vbo_cap * size_of(vui.Draw_Cmd), nil, gl.STREAM_DRAW)
	if n > 0 {
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, n * size_of(vui.Draw_Cmd), raw_data(d.cmds))
	}
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
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
		// attribute offsets for this batch
		stride := i32(size_of(vui.Draw_Cmd))
		base := uintptr(int(b.first) * size_of(vui.Draw_Cmd))
		for i in 0 ..< 15 {
			gl.VertexAttribPointer(u32(i), 4, gl.FLOAT, false, stride, base + uintptr(i * 16))
		}
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count)
	}
	gl.BindVertexArray(0)

	// present
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, r.fbo)
	gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
	gl.BlitFramebuffer(0, 0, fb_w, fb_h, 0, 0, fb_w, fb_h, gl.COLOR_BUFFER_BIT, gl.NEAREST)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	r.frame_fence = gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
}

// Reads the last rendered frame (RGBA8, top-down rows).
read_pixels :: proc(r: ^Renderer, allocator := context.allocator) -> (pixels: []u8, w, h: i32) {
	w = r.fbo_size.x
	h = r.fbo_size.y
	if w <= 0 || h <= 0 {
		return
	}
	buf := make([]u8, int(w) * int(h) * 4, context.temp_allocator)
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, r.fbo)
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(buf))
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, 0)
	pixels = make([]u8, int(w) * int(h) * 4, allocator)
	row := int(w * 4)
	for y in 0 ..< int(h) {
		copy(pixels[y * row:(y + 1) * row], buf[(int(h) - 1 - y) * row:(int(h) - y) * row])
	}
	// un-premultiply for PNG
	for i := 0; i < len(pixels); i += 4 {
		a := pixels[i + 3]
		if a > 0 && a < 255 {
			for c in 0 ..< 3 {
				pixels[i + c] = u8(min(255, int(pixels[i + c]) * 255 / int(a)))
			}
		}
	}
	return
}

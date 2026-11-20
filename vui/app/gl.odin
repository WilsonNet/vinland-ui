package vui_app

import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"
import vui ".."

// OpenGL 3.3 renderer for vui draw lists. Everything is one instanced quad per command
// drawn by an uber-shader; rendering goes to an offscreen framebuffer so screenshots
// read exactly what is shown (and hidden windows still render).

MAX_FILTERS :: 16

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
void main() {
	int kind = int(a_params.x);
	vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
	float pad = 1.0;
	if (kind == 1) pad = 3.0 * a_params.y + 2.0;
	if (kind == 3 || kind == 4) pad = 0.0;
	vec2 local = mix(vec2(-pad), a_size.xy + vec2(pad), corner);
	mat2 m = mat2(a_xf.x, a_xf.z, a_xf.y, a_xf.w);
	vec2 world = m * local + a_xt.xy;
	v_local = local;
	v_world = world;
	f_size = a_size; f_radii = a_radii; f_fill0 = a_fill0; f_fill1 = a_fill1; f_fill2 = a_fill2;
	f_bw = a_bw; f_bc = a_bc; f_grad = a_grad; f_params = a_params; f_uv = a_uv;
	f_clip = a_clip; f_clipr = a_clipr; f_xt = a_xt; f_extra = a_extra;
	gl_Position = vec4(world.x / u_viewport.x * 2.0 - 1.0, 1.0 - world.y / u_viewport.y * 2.0, 0.0, 1.0);
}
`

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

float sd_rrect(vec2 p, vec2 hs, vec4 r) {
	float rad = p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
	rad = min(rad, min(hs.x, hs.y));
	vec2 q = abs(p) - hs + rad;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

vec4 pm(vec4 c) { return vec4(c.rgb * c.a, c.a); }

vec2 erf2(vec2 x) {
	vec2 s = sign(x), a = abs(x);
	x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
	x *= x;
	return s - s / (x * x);
}
float gaussian(float x, float sigma) {
	const float pi = 3.141592653589793;
	return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * pi) * sigma);
}
float shadow_x(float x, float y, float sigma, float corner, vec2 hs) {
	float delta = min(hs.y - corner - abs(y), 0.0);
	float curved = hs.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
	vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-curved, curved)) * (sqrt(0.5) / sigma));
	return integral.y - integral.x;
}
float box_shadow(vec2 lower, vec2 upper, vec2 point, float sigma, float corner) {
	vec2 center = (lower + upper) * 0.5;
	vec2 hs = (upper - lower) * 0.5;
	point -= center;
	corner = min(corner, min(hs.x, hs.y));
	float low = point.y - hs.y;
	float high = point.y + hs.y;
	float start = clamp(-3.0 * sigma, low, high);
	float end = clamp(3.0 * sigma, low, high);
	float step = (end - start) / 4.0;
	float y = start + step * 0.5;
	float value = 0.0;
	for (int i = 0; i < 4; i++) {
		value += shadow_x(point.x, point.y - y, sigma, corner, hs) * gaussian(y, sigma) * step;
		y += step;
	}
	return value;
}

vec4 fill_color(vec2 p, vec2 size) {
	int gk = int(f_grad.x);
	vec4 c0 = pm(f_fill0);
	if (gk == 0) return c0;
	if (gk == 4) {
		float period = max(f_xt.w, 1.0) * 1.41421356;
		float s = v_world.x + v_world.y;
		float t = mod(s, period);
		float d = min(t, period - t) / 1.41421356;
		float c = clamp(f_extra.x * 0.5 - d + 0.5, 0.0, 1.0);
		vec4 line = pm(f_fill1) * c;
		return line + c0 * (1.0 - line.a);
	}
	vec2 hs = size * 0.5;
	float t;
	if (gk == 1) {
		float a = f_grad.y;
		vec2 dir = vec2(sin(a), -cos(a));
		float len = abs(size.x * dir.x) + abs(size.y * dir.y);
		t = dot(p, dir) / max(len, 1e-4) + 0.5;
	} else if (gk == 2) {
		t = length(p / max(hs * 1.41421356, vec2(1e-4)));
	} else {
		float ang = atan(p.x, -p.y) - f_grad.y;
		t = fract(ang / 6.28318530718);
	}
	float s0 = f_grad.z;
	float s1 = f_grad.w;
	float sv = f_params.w;
	vec4 b = pm(f_fill1);
	if (sv >= 0.0) {
		vec4 v = pm(f_fill2);
		if (t < sv) return mix(c0, v, clamp((t - s0) / max(sv - s0, 1e-4), 0.0, 1.0));
		return mix(v, b, clamp((t - sv) / max(s1 - sv, 1e-4), 0.0, 1.0));
	}
	return mix(c0, b, clamp((t - s0) / max(s1 - s0, 1e-4), 0.0, 1.0));
}

float dash_mask(vec2 lp, vec2 size, vec4 bw, int style, float dout) {
	// pick the side this fragment belongs to
	float dt = bw.x > 0.0 ? lp.y / bw.x : 1e9;
	float db = bw.z > 0.0 ? (size.y - lp.y) / bw.z : 1e9;
	float dl = bw.w > 0.0 ? lp.x / bw.w : 1e9;
	float dr = bw.y > 0.0 ? (size.x - lp.x) / bw.y : 1e9;
	float along; float w;
	float m = min(min(dt, db), min(dl, dr));
	if (m == dt) { along = lp.x; w = bw.x; }
	else if (m == db) { along = lp.x; w = bw.z; }
	else if (m == dl) { along = lp.y; w = bw.w; }
	else { along = lp.y; w = bw.y; }
	if (style == 3) {
		float f = dout / w;
		return (f < 0.34 || f > 0.66) ? 1.0 : 0.0;
	}
	if (style == 1) {
		float period = w * 5.0;
		float t = mod(along, period);
		return clamp(min(t, w * 3.0 - t) + 0.5, 0.0, 1.0);
	}
	float period = w * 2.0;
	float t = mod(along, period) - w * 0.5;
	float across = dout - w * 0.5;
	return clamp(w * 0.5 - length(vec2(t, across)) + 0.5, 0.0, 1.0);
}

void main() {
	int kind = int(f_params.x);
	vec2 size = f_size.xy;
	vec2 hs = size * 0.5;
	vec2 p = v_local - hs;
	float k = max(length(vec2(dFdx(v_local.x), dFdy(v_local.x))), 1e-4);
	vec4 col = vec4(0.0);
	if (kind == 0) {
		float d = sd_rrect(p, hs, f_radii) / k;
		float outer = clamp(0.5 - d, 0.0, 1.0);
		if (outer <= 0.0) discard;
		vec4 fill = fill_color(p, size);
		col = fill * outer;
		vec4 bw = f_bw;
		if (bw.x + bw.y + bw.z + bw.w > 0.0) {
			vec2 imin = vec2(bw.w, bw.x);
			vec2 imax = size - vec2(bw.y, bw.z);
			vec2 ihs = max((imax - imin) * 0.5, vec2(0.0));
			vec2 ic = (imin + imax) * 0.5;
			vec4 ir = max(f_radii - vec4(max(bw.w, bw.x), max(bw.y, bw.x), max(bw.y, bw.z), max(bw.w, bw.z)), 0.0);
			float di = sd_rrect(v_local - ic, ihs, ir) / k;
			float inner = (ihs.x <= 0.0 || ihs.y <= 0.0) ? 0.0 : clamp(0.5 - di, 0.0, 1.0);
			float bcov = clamp(outer - inner, 0.0, 1.0);
			int style = int(f_params.z);
			if (style != 0 && bcov > 0.0) bcov *= dash_mask(v_local, size, bw, style, -d);
			vec4 bc = pm(f_bc) * bcov;
			col = bc + col * (1.0 - bc.a);
		}
	} else if (kind == 1) {
		float sigma = f_params.y;
		float a;
		if (sigma < 0.5) {
			a = clamp(0.5 - sd_rrect(p, hs, f_radii) / k, 0.0, 1.0);
		} else {
			float corner = p.x < 0.0 ? (p.y < 0.0 ? f_radii.x : f_radii.w) : (p.y < 0.0 ? f_radii.y : f_radii.z);
			a = box_shadow(vec2(0.0), size, v_local, sigma, corner);
		}
		col = pm(f_fill0) * a;
	} else if (kind == 2) {
		float outer = clamp(0.5 - sd_rrect(p, hs, f_radii) / k, 0.0, 1.0);
		if (outer <= 0.0) discard;
		vec4 hole = f_fill1;
		vec2 hsz = hole.zw;
		float sigma = f_params.y;
		float h;
		if (hsz.x <= 0.0 || hsz.y <= 0.0) {
			h = 0.0;
		} else if (sigma < 0.5) {
			h = clamp(0.5 - sd_rrect(v_local - (hole.xy + hsz * 0.5), hsz * 0.5, f_fill2) / k, 0.0, 1.0);
		} else {
			vec2 hp = v_local - (hole.xy + hsz * 0.5);
			float corner = hp.x < 0.0 ? (hp.y < 0.0 ? f_fill2.x : f_fill2.w) : (hp.y < 0.0 ? f_fill2.y : f_fill2.z);
			h = box_shadow(hole.xy, hole.xy + hsz, v_local, sigma, corner);
		}
		col = pm(f_fill0) * outer * (1.0 - h);
	} else if (kind == 3) {
		vec2 tc = (f_uv.xy + v_local / max(size, vec2(1e-4)) * f_uv.zw) / u_atlas_size;
		float a = texture(u_atlas, tc).r;
		// perceptual tuning: gamma on coverage, mild contrast for small sizes
		a = pow(a, u_text_gamma);
		a = clamp((a - 0.5) * u_text_contrast + 0.5, 0.0, 1.0) * step(0.0001, a) + 0.0;
		col = pm(f_fill0) * a;
	} else {
		vec2 tc = f_uv.xy + v_local / max(size, vec2(1e-4)) * f_uv.zw;
		vec4 t = texture(u_image, tc);
		col = vec4(t.rgb * t.a, t.a) * f_fill0.a;
	}
	// clip (world space)
	vec2 w = v_world;
	if (w.x < f_clip.x || w.y < f_clip.y || w.x >= f_clip.z || w.y >= f_clip.w) discard;
	if (f_clipr.x + f_clipr.y + f_clipr.z + f_clipr.w > 0.0) {
		vec2 cs = f_clip.zw - f_clip.xy;
		float dc = sd_rrect(w - (f_clip.xy + cs * 0.5), cs * 0.5, f_clipr);
		col *= clamp(0.5 - dc, 0.0, 1.0);
	}
	int fi = int(f_xt.z);
	if (fi > 0 && col.a > 0.0) {
		vec4 c = vec4(col.rgb / col.a, col.a);
		c = u_filters[fi] * c + u_filter_off[fi];
		c = clamp(c, 0.0, 1.0);
		col = vec4(c.rgb * c.a, c.a);
	}
	o_color = col;
}
`

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

renderer_destroy :: proc(r: ^Renderer) {
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
		img.dirty = false
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
	n := len(d.cmds)
	if n > r.vbo_cap {
		for r.vbo_cap < n {
			r.vbo_cap *= 2
		}
	}
	gl.BufferData(gl.ARRAY_BUFFER, r.vbo_cap * size_of(vui.Draw_Cmd), nil, gl.STREAM_DRAW)
	if n > 0 {
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, n * size_of(vui.Draw_Cmd), raw_data(d.cmds))
	}
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, r.atlas_tex)
	for b in d.batches {
		gl.ActiveTexture(gl.TEXTURE1)
		tex := r.white_tex
		if b.image != 0 && int(b.image) <= len(ctx.images) {
			tex = u32(ctx.images[b.image - 1].handle)
		}
		gl.BindTexture(gl.TEXTURE_2D, tex)
		// attribute offsets for this batch
		stride := i32(size_of(vui.Draw_Cmd))
		base := uintptr(int(b.first) * size_of(vui.Draw_Cmd))
		for i in 0 ..< 15 {
			gl.VertexAttribPointer(u32(i), 4, gl.FLOAT, false, stride, base + uintptr(i * 16))
		}
		gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, b.count)
	}
	gl.BindVertexArray(0)

	// present
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, r.fbo)
	gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
	gl.BlitFramebuffer(0, 0, fb_w, fb_h, 0, 0, fb_w, fb_h, gl.COLOR_BUFFER_BIT, gl.NEAREST)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

// Reads the last rendered frame (RGBA8, top-down rows).
read_pixels :: proc(r: ^Renderer, allocator := context.allocator) -> (pixels: []u8, w, h: i32) {
	w = r.fbo_size.x
	h = r.fbo_size.y
	if w <= 0 || h <= 0 {
		return
	}
	buf := make([]u8, int(w * h * 4), context.temp_allocator)
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, r.fbo)
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(buf))
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, 0)
	pixels = make([]u8, int(w * h * 4), allocator)
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

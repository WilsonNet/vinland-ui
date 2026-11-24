#include <metal_stdlib>
using namespace metal;

struct VertIn {
	float4 a_size   [[attribute(0)]];
	float4 a_radii  [[attribute(1)]];
	float4 a_fill0  [[attribute(2)]];
	float4 a_fill1  [[attribute(3)]];
	float4 a_fill2  [[attribute(4)]];
	float4 a_bw     [[attribute(5)]];
	float4 a_bc     [[attribute(6)]];
	float4 a_grad   [[attribute(7)]];
	float4 a_params [[attribute(8)]];
	float4 a_uv     [[attribute(9)]];
	float4 a_clip   [[attribute(10)]];
	float4 a_clipr  [[attribute(11)]];
	float4 a_xf     [[attribute(12)]];
	float4 a_xt     [[attribute(13)]];
	float4 a_extra  [[attribute(14)]];
};

struct VertexUniforms {
	float2 u_viewport;
	float2 _pad;
};

struct FragIn {
	float4 pos      [[position]];
	float2 v_local;
	float2 v_world;
	float4 f_size   [[flat]];
	float4 f_radii  [[flat]];
	float4 f_fill0  [[flat]];
	float4 f_fill1  [[flat]];
	float4 f_fill2  [[flat]];
	float4 f_bw     [[flat]];
	float4 f_bc     [[flat]];
	float4 f_grad   [[flat]];
	float4 f_params [[flat]];
	float4 f_uv     [[flat]];
	float4 f_clip   [[flat]];
	float4 f_clipr  [[flat]];
	float4 f_xt     [[flat]];
	float4 f_extra  [[flat]];
};

struct FragmentUniforms {
	float4x4 u_filters[16];
	float4   u_filter_off[16];
	float2   u_atlas_size;
	float    u_text_gamma;
	float    u_text_contrast;
	float4   u_grade;
	float4   u_grade_tint;
};

vertex FragIn vs_main(
	VertIn in [[stage_in]],
	uint vid [[vertex_id]],
	constant VertexUniforms& vu [[buffer(0)]]
) {
	int kind = int(in.a_params.x);
	float2 corner = float2(float(vid & 1u), float((vid >> 1u) & 1u));
	float pad = 1.0f;
	if (kind == 1) pad = 3.0f * in.a_params.y + 2.0f;
	if (kind == 3 || kind == 4 || kind == 7) pad = 0.0f;
	float2 local = mix(float2(-pad), in.a_size.xy + float2(pad), corner);
	float2 world = float2(
		in.a_xf.x * local.x + in.a_xf.y * local.y,
		in.a_xf.z * local.x + in.a_xf.w * local.y
	) + in.a_xt.xy;

	FragIn out;
	out.v_local = local;
	out.v_world = world;
	out.f_size = in.a_size;
	out.f_radii = in.a_radii;
	out.f_fill0 = in.a_fill0;
	out.f_fill1 = in.a_fill1;
	out.f_fill2 = in.a_fill2;
	out.f_bw = in.a_bw;
	out.f_bc = in.a_bc;
	out.f_grad = in.a_grad;
	out.f_params = in.a_params;
	out.f_uv = in.a_uv;
	out.f_clip = in.a_clip;
	out.f_clipr = in.a_clipr;
	out.f_xt = in.a_xt;
	out.f_extra = in.a_extra;
	out.pos = float4(
		world.x / vu.u_viewport.x * 2.0f - 1.0f,
		1.0f - world.y / vu.u_viewport.y * 2.0f,
		0.0f,
		1.0f
	);
	return out;
}

static inline float glsl_mod(float x, float y) {
	return x - y * floor(x / y);
}

static inline float sd_rrect(float2 p, float2 hs, float4 r) {
	float rad = p.x < 0.0f ? (p.y < 0.0f ? r.x : r.w) : (p.y < 0.0f ? r.y : r.z);
	rad = min(rad, min(hs.x, hs.y));
	float2 q = abs(p) - hs + rad;
	return min(max(q.x, q.y), 0.0f) + length(max(q, 0.0f)) - rad;
}

// Ornate corner shapes (keep in sync with ui_fs_body.glsl sd_shape).
static inline float sd_shape(float2 p, float2 hs, float4 r, int code) {
	if (code == 0) return sd_rrect(p, hs, r);
	int ci = p.x < 0.0f ? (p.y < 0.0f ? 0 : 3) : (p.y < 0.0f ? 1 : 2);
	int shape = (code >> (3 * ci)) & 7;
	float rad = ci == 0 ? r.x : (ci == 1 ? r.y : (ci == 2 ? r.z : r.w));
	if (shape == 0) return sd_rrect(p, hs, r);
	float2 q = abs(p) - hs;
	float box = min(max(q.x, q.y), 0.0f) + length(max(q, 0.0f));
	if (shape == 4) {
		float h = clamp(rad, 1e-3f, 2.0f * hs.y);
		float R = (h * h + hs.x * hs.x) / (2.0f * hs.x);
		float spring = hs.y - h;
		float2 a = abs(p);
		if (a.y <= spring) return box;
		return max(box, length(a - float2(hs.x - R, spring)) - R);
	}
	rad = min(rad, min(hs.x, hs.y));
	if (rad <= 0.0f) return box;
	if (shape == 1) return max(box, (q.x + q.y + rad) * 0.70710678f);
	if (shape == 2) return max(box, rad - length(q));
	return max(box, min(q.x + rad, q.y + rad));
}

// Colour grade (keep in sync with ui_fs_body.glsl grade()).
static inline float g_hash(float2 p) {
	p = fract(p * float2(123.34f, 456.21f));
	p += dot(p, p + 45.32f);
	return fract(p.x * p.y);
}
static inline float g_noise(float2 p) {
	float2 i = floor(p);
	float2 f = fract(p);
	f = f * f * (3.0f - 2.0f * f);
	float a = g_hash(i), b = g_hash(i + float2(1.0f, 0.0f));
	float c = g_hash(i + float2(0.0f, 1.0f)), d = g_hash(i + float2(1.0f, 1.0f));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
static inline float4 grade(float4 col, int kind, float2 world, constant FragmentUniforms& fu) {
	if (fu.u_grade_tint.w <= 0.0f || col.a <= 0.0f) return col;
	float3 rgb = col.rgb / col.a;
	float l = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
	rgb = mix(float3(l), rgb, fu.u_grade.x);
	rgb = (rgb - 0.5f) * fu.u_grade.y + 0.5f;
	rgb *= fu.u_grade_tint.rgb;
	if (kind != 3) {
		float2 q = world / fu.u_grade_tint.w;
		float m = g_noise(q) * 0.6f + g_noise(q * 2.7f + 17.0f) * 0.4f;
		float n = g_hash(floor(world)) - 0.5f;
		rgb *= 1.0f + fu.u_grade.w * (m - 0.5f) + fu.u_grade.z * n;
	}
	return float4(clamp(rgb, 0.0f, 1.0f) * col.a, col.a);
}

static inline float4 pm(float4 c) {
	return float4(c.rgb * c.a, c.a);
}

static inline float2 erf2(float2 x) {
	float2 s = sign(x);
	float2 a = abs(x);
	x = 1.0f + (0.278393f + (0.230389f + 0.078108f * (a * a)) * a) * a;
	x *= x;
	return s - s / (x * x);
}

static inline float gaussian(float x, float sigma) {
	constexpr float pi = 3.141592653589793f;
	return exp(-(x * x) / (2.0f * sigma * sigma)) / (sqrt(2.0f * pi) * sigma);
}

static inline float shadow_x(float x, float y, float sigma, float corner, float2 hs) {
	float delta = min(hs.y - corner - abs(y), 0.0f);
	float curved = hs.x - corner + sqrt(max(0.0f, corner * corner - delta * delta));
	float2 integral = 0.5f + 0.5f * erf2((x + float2(-curved, curved)) * (sqrt(0.5f) / sigma));
	return integral.y - integral.x;
}

static inline float box_shadow(float2 lower, float2 upper, float2 point, float sigma, float corner) {
	float2 center = (lower + upper) * 0.5f;
	float2 hs = (upper - lower) * 0.5f;
	point -= center;
	corner = min(corner, min(hs.x, hs.y));
	float low = point.y - hs.y;
	float high = point.y + hs.y;
	float start = clamp(-3.0f * sigma, low, high);
	float end = clamp(3.0f * sigma, low, high);
	float step_y = (end - start) / 4.0f;
	float y = start + step_y * 0.5f;
	float value = 0.0f;
	for (int i = 0; i < 4; i++) {
		value += shadow_x(point.x, point.y - y, sigma, corner, hs) * gaussian(y, sigma) * step_y;
		y += step_y;
	}
	return value;
}

static inline float4 fill_color(FragIn in, float2 p, float2 size) {
	int gk = int(in.f_grad.x);
	float4 c0 = pm(in.f_fill0);
	if (gk == 0) return c0;
	if (gk == 4) {
		float period = max(in.f_xt.w, 1.0f) * 1.41421356f;
		float s = in.v_world.x + in.v_world.y;
		float t = glsl_mod(s, period);
		float d = min(t, period - t) / 1.41421356f;
		float c = clamp(in.f_extra.x * 0.5f - d + 0.5f, 0.0f, 1.0f);
		float4 line = pm(in.f_fill1) * c;
		return line + c0 * (1.0f - line.a);
	}
	float2 hs = size * 0.5f;
	float t;
	if (gk == 1) {
		float a = in.f_grad.y;
		float2 dir = float2(sin(a), -cos(a));
		float len = abs(size.x * dir.x) + abs(size.y * dir.y);
		t = dot(p, dir) / max(len, 1e-4f) + 0.5f;
	} else if (gk == 2) {
		t = length(p / max(hs * 1.41421356f, float2(1e-4f)));
	} else {
		float ang = atan2(p.x, -p.y) - in.f_grad.y;
		t = fract(ang / 6.28318530718f);
	}
	float s0 = in.f_grad.z;
	float s1 = in.f_grad.w;
	float sv = in.f_params.w;
	float4 b = pm(in.f_fill1);
	if (sv >= 0.0f) {
		float4 v = pm(in.f_fill2);
		if (t < sv) return mix(c0, v, clamp((t - s0) / max(sv - s0, 1e-4f), 0.0f, 1.0f));
		return mix(v, b, clamp((t - sv) / max(s1 - sv, 1e-4f), 0.0f, 1.0f));
	}
	return mix(c0, b, clamp((t - s0) / max(s1 - s0, 1e-4f), 0.0f, 1.0f));
}

static inline float dash_mask(float2 lp, float2 size, float4 bw, int style, float dout) {
	float dt = bw.x > 0.0f ? lp.y / bw.x : 1e9f;
	float db = bw.z > 0.0f ? (size.y - lp.y) / bw.z : 1e9f;
	float dl = bw.w > 0.0f ? lp.x / bw.w : 1e9f;
	float dr = bw.y > 0.0f ? (size.x - lp.x) / bw.y : 1e9f;
	float along;
	float w;
	float m = min(min(dt, db), min(dl, dr));
	if (m == dt) { along = lp.x; w = bw.x; }
	else if (m == db) { along = lp.x; w = bw.z; }
	else if (m == dl) { along = lp.y; w = bw.w; }
	else { along = lp.y; w = bw.y; }
	if (style == 3) {
		float f = dout / w;
		return (f < 0.34f || f > 0.66f) ? 1.0f : 0.0f;
	}
	if (style == 1) {
		float period = w * 5.0f;
		float t = glsl_mod(along, period);
		return clamp(min(t, w * 3.0f - t) + 0.5f, 0.0f, 1.0f);
	}
	float period = w * 2.0f;
	float t = glsl_mod(along, period) - w * 0.5f;
	float across = dout - w * 0.5f;
	return clamp(w * 0.5f - length(float2(t, across)) + 0.5f, 0.0f, 1.0f);
}

fragment float4 fs_main(
	FragIn in [[stage_in]],
	constant FragmentUniforms& fu [[buffer(0)]],
	texture2d<float> u_atlas [[texture(0)]],
	sampler s_atlas [[sampler(0)]],
	texture2d<float> u_image [[texture(1)]],
	sampler s_image [[sampler(1)]]
) {
	int kind = int(in.f_params.x);
	float2 size = in.f_size.xy;
	float2 hs = size * 0.5f;
	float2 p = in.v_local - hs;
	float k = max(length(float2(dfdx(in.v_local.x), dfdy(in.v_local.x))), 1e-4f);
	float4 col = float4(0.0f);

	int shape = int(in.f_extra.y);
	if (kind == 0) {
		float d = sd_shape(p, hs, in.f_radii, shape) / k;
		float outer = clamp(0.5f - d, 0.0f, 1.0f);
		if (outer <= 0.0f) {
			discard_fragment();
			return float4(0.0f);
		}
		float4 fill = fill_color(in, p, size);
		if (in.f_extra.z != 0.0f) {
			float2 t = in.f_extra.z > 0.0f ? (in.v_local + in.f_extra.ww) / in.f_extra.z : in.v_local / max(size, float2(1e-4f));
			float2 tc = in.f_uv.xy + fract(t) * in.f_uv.zw;
			float4 sm = u_image.sample(s_image, tc, gradient2d(dfdx(t) * in.f_uv.zw, dfdy(t) * in.f_uv.zw));
			fill = fill * float4(sm.rgb * sm.a, sm.a);
		}
		col = fill * outer;
		float4 bw = in.f_bw;
		if (bw.x + bw.y + bw.z + bw.w > 0.0f) {
			float2 imin = float2(bw.w, bw.x);
			float2 imax = size - float2(bw.y, bw.z);
			float2 ihs = max((imax - imin) * 0.5f, float2(0.0f));
			float2 ic = (imin + imax) * 0.5f;
			float4 ir = max(in.f_radii - float4(max(bw.w, bw.x), max(bw.y, bw.x), max(bw.y, bw.z), max(bw.w, bw.z)), 0.0f);
			float di = shape == 0 ? sd_rrect(in.v_local - ic, ihs, ir) / k : d + max(max(bw.x, bw.y), max(bw.z, bw.w)) / k;
			float inner = (ihs.x <= 0.0f || ihs.y <= 0.0f) ? 0.0f : clamp(0.5f - di, 0.0f, 1.0f);
			float bcov = clamp(outer - inner, 0.0f, 1.0f);
			int style = int(in.f_params.z);
			if (style != 0 && bcov > 0.0f) bcov *= dash_mask(in.v_local, size, bw, style, -d);
			float4 bc = pm(in.f_bc) * bcov;
			col = bc + col * (1.0f - bc.a);
		}
	} else if (kind == 1) {
		float sigma = in.f_params.y;
		float a;
		if (sigma < 0.5f) {
			a = clamp(0.5f - sd_shape(p, hs, in.f_radii, shape) / k, 0.0f, 1.0f);
		} else {
			float corner = p.x < 0.0f ? (p.y < 0.0f ? in.f_radii.x : in.f_radii.w) : (p.y < 0.0f ? in.f_radii.y : in.f_radii.z);
			a = box_shadow(float2(0.0f), size, in.v_local, sigma, corner);
		}
		col = pm(in.f_fill0) * a;
	} else if (kind == 2) {
		float outer = clamp(0.5f - sd_shape(p, hs, in.f_radii, shape) / k, 0.0f, 1.0f);
		if (outer <= 0.0f) {
			discard_fragment();
			return float4(0.0f);
		}
		float4 hole = in.f_fill1;
		float2 hsz = hole.zw;
		float sigma = in.f_params.y;
		float h;
		if (hsz.x <= 0.0f || hsz.y <= 0.0f) {
			h = 0.0f;
		} else if (shape != 0) {
			float dh = sd_shape(in.v_local - (hole.xy + hsz * 0.5f), hsz * 0.5f, in.f_fill2, shape);
			h = sigma < 0.5f ? clamp(0.5f - dh / k, 0.0f, 1.0f) : clamp(0.5f - dh / (2.5f * sigma), 0.0f, 1.0f);
		} else if (sigma < 0.5f) {
			h = clamp(0.5f - sd_rrect(in.v_local - (hole.xy + hsz * 0.5f), hsz * 0.5f, in.f_fill2) / k, 0.0f, 1.0f);
		} else {
			float2 hp = in.v_local - (hole.xy + hsz * 0.5f);
			float corner = hp.x < 0.0f ? (hp.y < 0.0f ? in.f_fill2.x : in.f_fill2.w) : (hp.y < 0.0f ? in.f_fill2.y : in.f_fill2.z);
			h = box_shadow(hole.xy, hole.xy + hsz, in.v_local, sigma, corner);
		}
		col = pm(in.f_fill0) * outer * (1.0f - h);
	} else if (kind == 3) {
		float2 tc = (in.f_uv.xy + in.v_local / max(size, float2(1e-4f)) * in.f_uv.zw) / fu.u_atlas_size;
		float a = u_atlas.sample(s_atlas, tc).r;
		a = pow(max(a, 0.0f), fu.u_text_gamma);
		a = clamp((a - 0.5f) * fu.u_text_contrast + 0.5f, 0.0f, 1.0f) * step(0.0001f, a);
		col = pm(in.f_fill0) * a;
	} else if (kind == 5) {
		float2 pa = in.v_local - in.f_fill1.xy;
		float2 ba = in.f_fill1.zw - in.f_fill1.xy;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6f), 0.0f, 1.0f);
		float d = (length(pa - ba * h) - in.f_fill2.x) / k;
		col = pm(in.f_fill0) * clamp(0.5f - d, 0.0f, 1.0f);
	} else if (kind == 6) {
		float r = in.f_fill1.x;
		float th = in.f_fill1.y;
		float a0 = in.f_fill1.z;
		float sw = in.f_fill1.w;
		float ang = glsl_mod(atan2(p.y, p.x) - a0, 6.28318530718f);
		float d;
		if (ang <= sw) {
			d = abs(length(p) - r) - th;
		} else {
			float2 e0 = r * float2(cos(a0), sin(a0));
			float2 e1 = r * float2(cos(a0 + sw), sin(a0 + sw));
			d = min(length(p - e0), length(p - e1)) - th;
		}
		col = pm(in.f_fill0) * clamp(0.5f - d / k, 0.0f, 1.0f);
	} else if (kind == 7) {
		float slope = (in.f_fill1.y - in.f_fill1.x) / max(size.x, 1e-4f);
		float ty = in.f_fill1.x + slope * in.v_local.x;
		float d = (ty - in.v_local.y) / sqrt(1.0f + slope * slope);
		float cov = clamp(0.5f - d / k, 0.0f, 1.0f);
		col = mix(pm(in.f_fill0), pm(in.f_fill2), clamp(in.v_local.y / max(size.y, 1e-4f), 0.0f, 1.0f)) * cov;
	} else {
		float2 tc = in.f_uv.xy + in.v_local / max(size, float2(1e-4f)) * in.f_uv.zw;
		float4 t = u_image.sample(s_image, tc);
		col = float4(t.rgb * t.a, t.a) * in.f_fill0.a;
	}

	float2 w = in.v_world;
	if (w.x < in.f_clip.x || w.y < in.f_clip.y || w.x >= in.f_clip.z || w.y >= in.f_clip.w) {
		discard_fragment();
		return float4(0.0f);
	}
	if (in.f_clipr.x + in.f_clipr.y + in.f_clipr.z + in.f_clipr.w > 0.0f) {
		float2 cs = in.f_clip.zw - in.f_clip.xy;
		float dc = sd_rrect(w - (in.f_clip.xy + cs * 0.5f), cs * 0.5f, in.f_clipr);
		col *= clamp(0.5f - dc, 0.0f, 1.0f);
	}
	int fi = int(in.f_xt.z);
	if (fi > 0 && fi < 16 && col.a > 0.0f) {
		float4 c = float4(col.rgb / col.a, col.a);
		c = fu.u_filters[fi] * c + fu.u_filter_off[fi];
		c = clamp(c, 0.0f, 1.0f);
		col = float4(c.rgb * c.a, c.a);
	}
	return grade(col, kind, in.v_world, fu);
}

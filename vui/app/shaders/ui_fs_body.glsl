// Shared fragment shader body (GL 3.3 and Vulkan/SPIR-V).
float sd_rrect(vec2 p, vec2 hs, vec4 r) {
	float rad = p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
	rad = min(rad, min(hs.x, hs.y));
	vec2 q = abs(p) - hs + rad;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

// Ornate corner shapes. code packs 3 bits per corner (tl, tr, br, bl):
// 0 round, 1 bevel, 2 scoop, 3 notch, 4 arch (pointed arch spanning the top or bottom edge;
// the corner radius is the arch height).
float sd_shape(vec2 p, vec2 hs, vec4 r, int code) {
	if (code == 0) return sd_rrect(p, hs, r);
	int ci = p.x < 0.0 ? (p.y < 0.0 ? 0 : 3) : (p.y < 0.0 ? 1 : 2);
	int shape = (code >> (3 * ci)) & 7;
	float rad = ci == 0 ? r.x : (ci == 1 ? r.y : (ci == 2 ? r.z : r.w));
	if (shape == 0) return sd_rrect(p, hs, r);
	vec2 q = abs(p) - hs;
	float box = min(max(q.x, q.y), 0.0) + length(max(q, 0.0));
	if (shape == 4) {
		float h = clamp(rad, 1e-3, 2.0 * hs.y);
		float R = (h * h + hs.x * hs.x) / (2.0 * hs.x);
		float spring = hs.y - h; // distance of the springline from the centre
		vec2 a = vec2(abs(p.x), abs(p.y));
		if (a.y <= spring) return box;
		return max(box, length(a - vec2(hs.x - R, spring)) - R);
	}
	rad = min(rad, min(hs.x, hs.y));
	if (rad <= 0.0) return box;
	if (shape == 1) return max(box, (q.x + q.y + rad) * 0.70710678);
	if (shape == 2) return max(box, rad - length(q));
	return max(box, min(q.x + rad, q.y + rad));
}

vec4 pm(vec4 c) { return vec4(c.rgb * c.a, c.a); }

// Colour grade (see vui.Grade). u_grade = saturation, contrast, grain, mottle;
// u_grade_tint = rgb multiplier, mottle feature size in physical px (0 = grade off).
float g_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = g_hash(i), b = g_hash(i + vec2(1.0, 0.0));
	float c = g_hash(i + vec2(0.0, 1.0)), d = g_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
vec4 grade(vec4 col, int kind) {
	if (u_grade_tint.w <= 0.0 || col.a <= 0.0) return col;
	vec3 rgb = col.rgb / col.a;
	float l = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	rgb = mix(vec3(l), rgb, u_grade.x);
	rgb = (rgb - 0.5) * u_grade.y + 0.5;
	rgb *= u_grade_tint.rgb;
	if (kind != 3) {
		vec2 q = v_world / u_grade_tint.w;
		float m = g_noise(q) * 0.6 + g_noise(q * 2.7 + 17.0) * 0.4;
		float n = g_hash(floor(v_world)) - 0.5;
		rgb *= 1.0 + u_grade.w * (m - 0.5) + u_grade.z * n;
	}
	return vec4(clamp(rgb, 0.0, 1.0) * col.a, col.a);
}

// Texture fill for RRect commands: extra.z > 0 tiles every extra.z physical px, extra.z < 0
// stretches over the box. uv is the sub-rect of the bound image (normalized).
vec4 tex_fill(vec4 c) {
	if (f_extra.z == 0.0) return c;
	vec2 t = f_extra.z > 0.0 ? (v_local + f_extra.ww) / f_extra.z : v_local / max(f_size.xy, vec2(1e-4));
	vec2 tc = f_uv.xy + fract(t) * f_uv.zw;
	vec4 s = textureGrad(u_image, tc, dFdx(t) * f_uv.zw, dFdy(t) * f_uv.zw);
	return c * vec4(s.rgb * s.a, s.a);
}

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
	int shape = int(f_extra.y);
	if (kind == 0) {
		float d = sd_shape(p, hs, f_radii, shape) / k;
		float outer = clamp(0.5 - d, 0.0, 1.0);
		if (outer <= 0.0) discard;
		vec4 fill = tex_fill(fill_color(p, size));
		col = fill * outer;
		vec4 bw = f_bw;
		if (bw.x + bw.y + bw.z + bw.w > 0.0) {
			vec2 imin = vec2(bw.w, bw.x);
			vec2 imax = size - vec2(bw.y, bw.z);
			vec2 ihs = max((imax - imin) * 0.5, vec2(0.0));
			vec2 ic = (imin + imax) * 0.5;
			vec4 ir = max(f_radii - vec4(max(bw.w, bw.x), max(bw.y, bw.x), max(bw.y, bw.z), max(bw.w, bw.z)), 0.0);
			float di = shape == 0 ? sd_rrect(v_local - ic, ihs, ir) / k : d + max(max(bw.x, bw.y), max(bw.z, bw.w)) / k;
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
			a = clamp(0.5 - sd_shape(p, hs, f_radii, shape) / k, 0.0, 1.0);
		} else {
			float corner = p.x < 0.0 ? (p.y < 0.0 ? f_radii.x : f_radii.w) : (p.y < 0.0 ? f_radii.y : f_radii.z);
			a = box_shadow(vec2(0.0), size, v_local, sigma, corner);
		}
		col = pm(f_fill0) * a;
	} else if (kind == 2) {
		float outer = clamp(0.5 - sd_shape(p, hs, f_radii, shape) / k, 0.0, 1.0);
		if (outer <= 0.0) discard;
		vec4 hole = f_fill1;
		vec2 hsz = hole.zw;
		float sigma = f_params.y;
		float h;
		if (hsz.x <= 0.0 || hsz.y <= 0.0) {
			h = 0.0;
		} else if (shape != 0) {
			// ornate corners: the hole follows the same corner geometry as the box
			float dh = sd_shape(v_local - (hole.xy + hsz * 0.5), hsz * 0.5, f_fill2, shape);
			h = sigma < 0.5 ? clamp(0.5 - dh / k, 0.0, 1.0) : clamp(0.5 - dh / (2.5 * sigma), 0.0, 1.0);
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
	} else if (kind == 5) {
		// segment with round caps: fill1 = a.xy b.xy (local px), fill2.x = half width
		vec2 pa = v_local - f_fill1.xy;
		vec2 ba = f_fill1.zw - f_fill1.xy;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
		float d = (length(pa - ba * h) - f_fill2.x) / k;
		col = pm(f_fill0) * clamp(0.5 - d, 0.0, 1.0);
	} else if (kind == 6) {
		// arc around the quad centre: fill1 = radius, half width, start angle, sweep (rad, y down)
		float r = f_fill1.x;
		float th = f_fill1.y;
		float a0 = f_fill1.z;
		float sw = f_fill1.w;
		float ang = mod(atan(p.y, p.x) - a0, 6.28318530718);
		float d;
		if (ang <= sw) {
			d = abs(length(p) - r) - th;
		} else {
			vec2 e0 = r * vec2(cos(a0), sin(a0));
			vec2 e1 = r * vec2(cos(a0 + sw), sin(a0 + sw));
			d = min(length(p - e0), length(p - e1)) - th;
		}
		col = pm(f_fill0) * clamp(0.5 - d / k, 0.0, 1.0);
	} else if (kind == 7) {
		// area column: top edge from (0, fill1.x) to (w, fill1.y), filled down to the quad
		// bottom; vertical gradient fill0 (top) -> fill2 (bottom)
		float slope = (f_fill1.y - f_fill1.x) / max(size.x, 1e-4);
		float ty = f_fill1.x + slope * v_local.x;
		float d = (ty - v_local.y) / sqrt(1.0 + slope * slope);
		float cov = clamp(0.5 - d / k, 0.0, 1.0);
		col = mix(pm(f_fill0), pm(f_fill2), clamp(v_local.y / max(size.y, 1e-4), 0.0, 1.0)) * cov;
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
	if (fi > 0 && fi < 16 && col.a > 0.0) {
		vec4 c = vec4(col.rgb / col.a, col.a);
		c = u_filters[fi] * c + u_filter_off[fi];
		c = clamp(c, 0.0, 1.0);
		col = vec4(c.rgb * c.a, c.a);
	}
	o_color = grade(col, kind);
}

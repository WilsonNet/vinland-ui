package vui

import "core:math"
import "core:strconv"
import "core:strings"

// Straight-alpha sRGB color, components 0..1.
Color :: [4]f32

TRANSPARENT :: Color{0, 0, 0, 0}
BLACK :: Color{0, 0, 0, 1}
WHITE :: Color{1, 1, 1, 1}

rgb :: proc "contextless" (hex: u32, alpha: f32 = 1) -> Color {
	return Color {
		f32((hex >> 16) & 0xff) / 255,
		f32((hex >> 8) & 0xff) / 255,
		f32(hex & 0xff) / 255,
		alpha,
	}
}

with_alpha :: proc "contextless" (c: Color, a: f32) -> Color {
	return {c.r, c.g, c.b, a}
}

fade :: proc "contextless" (c: Color, mul: f32) -> Color {
	return {c.r, c.g, c.b, c.a * mul}
}

// Interpolates like CSS transitions (premultiplied sRGB).
color_lerp :: proc "contextless" (a, b: Color, t: f32) -> Color {
	if a.a == 0 && b.a == 0 {
		return TRANSPARENT
	}
	pa := [3]f32{a.r * a.a, a.g * a.a, a.b * a.a}
	pb := [3]f32{b.r * b.a, b.g * b.a, b.b * b.a}
	alpha := a.a + (b.a - a.a) * t
	if alpha <= 0 {
		return TRANSPARENT
	}
	p := pa + (pb - pa) * t
	return {p.x / alpha, p.y / alpha, p.z / alpha, alpha}
}

color_eq :: proc "contextless" (a, b: Color) -> bool {
	d := a - b
	return abs(d.r) < 1e-4 && abs(d.g) < 1e-4 && abs(d.b) < 1e-4 && abs(d.a) < 1e-4
}

// Relative luminance (WCAG) of an opaque color.
luminance :: proc "contextless" (c: Color) -> f32 {
	lin :: proc "contextless" (v: f32) -> f32 {
		return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4)
	}
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}

// Parses "#rgb", "#rgba", "#rrggbb", "#rrggbbaa" (leading # optional).
parse_hex_color :: proc(s: string) -> (c: Color, ok: bool) {
	h := strings.trim_prefix(s, "#")
	v, vok := strconv.parse_u64_of_base(h, 16)
	if !vok {
		return {}, false
	}
	switch len(h) {
	case 3:
		r := f32((v >> 8) & 0xf) / 15
		g := f32((v >> 4) & 0xf) / 15
		b := f32(v & 0xf) / 15
		return {r, g, b, 1}, true
	case 4:
		r := f32((v >> 12) & 0xf) / 15
		g := f32((v >> 8) & 0xf) / 15
		b := f32((v >> 4) & 0xf) / 15
		a := f32(v & 0xf) / 15
		return {r, g, b, a}, true
	case 6:
		return rgb(u32(v)), true
	case 8:
		return rgb(u32(v >> 8), f32(v & 0xff) / 255), true
	}
	return {}, false
}

// Parses "rgb(1 2 3)", "rgb(1,2,3)", "rgba(1,2,3,0.5)" and hex.
parse_css_color :: proc(s: string) -> (c: Color, ok: bool) {
	t := strings.trim_space(s)
	if strings.has_prefix(t, "#") {
		return parse_hex_color(t)
	}
	if strings.has_prefix(t, "rgb") {
		open := strings.index_byte(t, '(')
		close := strings.last_index_byte(t, ')')
		if open < 0 || close < open {
			return {}, false
		}
		inner := t[open + 1:close]
		vals: [4]f32 = {0, 0, 0, 1}
		n := 0
		for part in strings.fields_iterator(&inner) {
			p := strings.trim(part, ",/ ")
			if p == "" {
				continue
			}
			pct := strings.has_suffix(p, "%")
			f, fok := strconv.parse_f32(strings.trim_suffix(p, "%"))
			if !fok || n >= 4 {
				return {}, false
			}
			if n < 3 {
				vals[n] = pct ? f / 100 : f / 255
			} else {
				vals[n] = pct ? f / 100 : f
			}
			n += 1
		}
		return vals, n >= 3
	}
	return {}, false
}

// 4x5 color matrix used for CSS-style filters (grayscale, sepia, ...).
Color_Matrix :: struct {
	m: matrix[4, 4]f32,
	o: [4]f32,
}

COLOR_MATRIX_IDENTITY :: Color_Matrix {
	m = 1,
	o = {0, 0, 0, 0},
}

color_matrix_mul :: proc(a, b: Color_Matrix) -> Color_Matrix {
	// apply b then a
	return {m = a.m * b.m, o = a.m * b.o + a.o}
}

cm_grayscale :: proc(amount: f32) -> Color_Matrix {
	a := 1 - clamp(amount, 0, 1)
	m := matrix[4, 4]f32{
		0.2126 + 0.7874 * a, 0.7152 - 0.7152 * a, 0.0722 - 0.0722 * a, 0,
		0.2126 - 0.2126 * a, 0.7152 + 0.2848 * a, 0.0722 - 0.0722 * a, 0,
		0.2126 - 0.2126 * a, 0.7152 - 0.7152 * a, 0.0722 + 0.9278 * a, 0,
		0, 0, 0, 1,
	}
	return {m = m}
}

cm_sepia :: proc(amount: f32) -> Color_Matrix {
	a := 1 - clamp(amount, 0, 1)
	m := matrix[4, 4]f32{
		0.393 + 0.607 * a, 0.769 - 0.769 * a, 0.189 - 0.189 * a, 0,
		0.349 - 0.349 * a, 0.686 + 0.314 * a, 0.168 - 0.168 * a, 0,
		0.272 - 0.272 * a, 0.534 - 0.534 * a, 0.131 + 0.869 * a, 0,
		0, 0, 0, 1,
	}
	return {m = m}
}

cm_saturate :: proc(s: f32) -> Color_Matrix {
	m := matrix[4, 4]f32{
		0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0,
		0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0,
		0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0,
		0, 0, 0, 1,
	}
	return {m = m}
}

cm_hue_rotate :: proc(deg: f32) -> Color_Matrix {
	r := deg * math.PI / 180
	c := math.cos(r)
	s := math.sin(r)
	m := matrix[4, 4]f32{
		0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0,
		0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0,
		0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0,
		0, 0, 0, 1,
	}
	return {m = m}
}

cm_brightness :: proc(b: f32) -> Color_Matrix {
	m := matrix[4, 4]f32{
		b, 0, 0, 0,
		0, b, 0, 0,
		0, 0, b, 0,
		0, 0, 0, 1,
	}
	return {m = m}
}

cm_contrast :: proc(c: f32) -> Color_Matrix {
	o := 0.5 - 0.5 * c
	m := matrix[4, 4]f32{
		c, 0, 0, 0,
		0, c, 0, 0,
		0, 0, c, 0,
		0, 0, 0, 1,
	}
	return {m = m, o = {o, o, o, 0}}
}

cm_invert :: proc(amount: f32) -> Color_Matrix {
	a := clamp(amount, 0, 1)
	k := 1 - 2 * a
	m := matrix[4, 4]f32{
		k, 0, 0, 0,
		0, k, 0, 0,
		0, 0, k, 0,
		0, 0, 0, 1,
	}
	return {m = m, o = {a, a, a, 0}}
}

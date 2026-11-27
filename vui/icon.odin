package vui

import "core:math"
import "core:strconv"
import stbtt "vendor:stb/truetype"

// Vector icons from SVG path data. Paths are parsed once into contours, rasterized by
// stb_truetype's exact-coverage scanline rasterizer at the requested physical size and
// cached in the glyph atlas, so icons are exactly as crisp as text.

Icon :: distinct u32 // 0 = none

Icon_Path :: struct {
	d:        string,
	even_odd: bool,
}

@(private)
Seg_Kind :: enum u8 {
	Line,
	Quad,
	Cubic,
}

@(private)
Seg :: struct {
	kind: Seg_Kind,
	p0:   [2]f32,
	c0:   [2]f32,
	c1:   [2]f32,
	p1:   [2]f32,
}

@(private)
Contour :: struct {
	segs: [dynamic]Seg,
}

Icon_Def :: struct {
	name:     string,
	viewbox:  [2]f32,
	vertices: []stbtt.vertex, // in viewbox units * ICON_UNIT
}

ICON_UNIT :: 64

@(private)
Path_Lexer :: struct {
	s: string,
	i: int,
}

@(private)
lex_skip :: proc(l: ^Path_Lexer) {
	for l.i < len(l.s) {
		c := l.s[l.i]
		if c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r' {
			l.i += 1
		} else {
			break
		}
	}
}

@(private)
lex_cmd :: proc(l: ^Path_Lexer) -> (u8, bool) {
	lex_skip(l)
	if l.i >= len(l.s) {
		return 0, false
	}
	c := l.s[l.i]
	if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
		l.i += 1
		return c, true
	}
	return 0, false
}

@(private)
lex_has_num :: proc(l: ^Path_Lexer) -> bool {
	lex_skip(l)
	if l.i >= len(l.s) {
		return false
	}
	c := l.s[l.i]
	return (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.'
}

@(private)
lex_num :: proc(l: ^Path_Lexer) -> f32 {
	lex_skip(l)
	start := l.i
	if l.i < len(l.s) && (l.s[l.i] == '-' || l.s[l.i] == '+') {
		l.i += 1
	}
	seen_dot := false
	seen_e := false
	for l.i < len(l.s) {
		c := l.s[l.i]
		if c >= '0' && c <= '9' {
			l.i += 1
		} else if c == '.' && !seen_dot && !seen_e {
			seen_dot = true
			l.i += 1
		} else if (c == 'e' || c == 'E') && !seen_e {
			seen_e = true
			l.i += 1
			if l.i < len(l.s) && (l.s[l.i] == '-' || l.s[l.i] == '+') {
				l.i += 1
			}
		} else {
			break
		}
	}
	v, _ := strconv.parse_f32(l.s[start:l.i])
	return v
}

@(private)
lex_flag :: proc(l: ^Path_Lexer) -> bool {
	lex_skip(l)
	if l.i < len(l.s) {
		c := l.s[l.i]
		l.i += 1
		return c == '1'
	}
	return false
}

@(private)
arc_to_cubics :: proc(c: ^Contour, p0: [2]f32, rx0, ry0, phi_deg: f32, large, sweep: bool, p1: [2]f32) {
	rx := abs(rx0)
	ry := abs(ry0)
	if rx == 0 || ry == 0 {
		append(&c.segs, Seg{kind = .Line, p0 = p0, p1 = p1})
		return
	}
	phi := phi_deg * math.PI / 180
	cp := math.cos(phi)
	sp := math.sin(phi)
	dx := (p0.x - p1.x) / 2
	dy := (p0.y - p1.y) / 2
	x1p := cp * dx + sp * dy
	y1p := -sp * dx + cp * dy
	lam := (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
	if lam > 1 {
		s := math.sqrt(lam)
		rx *= s
		ry *= s
	}
	num := rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	den := rx * rx * y1p * y1p + ry * ry * x1p * x1p
	coef: f32 = 0
	if den != 0 {
		coef = math.sqrt(max(0, num / den))
	}
	if large == sweep {
		coef = -coef
	}
	cxp := coef * rx * y1p / ry
	cyp := -coef * ry * x1p / rx
	cx := cp * cxp - sp * cyp + (p0.x + p1.x) / 2
	cy := sp * cxp + cp * cyp + (p0.y + p1.y) / 2
	ang :: proc(ux, uy, vx, vy: f32) -> f32 {
		a := math.atan2(uy, ux)
		b := math.atan2(vy, vx)
		return b - a
	}
	t1 := math.atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
	dt := ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
	if !sweep && dt > 0 {
		dt -= 2 * math.PI
	} else if sweep && dt < 0 {
		dt += 2 * math.PI
	}
	n := int(math.ceil(abs(dt) / (math.PI / 2)))
	n = max(n, 1)
	step := dt / f32(n)
	k := 4.0 / 3.0 * math.tan(step / 4)
	prev := p0
	for i in 0 ..< n {
		a1 := t1 + step * f32(i)
		a2 := a1 + step
		c1 := math.cos(a1)
		s1 := math.sin(a1)
		c2 := math.cos(a2)
		s2 := math.sin(a2)
		e1 := [2]f32{c1 - k * s1, s1 + k * c1}
		e2 := [2]f32{c2 + k * s2, s2 - k * c2}
		e3 := [2]f32{c2, s2}
		tr :: proc(v: [2]f32, rx, ry, cp, sp, cx, cy: f32) -> [2]f32 {
			x := v.x * rx
			y := v.y * ry
			return {cp * x - sp * y + cx, sp * x + cp * y + cy}
		}
		q1 := tr(e1, rx, ry, cp, sp, cx, cy)
		q2 := tr(e2, rx, ry, cp, sp, cx, cy)
		q3 := i == n - 1 ? p1 : tr(e3, rx, ry, cp, sp, cx, cy)
		append(&c.segs, Seg{kind = .Cubic, p0 = prev, c0 = q1, c1 = q2, p1 = q3})
		prev = q3
	}
}

// Parses SVG path data into contours (allocations use the provided allocator).
@(private)
parse_path :: proc(d: string, contours: ^[dynamic]Contour) {
	l := Path_Lexer{s = d}
	cur: [2]f32
	start: [2]f32
	last_ctrl: [2]f32
	last_cmd: u8 = 0
	contour: ^Contour = nil
	begin :: proc(contours: ^[dynamic]Contour) -> ^Contour {
		append(contours, Contour{})
		return &contours[len(contours) - 1]
	}
	cmd: u8 = 0
	for {
		if c, ok := lex_cmd(&l); ok {
			cmd = c
		} else if !lex_has_num(&l) || cmd == 0 {
			break
		}
		rel := cmd >= 'a'
		up := rel ? cmd - 32 : cmd
		base := rel ? cur : [2]f32{0, 0}
		if up != 'M' && up != 'Z' && contour == nil {
			contour = begin(contours)
			start = cur
		}
		switch up {
		case 'M':
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			contour = begin(contours)
			cur = p
			start = p
			// subsequent implicit pairs are linetos
			cmd = rel ? 'l' : 'L'
		case 'L':
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			if contour == nil {
				contour = begin(contours)
			}
			append(&contour.segs, Seg{kind = .Line, p0 = cur, p1 = p})
			cur = p
		case 'H':
			x := lex_num(&l) + (rel ? cur.x : 0)
			p := [2]f32{x, cur.y}
			append(&contour.segs, Seg{kind = .Line, p0 = cur, p1 = p})
			cur = p
		case 'V':
			y := lex_num(&l) + (rel ? cur.y : 0)
			p := [2]f32{cur.x, y}
			append(&contour.segs, Seg{kind = .Line, p0 = cur, p1 = p})
			cur = p
		case 'C':
			c0 := [2]f32{lex_num(&l), lex_num(&l)} + base
			c1 := [2]f32{lex_num(&l), lex_num(&l)} + base
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			append(&contour.segs, Seg{kind = .Cubic, p0 = cur, c0 = c0, c1 = c1, p1 = p})
			last_ctrl = c1
			cur = p
		case 'S':
			c0 := cur
			if last_cmd == 'C' || last_cmd == 'S' {
				c0 = cur * 2 - last_ctrl
			}
			c1 := [2]f32{lex_num(&l), lex_num(&l)} + base
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			append(&contour.segs, Seg{kind = .Cubic, p0 = cur, c0 = c0, c1 = c1, p1 = p})
			last_ctrl = c1
			cur = p
		case 'Q':
			c0 := [2]f32{lex_num(&l), lex_num(&l)} + base
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			append(&contour.segs, Seg{kind = .Quad, p0 = cur, c0 = c0, p1 = p})
			last_ctrl = c0
			cur = p
		case 'T':
			c0 := cur
			if last_cmd == 'Q' || last_cmd == 'T' {
				c0 = cur * 2 - last_ctrl
			}
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			append(&contour.segs, Seg{kind = .Quad, p0 = cur, c0 = c0, p1 = p})
			last_ctrl = c0
			cur = p
		case 'A':
			rx := lex_num(&l)
			ry := lex_num(&l)
			rot := lex_num(&l)
			large := lex_flag(&l)
			sweep := lex_flag(&l)
			p := [2]f32{lex_num(&l), lex_num(&l)} + base
			arc_to_cubics(contour, cur, rx, ry, rot, large, sweep, p)
			cur = p
		case 'Z':
			if contour != nil && cur != start {
				append(&contour.segs, Seg{kind = .Line, p0 = cur, p1 = start})
			}
			cur = start
			contour = nil
			last_cmd = 'Z'
			continue
		case:
			return
		}
		last_cmd = up
		if contour == nil && up != 'M' {
			// drawing after Z without M starts a new contour at current point
		}
	}
}

@(private)
contour_poly :: proc(c: ^Contour, out: ^[dynamic][2]f32) {
	clear(out)
	for s in c.segs {
		switch s.kind {
		case .Line:
			append(out, s.p0)
		case .Quad:
			for i in 0 ..< 4 {
				t := f32(i) / 4
				u := 1 - t
				append(out, u * u * s.p0 + 2 * u * t * s.c0 + t * t * s.p1)
			}
		case .Cubic:
			for i in 0 ..< 6 {
				t := f32(i) / 6
				u := 1 - t
				append(out, u * u * u * s.p0 + 3 * u * u * t * s.c0 + 3 * u * t * t * s.c1 + t * t * t * s.p1)
			}
		}
	}
}

@(private)
poly_area :: proc(p: [][2]f32) -> f32 {
	a: f32 = 0
	for i in 0 ..< len(p) {
		j := (i + 1) % len(p)
		a += p[i].x * p[j].y - p[j].x * p[i].y
	}
	return a / 2
}

@(private)
point_in_poly :: proc(pt: [2]f32, p: [][2]f32) -> bool {
	inside := false
	j := len(p) - 1
	for i in 0 ..< len(p) {
		if ((p[i].y > pt.y) != (p[j].y > pt.y)) && (pt.x < (p[j].x - p[i].x) * (pt.y - p[i].y) / (p[j].y - p[i].y) + p[i].x) {
			inside = !inside
		}
		j = i
	}
	return inside
}

@(private)
reverse_contour :: proc(c: ^Contour) {
	n := len(c.segs)
	for i in 0 ..< n / 2 {
		c.segs[i], c.segs[n - 1 - i] = c.segs[n - 1 - i], c.segs[i]
	}
	for &s in c.segs {
		s.p0, s.p1 = s.p1, s.p0
		s.c0, s.c1 = s.c1, s.c0
		if s.kind == .Quad {
			s.c0 = s.c1
		}
	}
}

// Fixes quad control point after reversal (quads only use c0).
@(private)
reverse_contour_fix :: proc(c: ^Contour) {
	// handled in reverse_contour: for quads c1 is unused, swap leaves c0 in c1
}

// Registers an icon from SVG path data in a `viewbox` coordinate system. A name that is
// already registered returns the existing icon (setup code may run again after a hot reload).
icon_register :: proc(ctx: ^Context, name: string, viewbox: [2]f32, paths: []Icon_Path) -> Icon {
	if name != "" {
		if existing := icon_by_name(ctx, name); existing != 0 {
			return existing
		}
	}
	verts := make([dynamic]stbtt.vertex)
	contours := make([dynamic]Contour, context.temp_allocator)
	poly := make([dynamic][2]f32, context.temp_allocator)
	for p in paths {
		clear(&contours)
		parse_path(p.d, &contours)
		if p.even_odd && len(contours) > 1 {
			// emulate even-odd with nonzero: orient contours by nesting depth
			polys := make([][][2]f32, len(contours), context.temp_allocator)
			for &c, i in contours {
				contour_poly(&c, &poly)
				polys[i] = make([][2]f32, len(poly), context.temp_allocator)
				copy(polys[i], poly[:])
			}
			for &c, i in contours {
				if len(polys[i]) == 0 {
					continue
				}
				depth := 0
				for other, j in polys {
					if i != j && len(other) > 2 && point_in_poly(polys[i][0], other) {
						depth += 1
					}
				}
				a := poly_area(polys[i])
				want_positive := depth % 2 == 0
				if (a > 0) != want_positive {
					reverse_contour(&c)
				}
			}
		}
		for &c in contours {
			if len(c.segs) == 0 {
				continue
			}
			p0 := c.segs[0].p0 * ICON_UNIT
			append(&verts, stbtt.vertex{x = stbtt.vertex_type(p0.x), y = stbtt.vertex_type(p0.y), type = u8(stbtt.vmove.vmove)})
			for s in c.segs {
				v: stbtt.vertex
				p1 := s.p1 * ICON_UNIT
				v.x = stbtt.vertex_type(math.round(p1.x))
				v.y = stbtt.vertex_type(math.round(p1.y))
				switch s.kind {
				case .Line:
					v.type = u8(stbtt.vmove.vline)
				case .Quad:
					c0 := s.c0 * ICON_UNIT
					v.cx = stbtt.vertex_type(math.round(c0.x))
					v.cy = stbtt.vertex_type(math.round(c0.y))
					v.type = u8(stbtt.vmove.vcurve)
				case .Cubic:
					c0 := s.c0 * ICON_UNIT
					c1 := s.c1 * ICON_UNIT
					v.cx = stbtt.vertex_type(math.round(c0.x))
					v.cy = stbtt.vertex_type(math.round(c0.y))
					v.cx1 = stbtt.vertex_type(math.round(c1.x))
					v.cy1 = stbtt.vertex_type(math.round(c1.y))
					v.type = u8(stbtt.vmove.vcubic)
				}
				append(&verts, v)
			}
		}
		for &c in contours {
			delete(c.segs)
		}
	}
	append(&ctx.icons, Icon_Def{name = name, viewbox = viewbox, vertices = verts[:]})
	return Icon(len(ctx.icons)) // 1-based
}

icon_by_name :: proc(ctx: ^Context, name: string) -> Icon {
	for d, i in ctx.icons {
		if d.name == name {
			return Icon(i + 1)
		}
	}
	return 0
}

// Rasterizes icon at a physical pixel size (square box of `px_size`).
atlas_icon :: proc(a: ^Atlas, ctx: ^Context, icon: Icon, px_w, px_h: f32) -> (Atlas_Entry, bool) {
	if icon == 0 || int(icon) > len(ctx.icons) {
		return {}, false
	}
	w := int(math.round(px_w))
	h := int(math.round(px_h))
	if w <= 0 || h <= 0 || w > 2048 || h > 2048 {
		return {}, false
	}
	key := glyph_key(1, u16(icon), u16(w), u16(h), 0)
	if e, ok := a.entries[key]; ok {
		return e, true
	}
	def := &ctx.icons[icon - 1]
	x, y, ok := atlas_alloc(a, w, h)
	if !ok {
		return {}, false
	}
	bm := stbtt._bitmap {
		w      = i32(w),
		h      = i32(h),
		stride = i32(a.w),
		pixels = &a.pixels[y * a.w + x],
	}
	sx := f32(w) / (def.viewbox.x * ICON_UNIT)
	sy := f32(h) / (def.viewbox.y * ICON_UNIT)
	if len(def.vertices) > 0 {
		stbtt.Rasterize(&bm, 0.2, raw_data(def.vertices), i32(len(def.vertices)), sx, sy, 0, 0, 0, 0, false, nil)
	}
	atlas_mark(a, y, y + h)
	e := Atlas_Entry{x = i16(x), y = i16(y), w = i16(w), h = i16(h)}
	a.entries[key] = e
	return e, true
}

package vui

import "core:math"
import "core:strings"
import "core:unicode/utf8"
import stbtt "vendor:stb/truetype"

// ---------------------------------------------------------------------------
// Fonts
//
// Text quality rules this engine follows (the reasons native UIs often look worse than web):
//  1. Glyphs are rasterized at the exact *physical* pixel size (font-size * display scale).
//     Nothing is ever bitmap-scaled, so fractional display scales (1.25, 1.333...) stay sharp.
//  2. Horizontal pen positions keep 1/4-pixel precision (4 subpixel variants per glyph), so
//     spacing matches the font's metrics instead of drifting to whole pixels.
//  3. Baselines and box edges snap to whole physical pixels, so stems and borders stay crisp.
//  4. Kerning comes from the font (kern + GPOS pair adjustments).
// ---------------------------------------------------------------------------

Face_Id :: u16

Glyph_Metric :: struct {
	glyph: u16,
	adv:   f32, // em units (advance / units-per-em)
}

Face :: struct {
	family:        string,
	weight:        u16,
	italic:        bool,
	data:          []u8,
	info:          stbtt.fontinfo,
	upem:          f32,
	ascent:        f32, // em
	descent:       f32, // em, positive
	line_gap:      f32,
	underline_pos: f32, // em, negative = below baseline
	underline_th:  f32, // em
	has_kern:      bool,
	ascii:         [128]Glyph_Metric,
	glyphs:        map[rune]Glyph_Metric,
}

Fonts :: struct {
	faces:    [dynamic]Face,
	families: map[string][dynamic]Face_Id,
}

@(private)
read_u16be :: proc(d: []u8, o: int) -> u16 {
	return u16(d[o]) << 8 | u16(d[o + 1])
}

@(private)
read_i16be :: proc(d: []u8, o: int) -> i16 {
	return i16(read_u16be(d, o))
}

@(private)
find_table :: proc(d: []u8, tag: string) -> int {
	if len(d) < 12 {
		return -1
	}
	n := int(read_u16be(d, 4))
	for i in 0 ..< n {
		o := 12 + i * 16
		if o + 16 > len(d) {
			return -1
		}
		if string(d[o:o + 4]) == tag {
			return int(read_u16be(d, o + 8)) << 16 | int(read_u16be(d, o + 10))
		}
	}
	return -1
}

// Registers a TrueType/OpenType (glyf) font. `data` must outlive the context.
// Registering the same family, weight and style again returns the existing face, so setup code
// can run more than once (hot reload re-runs `Program.setup` on every load).
font_register :: proc(fonts: ^Fonts, family: string, data: []u8, weight: u16 = 400, italic := false) -> (Face_Id, bool) {
	if list, ok := fonts.families[family]; ok {
		for id in list {
			if f := &fonts.faces[id]; f.weight == weight && f.italic == italic {
				return id, true
			}
		}
	}
	f: Face
	f.family = strings.clone(family)
	f.weight = weight
	f.italic = italic
	f.data = data
	if !stbtt.InitFont(&f.info, raw_data(data), stbtt.GetFontOffsetForIndex(raw_data(data), 0)) {
		return 0, false
	}
	head := find_table(data, "head")
	f.upem = head >= 0 ? f32(read_u16be(data, head + 18)) : 1000
	asc, desc, gap: i32
	stbtt.GetFontVMetrics(&f.info, &asc, &desc, &gap)
	f.ascent = f32(asc) / f.upem
	f.descent = -f32(desc) / f.upem
	f.line_gap = f32(gap) / f.upem
	post := find_table(data, "post")
	if post >= 0 {
		f.underline_pos = f32(read_i16be(data, post + 8)) / f.upem
		f.underline_th = f32(read_i16be(data, post + 10)) / f.upem
	} else {
		f.underline_pos = -0.1
		f.underline_th = 0.06
	}
	f.has_kern = f.info.kern != 0 || f.info.gpos != 0
	for c in 0 ..< 128 {
		f.ascii[c] = face_lookup_uncached(&f, rune(c))
	}
	id := Face_Id(len(fonts.faces))
	append(&fonts.faces, f)
	key := f.family
	if key not_in fonts.families {
		fonts.families[key] = make([dynamic]Face_Id)
	}
	list := &fonts.families[key]
	append(list, id)
	return id, true
}

@(private)
face_lookup_uncached :: proc(f: ^Face, r: rune) -> Glyph_Metric {
	g := stbtt.FindGlyphIndex(&f.info, r)
	adv, lsb: i32
	stbtt.GetGlyphHMetrics(&f.info, g, &adv, &lsb)
	return {u16(g), f32(adv) / f.upem}
}

face_glyph :: proc(f: ^Face, r: rune) -> Glyph_Metric {
	if r >= 0 && r < 128 {
		return f.ascii[r]
	}
	if m, ok := f.glyphs[r]; ok {
		return m
	}
	m := face_lookup_uncached(f, r)
	f.glyphs[r] = m
	return m
}

face_kern :: proc(f: ^Face, a, b: u16) -> f32 {
	if !f.has_kern || a == 0 || b == 0 {
		return 0
	}
	return f32(stbtt.GetGlyphKernAdvance(&f.info, i32(a), i32(b))) / f.upem
}

// CSS font matching (simplified): prefer matching italic, then the nearest weight.
font_match :: proc(fonts: ^Fonts, family: string, weight: u16, italic: bool) -> Face_Id {
	list, ok := fonts.families[family]
	if !ok || len(list) == 0 {
		if len(fonts.faces) == 0 {
			return 0
		}
		// fall back to the first registered family
		for _, l in fonts.families {
			list = l
			break
		}
	}
	best := list[0]
	best_score := max(int)
	for id in list {
		f := &fonts.faces[id]
		score := abs(int(f.weight) - int(weight)) * 2
		if f.weight > weight && weight <= 500 {
			score += 1 // prefer lighter for normal weights
		} else if f.weight < weight && weight > 500 {
			score += 1
		}
		if f.italic != italic {
			score += 10000
		}
		if score < best_score {
			best_score = score
			best = id
		}
	}
	return best
}

// ---------------------------------------------------------------------------
// Glyph atlas (single channel coverage, shelf packed, grows to 4096^2)
// ---------------------------------------------------------------------------

ATLAS_INITIAL :: 1024
ATLAS_MAX :: 4096

Atlas_Entry :: struct {
	x, y, w, h: i16,
	ox, oy:     i16, // bitmap offset from pen/baseline in px
}

Shelf :: struct {
	y, h, x: int,
}

Atlas :: struct {
	w, h:       int,
	pixels:     []u8,
	shelves:    [dynamic]Shelf,
	entries:    map[u64]Atlas_Entry,
	dirty:      bool,
	dirty_y0:   int,
	dirty_y1:   int,
	generation: u32, // bumps when resized or cleared (backend re-uploads)
	reset_requested: bool,
}

atlas_init :: proc(a: ^Atlas) {
	a.w = ATLAS_INITIAL
	a.h = ATLAS_INITIAL
	a.pixels = make([]u8, a.w * a.h)
	a.generation += 1
	a.dirty = true
	a.dirty_y0 = 0
	a.dirty_y1 = a.h
}

atlas_destroy :: proc(a: ^Atlas) {
	delete(a.pixels)
	delete(a.shelves)
	delete(a.entries)
}

atlas_clear :: proc(a: ^Atlas) {
	clear(&a.shelves)
	clear(&a.entries)
	for &p in a.pixels {
		p = 0
	}
	a.generation += 1
	a.dirty = true
	a.dirty_y0 = 0
	a.dirty_y1 = a.h
	a.reset_requested = false
}

@(private)
atlas_mark :: proc(a: ^Atlas, y0, y1: int) {
	if !a.dirty {
		a.dirty = true
		a.dirty_y0 = y0
		a.dirty_y1 = y1
	} else {
		a.dirty_y0 = min(a.dirty_y0, y0)
		a.dirty_y1 = max(a.dirty_y1, y1)
	}
}

@(private)
atlas_grow :: proc(a: ^Atlas) -> bool {
	if a.h >= ATLAS_MAX && a.w >= ATLAS_MAX {
		return false
	}
	nw := a.w
	nh := a.h
	if a.h < ATLAS_MAX {
		nh = a.h * 2
	} else {
		nw = a.w * 2
	}
	np := make([]u8, nw * nh)
	for y in 0 ..< a.h {
		copy(np[y * nw:y * nw + a.w], a.pixels[y * a.w:(y + 1) * a.w])
	}
	delete(a.pixels)
	a.pixels = np
	a.w = nw
	a.h = nh
	a.generation += 1
	a.dirty = true
	a.dirty_y0 = 0
	a.dirty_y1 = a.h
	return true
}

// Reserves a w*h region (with 1px gutter). Returns false when full.
atlas_alloc :: proc(a: ^Atlas, w, h: int) -> (x, y: int, ok: bool) {
	gw := w + 2
	gh := h + 2
	if w <= 0 || h <= 0 || gw > ATLAS_MAX || gh > ATLAS_MAX {
		// can never fit: fail without growing to the maximum and wiping the atlas every
		// frame (which would re-upload the full 16 MB texture each frame)
		return 0, 0, false
	}
	for {
		for &s in a.shelves {
			if gh <= s.h && s.h <= gh + gh / 3 + 4 && s.x + gw <= a.w {
				x = s.x + 1
				y = s.y + 1
				s.x += gw
				return x, y, true
			}
		}
		top := 0
		if len(a.shelves) > 0 {
			last := a.shelves[len(a.shelves) - 1]
			top = last.y + last.h
		}
		if top + gh <= a.h && gw <= a.w {
			append(&a.shelves, Shelf{y = top, h = gh, x = gw})
			return 1, top + 1, true
		}
		if !atlas_grow(a) {
			a.reset_requested = true
			return 0, 0, false
		}
	}
}

@(private)
glyph_key :: proc "contextless" (kind: u8, face: u16, glyph: u16, size_q: u16, sub: u8) -> u64 {
	return u64(kind) << 56 | u64(face) << 40 | u64(glyph) << 24 | u64(size_q) << 8 | u64(sub)
}

SUBPIXEL_STEPS :: 4

// Returns the atlas entry for a glyph rendered at `px_size` physical pixels with
// horizontal subpixel phase `sub` (0..SUBPIXEL_STEPS-1).
atlas_glyph :: proc(a: ^Atlas, fonts: ^Fonts, face: Face_Id, glyph: u16, px_size: f32, sub: int) -> (Atlas_Entry, bool) {
	size_q := u16(clamp(math.round(px_size * 4), 1, 65535))
	key := glyph_key(0, face, glyph, size_q, u8(sub))
	if e, ok := a.entries[key]; ok {
		return e, true
	}
	f := &fonts.faces[face]
	sc := stbtt.ScaleForMappingEmToPixels(&f.info, f32(size_q) / 4)
	shift := f32(sub) / SUBPIXEL_STEPS
	x0, y0, x1, y1: i32
	stbtt.GetGlyphBitmapBoxSubpixel(&f.info, i32(glyph), sc, sc, shift, 0, &x0, &y0, &x1, &y1)
	w := int(x1 - x0)
	h := int(y1 - y0)
	e := Atlas_Entry{ox = i16(x0), oy = i16(y0)}
	if w > 0 && h > 0 {
		x, y, ok := atlas_alloc(a, w, h)
		if !ok {
			return {}, false
		}
		stbtt.MakeGlyphBitmapSubpixel(&f.info, &a.pixels[y * a.w + x], i32(w), i32(h), i32(a.w), sc, sc, shift, 0, i32(glyph))
		e.x = i16(x)
		e.y = i16(y)
		e.w = i16(w)
		e.h = i16(h)
		atlas_mark(a, y, y + h)
	}
	a.entries[key] = e
	return e, true
}

// ---------------------------------------------------------------------------
// Paragraph layout
// ---------------------------------------------------------------------------

Span :: struct {
	text:   string,
	style:  Style,
	node:   i32, // owning span node (for hit testing / debug), -1 when anonymous
	face:   Face_Id,
	size:   f32,
	lh:     f32,
	ls:     f32,
	ascent: f32, // px
	descent: f32,
	pad:    [4]f32, // inline box padding (t r b l)
}

Text_Glyph :: struct {
	sx:     f32, // pen x in the unbroken run (logical px)
	x:      f32, // pen x from line start (logical px), before alignment
	adv:    f32,
	glyph:  u16,
	span:   u16,
	byte:   u32, // byte offset within span text
	flags:  Glyph_Flags,
}

Glyph_Flag :: enum u8 {
	Space,
	Break_After,
	Newline,
	Span_Start,
	Span_End,
	Ellipsis,
}
Glyph_Flags :: bit_set[Glyph_Flag;u8]

Text_Line :: struct {
	first, count: i32,
	width:        f32,
	x:            f32, // alignment offset
	top:          f32,
	height:       f32,
	baseline:     f32, // from paragraph top
}

Paragraph :: struct {
	spans:    [dynamic]Span,
	glyphs:   [dynamic]Text_Glyph,
	lines:    [dynamic]Text_Line,
	min_w:    f32, // min-content
	max_w:    f32, // max-content
	shaped:   bool,
	laid_w:   f32, // width used for the current line layout (-1 = none)
	laid:     bool,
	width:    f32,
	height:   f32,
	ellipsis_glyph: Text_Glyph,
	ellipsis_line:  i32,
	has_ellipsis:   bool,
}

@(private)
apply_text_transform :: proc(s: string, tt: Text_Transform, allocator := context.temp_allocator) -> string {
	switch tt {
	case .None:
		return s
	case .Upper:
		return strings.to_upper(s, allocator)
	case .Lower:
		return strings.to_lower(s, allocator)
	case .Capitalize:
		b := strings.builder_make(allocator)
		prev_space := true
		for r in s {
			if prev_space && r >= 'a' && r <= 'z' {
				strings.write_rune(&b, r - 32)
			} else {
				strings.write_rune(&b, r)
			}
			prev_space = r == ' ' || r == '\n' || r == '\t'
		}
		return strings.to_string(b)
	}
	return s
}

@(private)
collapse_ws :: proc(s: string, keep_newlines: bool, allocator := context.temp_allocator) -> string {
	needs := false
	prev := false
	for i in 0 ..< len(s) {
		c := s[i]
		ws := c == ' ' || c == '\t' || (c == '\n' && !keep_newlines) || c == '\r'
		if (ws && prev) || c == '\t' || c == '\r' || (c == '\n' && !keep_newlines) {
			needs = true
			break
		}
		prev = ws
	}
	if !needs {
		return s
	}
	b := strings.builder_make(allocator)
	prev = false
	for i in 0 ..< len(s) {
		c := s[i]
		if c == '\n' && keep_newlines {
			strings.write_byte(&b, '\n')
			prev = true
			continue
		}
		ws := c == ' ' || c == '\t' || c == '\n' || c == '\r'
		if ws {
			if !prev {
				strings.write_byte(&b, ' ')
			}
			prev = true
		} else {
			strings.write_byte(&b, c)
			prev = false
		}
	}
	return strings.to_string(b)
}

// Converts spans into positioned glyph runs (no line breaking yet). Computes min/max content.
paragraph_shape :: proc(p: ^Paragraph, fonts: ^Fonts, theme: ^Theme, allocator := context.temp_allocator) {
	if p.shaped {
		return
	}
	p.shaped = true
	clear(&p.glyphs)
	x: f32 = 0
	word_w: f32 = 0
	line_w: f32 = 0
	p.min_w = 0
	p.max_w = 0
	for &sp, si in p.spans {
		st := &sp.style
		fam := resolve_family(theme, st.font_family)
		sp.face = font_match(fonts, fam, st.font_weight, st.italic)
		f := &fonts.faces[sp.face]
		sp.size = st.font_size
		sp.lh = line_height_px(st)
		sp.ls = letter_spacing_px(st)
		sp.ascent = f.ascent * sp.size
		sp.descent = f.descent * sp.size
		ws := st.white_space
		keep_nl := ws == .Pre || ws == .Pre_Wrap || ws == .Pre_Line || ws == .Break_Spaces
		text := sp.text
		if ws == .Normal || ws == .No_Wrap || ws == .Pre_Line {
			text = collapse_ws(text, ws == .Pre_Line, allocator)
		}
		text = apply_text_transform(text, st.text_transform, allocator)
		sp.text = text
		wraps := ws != .No_Wrap && ws != .Pre && st.text_wrap != .No_Wrap
		break_all := st.word_break == .Break_All || st.word_break == .Anywhere
		prev_glyph: u16 = 0
		first := true
		for r, bi in text {
			if r == '\n' && keep_nl {
				append(&p.glyphs, Text_Glyph{sx = x, x = x, adv = 0, span = u16(si), byte = u32(bi), flags = {.Newline}})
				p.max_w = max(p.max_w, line_w)
				p.min_w = max(p.min_w, word_w)
				line_w = 0
				word_w = 0
				prev_glyph = 0
				continue
			}
			rr := r
			if r == '\t' {
				rr = ' '
			}
			m := face_glyph(f, rr)
			adv := m.adv * sp.size
			if prev_glyph != 0 {
				k := face_kern(f, prev_glyph, m.glyph) * sp.size
				if len(p.glyphs) > 0 {
					p.glyphs[len(p.glyphs) - 1].adv += k
					line_w += k
					word_w += k
					x += k
				}
			}
			adv += sp.ls
			if r == '\t' {
				adv *= 4
			}
			g := Text_Glyph{sx = x, x = x, adv = adv, glyph = m.glyph, span = u16(si), byte = u32(bi)}
			if first {
				g.flags += {.Span_Start}
				first = false
				if sp.pad[3] > 0 {
					g.sx += sp.pad[3]
					g.x += sp.pad[3]
					x += sp.pad[3]
					line_w += sp.pad[3]
					word_w += sp.pad[3]
				}
			}
			is_space := rr == ' '
			if is_space {
				g.flags += {.Space}
				if wraps {
					g.flags += {.Break_After}
				}
			} else if wraps && (r == '-' || r == '/' || break_all || r == 0x2014 || r == 0x2013) {
				g.flags += {.Break_After}
			}
			append(&p.glyphs, g)
			x += adv
			line_w += adv
			if is_space || .Break_After in g.flags {
				if !is_space {
					word_w += adv
				}
				p.min_w = max(p.min_w, word_w)
				word_w = 0
			} else {
				word_w += adv
			}
			prev_glyph = m.glyph
		}
		if !first && len(p.glyphs) > 0 {
			last := &p.glyphs[len(p.glyphs) - 1]
			last.flags += {.Span_End}
			if sp.pad[1] > 0 {
				last.adv += sp.pad[1]
				x += sp.pad[1]
				line_w += sp.pad[1]
				word_w += sp.pad[1]
			}
		}
		if !wraps {
			// a no-wrap span contributes its whole width as min-content
			word_w = word_w
		}
	}
	p.min_w = max(p.min_w, word_w)
	p.max_w = max(p.max_w, line_w)
	// non-wrapping paragraphs: min = max
	all_nowrap := true
	for &sp in p.spans {
		ws := sp.style.white_space
		if ws != .No_Wrap && ws != .Pre && sp.style.text_wrap != .No_Wrap {
			all_nowrap = false
		}
	}
	if all_nowrap {
		// min-content is the longest line
		lw: f32 = 0
		mx: f32 = 0
		for g in p.glyphs {
			if .Newline in g.flags {
				mx = max(mx, lw)
				lw = 0
			} else {
				lw += g.adv
			}
		}
		p.min_w = max(mx, lw)
	}
	p.min_w = math.ceil(p.min_w * 64) / 64
	p.max_w = math.ceil(p.max_w * 64) / 64
	p.laid = false
}

resolve_family :: proc(theme: ^Theme, token: string) -> string {
	t := token
	if t == "" {
		t = theme.default_font
	}
	if fam, ok := theme.fonts[t]; ok {
		return fam
	}
	return t
}

// Breaks shaped glyphs into lines for `max_width` (use a huge value for no wrapping).
paragraph_layout :: proc(p: ^Paragraph, fonts: ^Fonts, max_width: f32) {
	if p.laid && abs(p.laid_w - max_width) < 0.01 {
		return
	}
	p.laid = true
	p.laid_w = max_width
	p.has_ellipsis = false
	clear(&p.lines)
	n := i32(len(p.glyphs))
	if len(p.spans) == 0 {
		p.width = 0
		p.height = 0
		return
	}
	root := &p.spans[0].style
	limit := max_width + 0.01
	i: i32 = 0
	top: f32 = 0
	max_line_w: f32 = 0
	clamp_lines := root.line_clamp
	truncate := root.truncate
	for {
		// skip collapsible leading spaces
		for i < n && (.Space in p.glyphs[i].flags) && p.spans[p.glyphs[i].span].style.white_space != .Pre && p.spans[p.glyphs[i].span].style.white_space != .Pre_Wrap && p.spans[p.glyphs[i].span].style.white_space != .Break_Spaces {
			i += 1
		}
		start := i
		x: f32 = 0
		line_x0: f32 = start < n ? p.glyphs[start].sx : 0
		last_break: i32 = -1
		end := n
		next := n
		overflow := false
		j := start
		for j < n {
			g := &p.glyphs[j]
			if .Newline in g.flags {
				end = j
				next = j + 1
				break
			}
			gx := g.sx - line_x0
			right := gx + g.adv
			if right > limit && j > start && !(.Space in g.flags) {
				if last_break >= start {
					end = last_break + 1
					next = end
					break
				}
				ws := p.spans[g.span].style.word_break
				if ws == .Break_All || ws == .Anywhere || ws == .Break_Word {
					end = j
					next = j
					break
				}
				overflow = true
			}
			if .Break_After in g.flags {
				last_break = j
				if overflow {
					end = j + 1
					next = end
					break
				}
			}
			x = right
			j += 1
		}
		if j >= n {
			end = n
			next = n
		}
		// measure (excluding trailing spaces)
		w: f32 = 0
		k := end - 1
		for k >= start && (.Space in p.glyphs[k].flags) {
			k -= 1
		}
		if k >= start {
			w = p.glyphs[k].sx + p.glyphs[k].adv - line_x0
		}
		// line metrics
		lh: f32 = 0
		base: f32 = 0
		if end > start {
			seen: [64]bool
			for gi in start ..< end {
				si := p.glyphs[gi].span
				if int(si) < 64 && seen[si] {
					continue
				}
				if int(si) < 64 {
					seen[si] = true
				}
				sp := &p.spans[si]
				lh = max(lh, sp.lh)
				half := (sp.lh - (sp.ascent + sp.descent)) / 2
				base = max(base, half + sp.ascent)
			}
		} else {
			si := start < n ? p.glyphs[start].span : 0
			if next > 0 && next - 1 < n {
				si = p.glyphs[next - 1].span
			}
			sp := &p.spans[si]
			lh = sp.lh
			base = (sp.lh - (sp.ascent + sp.descent)) / 2 + sp.ascent
		}
		line := Text_Line {
			first    = start,
			count    = end - start,
			width    = w,
			top      = top,
			height   = lh,
			baseline = top + base,
		}
		// shift glyph x to be relative to line start
		for gi in start ..< end {
			p.glyphs[gi].x = p.glyphs[gi].sx - line_x0
		}
		append(&p.lines, line)
		max_line_w = max(max_line_w, w)
		top += lh
		i = next
		if i >= n {
			// a trailing newline produces an empty last line
			if n > 0 && .Newline in p.glyphs[n - 1].flags && end != n {
				sp := &p.spans[p.glyphs[n - 1].span]
				append(&p.lines, Text_Line{first = n, count = 0, top = top, height = sp.lh, baseline = top + (sp.lh - (sp.ascent + sp.descent)) / 2 + sp.ascent})
				top += sp.lh
			}
			break
		}
		if clamp_lines > 0 && i32(len(p.lines)) >= clamp_lines {
			paragraph_ellipsize(p, fonts, i32(len(p.lines) - 1), max_width)
			break
		}
	}
	if len(p.lines) == 0 {
		sp := &p.spans[0]
		append(&p.lines, Text_Line{top = 0, height = sp.lh, baseline = (sp.lh - (sp.ascent + sp.descent)) / 2 + sp.ascent})
		top = sp.lh
	}
	if truncate && len(p.lines) > 0 && p.lines[0].width > max_width + 0.01 {
		paragraph_ellipsize(p, fonts, 0, max_width)
	}
	p.width = max_line_w
	p.height = top
	// alignment
	align := root.text_align
	for &l in p.lines {
		free_w := max_width - l.width
		if max_width > 1e8 {
			free_w = max_line_w - l.width
		}
		switch align {
		case .Center:
			l.x = free_w / 2
		case .Right, .End:
			l.x = free_w
		case .Start, .Left, .Justify:
			l.x = 0
		}
	}
}

@(private)
paragraph_ellipsize :: proc(p: ^Paragraph, fonts: ^Fonts, line_idx: i32, max_width: f32) {
	l := &p.lines[line_idx]
	if l.count == 0 {
		return
	}
	last_span := p.glyphs[l.first + l.count - 1].span
	sp := &p.spans[last_span]
	f := &fonts.faces[sp.face]
	m := face_glyph(f, 0x2026)
	ew := m.adv * sp.size
	cut := l.count
	for cut > 0 {
		g := p.glyphs[l.first + cut - 1]
		if g.x + g.adv + ew <= max_width + 0.01 && !(.Space in g.flags) {
			break
		}
		cut -= 1
	}
	l.count = cut
	ex: f32 = 0
	if cut > 0 {
		g := p.glyphs[l.first + cut - 1]
		ex = g.x + g.adv
	}
	p.ellipsis_glyph = Text_Glyph{x = ex, adv = ew, glyph = m.glyph, span = last_span, flags = {.Ellipsis}}
	l.width = ex + ew
	p.ellipsis_line = line_idx
	p.has_ellipsis = true
}

paragraph_reset :: proc(p: ^Paragraph) {
	clear(&p.spans)
	clear(&p.glyphs)
	clear(&p.lines)
	p.shaped = false
	p.laid = false
	p.has_ellipsis = false
}

// Measures a single-style string (used by widgets such as text inputs).
measure_string :: proc(fonts: ^Fonts, theme: ^Theme, s: string, st: ^Style) -> f32 {
	fam := resolve_family(theme, st.font_family)
	face := font_match(fonts, fam, st.font_weight, st.italic)
	f := &fonts.faces[face]
	w: f32 = 0
	prev: u16 = 0
	ls := letter_spacing_px(st)
	for r in s {
		m := face_glyph(f, r)
		if prev != 0 {
			w += face_kern(f, prev, m.glyph) * st.font_size
		}
		w += m.adv * st.font_size + ls
		prev = m.glyph
	}
	return w
}

// Byte offsets of each caret stop in s plus their x positions (for text inputs).
caret_stops :: proc(fonts: ^Fonts, theme: ^Theme, s: string, st: ^Style, allocator := context.temp_allocator) -> (offsets: []int, xs: []f32) {
	fam := resolve_family(theme, st.font_family)
	face := font_match(fonts, fam, st.font_weight, st.italic)
	f := &fonts.faces[face]
	n := utf8.rune_count(s)
	offsets = make([]int, n + 1, allocator)
	xs = make([]f32, n + 1, allocator)
	w: f32 = 0
	prev: u16 = 0
	ls := letter_spacing_px(st)
	i := 0
	for r, bi in s {
		m := face_glyph(f, r)
		if prev != 0 {
			w += face_kern(f, prev, m.glyph) * st.font_size
		}
		offsets[i] = bi
		xs[i] = w
		w += m.adv * st.font_size + ls
		prev = m.glyph
		i += 1
	}
	offsets[n] = len(s)
	xs[n] = w
	return
}

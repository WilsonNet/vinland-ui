package vui

import "core:math"
import "core:slice"

// CSS-like layout: block flow (with inline runs), flexbox, grid, absolute/fixed.
// All sizes are logical px and border-box. `final` passes position children;
// measure passes only compute sizes and are cached per node per frame.

@(private)
resolve :: proc(ctx: ^Context, s: Size, cb: f32) -> (f32, bool) {
	switch s.kind {
	case .Px:
		return s.v, true
	case .Percent:
		if cb >= INF * 0.5 {
			return 0, false
		}
		return cb * s.v / 100, true
	case .Vw:
		return ctx.viewport.x * s.v / 100, true
	case .Vh:
		return ctx.viewport.y * s.v / 100, true
	case .Auto, .Min_Content, .Max_Content, .Fit_Content:
		return 0, false
	}
	return 0, false
}

@(private)
pad_border :: proc "contextless" (s: ^Style) -> [4]f32 {
	return s.padding + s.border_w
}

@(private)
in_flow :: proc "contextless" (n: ^Node) -> bool {
	return n.style.display != .None && n.style.position != .Absolute && n.style.position != .Fixed
}

@(private)
clamp_axis :: proc(ctx: ^Context, v: f32, mn, mx: Size, cb: f32, extra: f32) -> f32 {
	r := v
	if m, ok := resolve(ctx, mx, cb); ok && mx.kind != .Auto {
		r = min(r, m + extra)
	}
	if m, ok := resolve(ctx, mn, cb); ok {
		r = max(r, m + extra)
	}
	return max(r, 0)
}

layout_root :: proc(ctx: ^Context) {
	vp := ctx.viewport
	root := &ctx.nodes[0]
	root.pos = {0, 0}
	layout_box(ctx, 0, vp, {vp.x, vp.y}, vp, true)
}

// ---------------------------------------------------------------------------
// Intrinsic widths
// ---------------------------------------------------------------------------

intrinsic :: proc(ctx: ^Context, ni: i32) -> [2]f32 {
	n := &ctx.nodes[ni]
	if .Measured_Intrinsic in n.flags {
		return n.intrinsic
	}
	s := &n.style
	pb := pad_border(s)
	hpb := pb[1] + pb[3]
	res: [2]f32
	if n.style.width.kind == .Px {
		v := s.width.v + (s.box_content ? hpb : 0)
		res = {v, v}
	} else {
		mn, mx: f32
		switch n.kind {
		case .Text:
			pr := &ctx.paras[n.para]
			paragraph_shape(pr, &ctx.fonts, &ctx.theme, ctx.frame_alloc)
			mn = pr.min_w
			mx = pr.max_w
		case .Icon:
			v := s.height.kind == .Px ? s.height.v : s.font_size
			mn = v
			mx = v
		case .Image:
			sz := image_size(ctx, n.image)
			v := sz.x
			if s.height.kind == .Px && sz.y > 0 {
				v = s.height.v * sz.x / sz.y
			}
			mn = 0
			mx = v
		case .Custom:
			mn = 0
			mx = 0
		case .Box:
			mn, mx = intrinsic_children(ctx, n)
		}
		if s.aspect > 0 && s.height.kind == .Px {
			v := s.height.v * s.aspect
			mn = v
			mx = v
		}
		res = {mn + hpb, mx + hpb}
		if s.min_w.kind == .Px {
			res.x = max(res.x, s.min_w.v)
			res.y = max(res.y, s.min_w.v)
		}
		if s.max_w.kind == .Px {
			res.x = min(res.x, s.max_w.v)
			res.y = min(res.y, s.max_w.v)
		}
	}
	n.intrinsic = res
	n.flags += {.Measured_Intrinsic}
	return res
}

@(private)
outer_h :: proc "contextless" (s: ^Style) -> f32 {
	return s.margin[1] + s.margin[3]
}

@(private)
intrinsic_children :: proc(ctx: ^Context, n: ^Node) -> (mn, mx: f32) {
	s := &n.style
	if is_flex(s.display) {
		row := s.flex_dir == .Row || s.flex_dir == .Row_Reverse
		count := 0
		for c := n.first; c >= 0; c = ctx.nodes[c].next {
			cn := &ctx.nodes[c]
			if !in_flow(cn) {
				continue
			}
			iw := intrinsic(ctx, c)
			m := outer_h(&cn.style)
			if row {
				mx += iw.y + m
				if s.flex_wrap == .No_Wrap {
					mn += (cn.style.shrink > 0 ? iw.x : iw.y) + m
				} else {
					mn = max(mn, iw.x + m)
				}
			} else {
				mx = max(mx, iw.y + m)
				mn = max(mn, iw.x + m)
			}
			count += 1
		}
		if row && count > 1 {
			mx += s.gap[1] * f32(count - 1)
			if s.flex_wrap == .No_Wrap {
				mn += s.gap[1] * f32(count - 1)
			}
		}
		return
	}
	if is_grid(s.display) {
		cols := int(s.grid_cols.count)
		if cols == 0 {
			cols = 1
		}
		colmax: [MAX_TRACKS]f32
		colmin: [MAX_TRACKS]f32
		i := 0
		for c := n.first; c >= 0; c = ctx.nodes[c].next {
			cn := &ctx.nodes[c]
			if !in_flow(cn) {
				continue
			}
			iw := intrinsic(ctx, c)
			span := int(max(cn.style.col_span, 1))
			if cn.style.col_span < 0 {
				span = cols
			}
			col := i % cols
			if cn.style.col_start > 0 {
				col = int(cn.style.col_start - 1) % cols
			}
			if span == 1 {
				colmax[col] = max(colmax[col], iw.y)
				colmin[col] = max(colmin[col], iw.x)
			}
			i += span
		}
		for k in 0 ..< cols {
			t := s.grid_cols.tracks[k]
			if s.grid_cols.count > 0 && t.kind == .Px {
				mx += t.v
				mn += t.v
			} else {
				mx += colmax[k]
				mn += t.kind == .Fr ? 0 : colmin[k]
			}
		}
		if cols > 1 {
			mx += s.gap[1] * f32(cols - 1)
			mn += s.gap[1] * f32(cols - 1)
		}
		return
	}
	// block flow: inline runs add up, blocks stack
	run_max: f32 = 0
	for c := n.first; c >= 0; c = ctx.nodes[c].next {
		cn := &ctx.nodes[c]
		if !in_flow(cn) {
			continue
		}
		iw := intrinsic(ctx, c)
		m := outer_h(&cn.style)
		if is_inline_level(cn.style.display) {
			run_max += iw.y + m
			mn = max(mn, iw.x + m)
		} else {
			mx = max(mx, run_max)
			run_max = 0
			mx = max(mx, iw.y + m)
			mn = max(mn, iw.x + m)
		}
	}
	mx = max(mx, run_max)
	return
}

// ---------------------------------------------------------------------------
// Box layout
// ---------------------------------------------------------------------------

// avail:  space available for the border box (INF = unbounded)
// forced: imposed border-box size per axis (-1 = none)
// cb:     containing block size for percentages (INF = indefinite)
layout_box :: proc(ctx: ^Context, ni: i32, avail: [2]f32, forced: [2]f32, cb: [2]f32, final: bool) -> [2]f32 {
	n := &ctx.nodes[ni]
	if !final {
		key := [5]f32{avail.x, forced.x, forced.y, cb.x, cb.y}
		for i in 0 ..< int(n.mcache_n) {
			if n.mcache[i].key == key {
				return n.mcache[i].size
			}
		}
		size := layout_box_impl(ctx, ni, avail, forced, cb, false)
		n = &ctx.nodes[ni]
		slot := int(n.mcache_n) % 4
		n.mcache[slot] = {key, size}
		if n.mcache_n < 4 {
			n.mcache_n += 1
		} else {
			// rotate: keep most recent at a moving slot
			n.mcache_n = 4
		}
		return size
	}
	return layout_box_impl(ctx, ni, avail, forced, cb, true)
}

@(private)
layout_box_impl :: proc(ctx: ^Context, ni: i32, avail: [2]f32, forced: [2]f32, cb: [2]f32, final: bool) -> [2]f32 {
	n := &ctx.nodes[ni]
	s := &n.style
	pb := pad_border(s)
	hpb := pb[1] + pb[3]
	vpb := pb[0] + pb[2]
	extra_w: f32 = s.box_content ? hpb : 0
	extra_h: f32 = s.box_content ? vpb : 0

	// height first if definite (needed for aspect-ratio)
	h: f32
	h_def := false
	if forced.y >= 0 {
		h = forced.y
		h_def = true
	} else if v, ok := resolve(ctx, s.height, cb.y); ok {
		h = v + extra_h
		h_def = true
	}

	w: f32
	w_def := false
	if forced.x >= 0 {
		w = forced.x
		w_def = true
	} else if v, ok := resolve(ctx, s.width, cb.x); ok {
		w = v + extra_w
		w_def = true
	} else if s.aspect > 0 && h_def {
		w = h * s.aspect
		w_def = true
	} else if n.kind == .Image && h_def {
		sz := image_size(ctx, n.image)
		if sz.y > 0 {
			w = h * sz.x / sz.y
			w_def = true
		}
	}
	if !w_def {
		iw := intrinsic(ctx, ni)
		#partial switch s.width.kind {
		case .Min_Content:
			w = iw.x
		case .Max_Content:
			w = iw.y
		case:
			w = min(iw.y, max(iw.x, avail.x))
		}
	}
	w = clamp_axis(ctx, w, s.min_w, s.max_w, cb.x, extra_w)
	if !h_def && s.aspect > 0 {
		h = w / s.aspect
		h_def = true
	}
	if !h_def && n.kind == .Image {
		sz := image_size(ctx, n.image)
		if sz.x > 0 {
			h = (w - hpb) * sz.y / sz.x + vpb
			h_def = true
		}
	}
	inner_w := max(0, w - hpb)

	content: [2]f32
	if h_def {
		h = clamp_axis(ctx, h, s.min_h, s.max_h, cb.y, extra_h)
		inner_h := max(0, h - vpb)
		content = layout_content(ctx, ni, inner_w, inner_h, inner_h, final)
	} else {
		mc := layout_content(ctx, ni, inner_w, INF, INF, false)
		h = clamp_axis(ctx, mc.y + vpb, s.min_h, s.max_h, cb.y, extra_h)
		if final {
			inner_h := max(0, h - vpb)
			content = layout_content(ctx, ni, inner_w, inner_h, INF, true)
		} else {
			content = mc
		}
	}
	n = &ctx.nodes[ni]
	size := [2]f32{w, h}
	if final {
		n.size = size
		n.content = content + {pb[1] + pb[3], pb[0] + pb[2]}
		layout_absolute_children(ctx, ni)
		n = &ctx.nodes[ni]
		if n.state != nil {
			sx := is_scroll(s.overflow_x)
			sy := is_scroll(s.overflow_y)
			cw := n.size.x - s.border_w[1] - s.border_w[3]
			ch := n.size.y - s.border_w[0] - s.border_w[2]
			n.state.scroll_max = {sx ? max(0, n.content.x - cw) : 0, sy ? max(0, n.content.y - ch) : 0}
			if sx {
				n.flags += {.Scroll_X}
			}
			if sy {
				n.flags += {.Scroll_Y}
			}
		}
	}
	return size
}

// Lays out children inside the content box. Returns the content extent.
@(private)
layout_content :: proc(ctx: ^Context, ni: i32, inner_w, inner_h: f32, cb_h: f32, final: bool) -> [2]f32 {
	n := &ctx.nodes[ni]
	switch n.kind {
	case .Text:
		pr := &ctx.paras[n.para]
		paragraph_shape(pr, &ctx.fonts, &ctx.theme, ctx.frame_alloc)
		wrap_w := inner_w
		paragraph_layout(pr, &ctx.fonts, wrap_w)
		if final && len(pr.lines) > 0 {
			n.baseline = pr.lines[0].baseline + n.style.padding[0] + n.style.border_w[0]
		}
		return {pr.width, pr.height}
	case .Icon:
		return {inner_w, n.style.font_size}
	case .Image, .Custom:
		return {inner_w, 0}
	case .Box:
	}
	s := &n.style
	if n.first < 0 {
		return {0, 0}
	}
	if is_flex(s.display) {
		return layout_flex(ctx, ni, inner_w, inner_h, cb_h, final)
	}
	if is_grid(s.display) {
		return layout_grid(ctx, ni, inner_w, inner_h, cb_h, final)
	}
	return layout_block(ctx, ni, inner_w, inner_h, cb_h, final)
}

// ---------------------------------------------------------------------------
// Block flow
// ---------------------------------------------------------------------------

@(private)
Inline_Item :: struct {
	ni:   i32,
	size: [2]f32,
	base: f32, // baseline from border-box top
	x:    f32,
}

// Baseline used for inline-level boxes: first text line for text, bottom edge otherwise.
// Computed the same way in measure and final passes so both agree on line heights.
@(private)
inline_baseline :: proc(ctx: ^Context, ni: i32, size: [2]f32) -> f32 {
	n := &ctx.nodes[ni]
	if n.kind == .Text && n.para >= 0 {
		pr := &ctx.paras[n.para]
		if len(pr.lines) > 0 {
			pb := pad_border(&n.style)
			return pr.lines[0].baseline + pb[0]
		}
	}
	return size.y
}

@(private)
layout_block :: proc(ctx: ^Context, ni: i32, inner_w, inner_h: f32, cb_h: f32, final: bool) -> [2]f32 {
	n := &ctx.nodes[ni]
	pb := pad_border(&n.style)
	origin := [2]f32{pb[3], pb[0]}
	cb := [2]f32{inner_w, cb_h}
	y: f32 = 0
	max_x: f32 = 0
	first_baseline: f32 = -1
	align := n.style.text_align

	run := make([dynamic]Inline_Item, 0, 8, context.temp_allocator)
	run_x: f32 = 0

	flush :: proc(ctx: ^Context, run: ^[dynamic]Inline_Item, y: ^f32, run_x: ^f32, origin: [2]f32, final: bool, align: Text_Align, inner_w: f32, max_x: ^f32) {
		if len(run) == 0 {
			return
		}
		base: f32 = 0
		for it in run {
			base = max(base, it.base + ctx.nodes[it.ni].style.margin[0])
		}
		line_h: f32 = 0
		for it in run {
			m := ctx.nodes[it.ni].style.margin
			off := base - it.base - m[0]
			line_h = max(line_h, off + it.size.y + m[0] + m[2])
		}
		shift: f32 = 0
		if align == .Center {
			shift = (inner_w - run_x^) / 2
		} else if align == .Right || align == .End {
			shift = inner_w - run_x^
		}
		if final {
			for it in run {
				cn := &ctx.nodes[it.ni]
				off := base - it.base - cn.style.margin[0]
				cn.pos = origin + {it.x + shift, y^ + off + cn.style.margin[0]}
			}
		}
		max_x^ = max(max_x^, run_x^)
		y^ += line_h
		clear(run)
		run_x^ = 0
	}

	for c := n.first; c >= 0; c = ctx.nodes[c].next {
		cn := &ctx.nodes[c]
		if !in_flow(cn) {
			continue
		}
		cs := &cn.style
		m := cs.margin
		if is_inline_level(cs.display) {
			avail := max(0, inner_w - m[1] - m[3])
			sz := layout_box(ctx, c, {avail, INF}, {-1, -1}, cb, final)
			ow := sz.x + m[1] + m[3]
			if run_x > 0 && run_x + ow > inner_w + 0.01 {
				flush(ctx, &run, &y, &run_x, origin, final, align, inner_w, &max_x)
			}
			append(&run, Inline_Item{ni = c, size = sz, base = inline_baseline(ctx, c, sz), x = run_x + m[3]})
			run_x += ow
			continue
		}
		flush(ctx, &run, &y, &run_x, origin, final, align, inner_w, &max_x)
		cn = &ctx.nodes[c]
		// block-level child: stretch unless width specified
		avail_w := max(0, inner_w - m[1] - m[3])
		forced := [2]f32{-1, -1}
		w_auto := cs.width.kind == .Auto
		if w_auto && cs.aspect == 0 && cn.kind != .Image {
			forced.x = avail_w
		}
		sz := layout_box(ctx, c, {avail_w, INF}, forced, cb, final)
		cn = &ctx.nodes[c]
		x := m[3]
		free := inner_w - sz.x - m[1] - m[3]
		if cs.margin_auto[1] && cs.margin_auto[3] {
			x = m[3] + max(free, 0) / 2
		} else if cs.margin_auto[3] {
			x = m[3] + max(free, 0)
		}
		y += m[0]
		if final {
			cn.pos = origin + {x, y}
			if first_baseline < 0 && cn.baseline >= 0 {
				first_baseline = y + cn.baseline + origin.y
			}
		}
		y += sz.y + m[2]
		max_x = max(max_x, x + sz.x + m[1])
	}
	flush(ctx, &run, &y, &run_x, origin, final, align, inner_w, &max_x)
	if final {
		n = &ctx.nodes[ni]
		if first_baseline >= 0 {
			n.baseline = first_baseline
		} else if n.first >= 0 {
			fc := &ctx.nodes[n.first]
			if fc.baseline >= 0 {
				n.baseline = fc.pos.y + fc.baseline
			}
		}
	}
	return {max_x, y}
}

// ---------------------------------------------------------------------------
// Flexbox
// ---------------------------------------------------------------------------

@(private)
Flex_Item :: struct {
	ni:        i32,
	order:     i32,
	seq:       int,
	base:      f32,
	hyp:       f32,
	target:    f32,
	min_main:  f32,
	max_main:  f32,
	frozen:    bool,
	m_main:    [2]f32,
	m_cross:   [2]f32,
	auto_main: [2]bool,
	auto_cross: [2]bool,
	cross:     f32,
	stretch:   bool,
	align:     Align,
	baseline:  f32,
}

@(private)
Flex_Line :: struct {
	first, count: int,
	cross:        f32,
	pos:          f32,
	baseline:     f32,
}

@(private)
layout_flex :: proc(ctx: ^Context, ni: i32, inner_w, inner_h: f32, cb_h: f32, final: bool) -> [2]f32 {
	n := &ctx.nodes[ni]
	s := n.style // copy (node array may not move, but keep it simple)
	pb := pad_border(&s)
	origin := [2]f32{pb[3], pb[0]}
	row := s.flex_dir == .Row || s.flex_dir == .Row_Reverse
	reverse := s.flex_dir == .Row_Reverse || s.flex_dir == .Column_Reverse
	main_size := row ? inner_w : inner_h
	cross_size := row ? inner_h : inner_w
	main_def := main_size < INF * 0.5
	cross_def := cross_size < INF * 0.5
	gap_main := row ? s.gap[1] : s.gap[0]
	gap_cross := row ? s.gap[0] : s.gap[1]
	cb := [2]f32{inner_w, cb_h}

	items := make([dynamic]Flex_Item, 0, 16, context.temp_allocator)
	seq := 0
	for c := n.first; c >= 0; c = ctx.nodes[c].next {
		cn := &ctx.nodes[c]
		if !in_flow(cn) {
			continue
		}
		append(&items, Flex_Item{ni = c, order = cn.style.order, seq = seq})
		seq += 1
	}
	if len(items) == 0 {
		return {0, 0}
	}
	slice.stable_sort_by(items[:], proc(a, b: Flex_Item) -> bool {
		return a.order < b.order
	})

	// 1. flex base sizes
	for &it in items {
		cn := &ctx.nodes[it.ni]
		cs := &cn.style
		m := cs.margin
		if row {
			it.m_main = {m[3], m[1]}
			it.m_cross = {m[0], m[2]}
			it.auto_main = {cs.margin_auto[3], cs.margin_auto[1]}
			it.auto_cross = {cs.margin_auto[0], cs.margin_auto[2]}
		} else {
			it.m_main = {m[0], m[2]}
			it.m_cross = {m[3], m[1]}
			it.auto_main = {cs.margin_auto[0], cs.margin_auto[2]}
			it.auto_cross = {cs.margin_auto[3], cs.margin_auto[1]}
		}
		it.align = cs.align_self == .Auto ? s.align_items : cs.align_self
		cross_auto := row ? cs.height.kind == .Auto : cs.width.kind == .Auto
		it.stretch = it.align == .Stretch && cross_auto && !it.auto_cross[0] && !it.auto_cross[1] && cs.aspect == 0
		cpb := pad_border(cs)
		main_pb := row ? cpb[1] + cpb[3] : cpb[0] + cpb[2]
		extra: f32 = cs.box_content ? main_pb : 0

		base: f32
		have := false
		if cs.basis.kind != .Auto {
			if v, ok := resolve(ctx, cs.basis, main_size); ok {
				base = v + extra
				have = true
			}
		}
		if !have {
			msz := row ? cs.width : cs.height
			if v, ok := resolve(ctx, msz, row ? main_size : cb_h); ok {
				base = v + extra
				have = true
			}
		}
		if !have {
			if row {
				iw := intrinsic(ctx, it.ni)
				base = iw.y
				if cs.aspect > 0 && cross_def && it.stretch {
					base = (cross_size - it.m_cross[0] - it.m_cross[1]) * cs.aspect
				}
			} else {
				cw: f32 = -1
				if it.stretch && cross_def {
					cw = max(0, cross_size - it.m_cross[0] - it.m_cross[1])
				}
				avail_c := cross_def ? cross_size - it.m_cross[0] - it.m_cross[1] : INF
				sz := layout_box(ctx, it.ni, {avail_c, INF}, {cw, -1}, cb, false)
				base = sz.y
			}
		}
		it.base = base
		// min/max main
		mn_s := row ? cs.min_w : cs.min_h
		mx_s := row ? cs.max_w : cs.max_h
		cbm := row ? main_size : cb_h
		it.min_main = 0
		if v, ok := resolve(ctx, mn_s, cbm); ok {
			it.min_main = v + extra
		} else if mn_s.kind == .Auto {
			// automatic minimum size: content-based for items with visible overflow
			ov := row ? cs.overflow_x : cs.overflow_y
			if ov == .Visible {
				if row {
					iw := intrinsic(ctx, it.ni)
					spec := iw.x
					if v, ok2 := resolve(ctx, cs.width, main_size); ok2 {
						spec = min(spec, v + extra)
					}
					it.min_main = spec
				} else {
					if v, ok2 := resolve(ctx, cs.height, cb_h); ok2 {
						it.min_main = min(base, v + extra)
					} else {
						it.min_main = cs.basis.kind == .Percent && cs.basis.v == 0 ? 0 : base
						if cs.basis.kind != .Auto || cs.grow > 0 || cs.shrink > 0 {
							// content min for column flex items: their content height
							cw: f32 = -1
							if it.stretch && cross_def {
								cw = max(0, cross_size - it.m_cross[0] - it.m_cross[1])
							}
							avail_c := cross_def ? cross_size - it.m_cross[0] - it.m_cross[1] : INF
							sz := layout_box(ctx, it.ni, {avail_c, INF}, {cw, -1}, cb, false)
							it.min_main = sz.y
						}
					}
				}
			}
		}
		it.max_main = INF
		if v, ok := resolve(ctx, mx_s, cbm); ok && mx_s.kind != .Auto {
			it.max_main = v + extra
		}
		it.hyp = clamp(base, it.min_main, max(it.max_main, it.min_main))
	}

	// 2. lines
	lines := make([dynamic]Flex_Line, 0, 4, context.temp_allocator)
	{
		start := 0
		used: f32 = 0
		for it, i in items {
			outer := it.hyp + it.m_main[0] + it.m_main[1]
			if s.flex_wrap != .No_Wrap && main_def && i > start && used + gap_main + outer > main_size + 0.01 {
				append(&lines, Flex_Line{first = start, count = i - start})
				start = i
				used = 0
			}
			if i > start {
				used += gap_main
			}
			used += outer
		}
		append(&lines, Flex_Line{first = start, count = len(items) - start})
	}

	// 3. resolve flexible lengths per line
	for &ln in lines {
		li := items[ln.first:ln.first + ln.count]
		if !main_def {
			for &it in li {
				it.target = it.hyp
			}
			continue
		}
		gaps := gap_main * f32(max(len(li) - 1, 0))
		sum_hyp: f32 = 0
		for it in li {
			sum_hyp += it.hyp + it.m_main[0] + it.m_main[1]
		}
		growing := sum_hyp + gaps < main_size
		for &it in li {
			cs := &ctx.nodes[it.ni].style
			it.frozen = growing ? cs.grow == 0 : cs.shrink == 0
			if growing && it.base > it.hyp {
				it.frozen = true
			}
			if !growing && it.base < it.hyp {
				it.frozen = true
			}
			it.target = it.hyp
		}
		for _ in 0 ..< 4 {
			free := main_size - gaps
			total: f32 = 0
			for it in li {
				cs := &ctx.nodes[it.ni].style
				free -= it.m_main[0] + it.m_main[1]
				if it.frozen {
					free -= it.target
				} else {
					free -= it.base
					total += growing ? cs.grow : cs.shrink * it.base
				}
			}
			if total == 0 {
				break
			}
			if growing {
				// sum of grow < 1 only distributes that fraction
				gsum: f32 = 0
				for it in li {
					if !it.frozen {
						gsum += ctx.nodes[it.ni].style.grow
					}
				}
				if gsum < 1 {
					free *= gsum
				}
			}
			violation: f32 = 0
			for &it in li {
				if it.frozen {
					continue
				}
				cs := &ctx.nodes[it.ni].style
				share: f32
				if growing {
					share = free * cs.grow / total
				} else {
					share = free * (cs.shrink * it.base) / total
				}
				v := it.base + share
				cl := clamp(v, it.min_main, max(it.max_main, it.min_main))
				violation += cl - v
				it.target = cl
			}
			if abs(violation) < 0.01 {
				break
			}
			for &it in li {
				if it.frozen {
					continue
				}
				v := it.target
				if violation > 0 && v <= it.min_main + 0.001 {
					it.frozen = true
				} else if violation < 0 && v >= it.max_main - 0.001 {
					it.frozen = true
				}
			}
		}
	}

	// 4. cross sizes
	single := len(lines) == 1 && s.flex_wrap == .No_Wrap
	for &ln in lines {
		li := items[ln.first:ln.first + ln.count]
		lc: f32 = 0
		lb: f32 = 0
		for &it in li {
			cn := &ctx.nodes[it.ni]
			cs := &cn.style
			if row {
				avail_c := cross_def ? cross_size - it.m_cross[0] - it.m_cross[1] : INF
				fy: f32 = -1
				if it.stretch && single && cross_def {
					fy = max(0, avail_c)
				}
				sz := layout_box(ctx, it.ni, {it.target, avail_c}, {it.target, fy}, cb, false)
				it.cross = sz.y
			} else {
				avail_c := cross_def ? cross_size - it.m_cross[0] - it.m_cross[1] : INF
				if it.stretch && cross_def {
					it.cross = max(0, avail_c)
				} else {
					sz := layout_box(ctx, it.ni, {avail_c, it.target}, {-1, it.target}, cb, false)
					it.cross = sz.x
				}
			}
			_ = cs
			lc = max(lc, it.cross + it.m_cross[0] + it.m_cross[1])
			if it.align == .Baseline && row {
				it.baseline = item_baseline(ctx, &it, cb)
				lb = max(lb, it.baseline + it.m_cross[0])
			}
		}
		if single && cross_def {
			lc = cross_size
		}
		// baseline-aligned items may extend the line
		if lb > 0 {
			for it in li {
				if it.align == .Baseline {
					lc = max(lc, lb - it.baseline - it.m_cross[0] + it.cross + it.m_cross[0] + it.m_cross[1])
				}
			}
		}
		ln.cross = lc
		ln.baseline = lb
	}

	total_cross: f32 = 0
	for ln, i in lines {
		total_cross += ln.cross
		if i > 0 {
			total_cross += gap_cross
		}
	}

	// 5. align-content
	{
		free := cross_def ? cross_size - total_cross : 0
		pos: f32 = 0
		between: f32 = 0
		nl := f32(len(lines))
		if cross_def && !single && len(lines) >= 1 {
			switch s.align_content {
			case .Normal, .Stretch:
				if free > 0 {
					add := free / nl
					for &ln in lines {
						ln.cross += add
					}
				}
			case .Start:
			case .End:
				pos = free
			case .Center:
				pos = free / 2
			case .Between:
				if nl > 1 {
					between = max(free, 0) / (nl - 1)
				}
			case .Around:
				between = max(free, 0) / nl
				pos = between / 2
			case .Evenly:
				between = max(free, 0) / (nl + 1)
				pos = between
			}
		}
		for &ln in lines {
			ln.pos = pos
			pos += ln.cross + gap_cross + between
		}
	}

	// 6. main-axis placement + final layout
	max_main: f32 = 0
	for &ln in lines {
		li := items[ln.first:ln.first + ln.count]
		used: f32 = 0
		auto_count := 0
		for it, i in li {
			used += it.target + it.m_main[0] + it.m_main[1]
			if i > 0 {
				used += gap_main
			}
			if it.auto_main[0] {
				auto_count += 1
			}
			if it.auto_main[1] {
				auto_count += 1
			}
		}
		free := main_def ? main_size - used : 0
		pos: f32 = 0
		between: f32 = 0
		auto_share: f32 = 0
		cnt := f32(len(li))
		if auto_count > 0 && free > 0 {
			auto_share = free / f32(auto_count)
		} else {
			j := s.justify
			if free < 0 && (j == .Between || j == .Around || j == .Evenly) {
				j = .Start
			}
			switch j {
			case .Normal, .Start, .Stretch:
			case .End:
				pos = free
			case .Center:
				pos = free / 2
			case .Between:
				if cnt > 1 {
					between = free / (cnt - 1)
				}
			case .Around:
				between = free / cnt
				pos = between / 2
			case .Evenly:
				between = free / (cnt + 1)
				pos = between
			}
		}
		for &it, i in li {
			if i > 0 {
				pos += gap_main + between
			}
			if it.auto_main[0] {
				pos += auto_share
			}
			pos += it.m_main[0]
			main_pos := pos
			pos += it.target + it.m_main[1]
			if it.auto_main[1] {
				pos += auto_share
			}
			// cross
			cn := &ctx.nodes[it.ni]
			cs := &cn.style
			cross_len := it.cross
			if it.stretch {
				cross_len = max(0, ln.cross - it.m_cross[0] - it.m_cross[1])
				mn_s := row ? cs.min_h : cs.min_w
				mx_s := row ? cs.max_h : cs.max_w
				cross_len = clamp_axis(ctx, cross_len, mn_s, mx_s, row ? cb_h : inner_w, 0)
			}
			cfree := ln.cross - cross_len - it.m_cross[0] - it.m_cross[1]
			coff: f32 = 0
			if it.auto_cross[0] && it.auto_cross[1] {
				coff = cfree / 2
			} else if it.auto_cross[0] {
				coff = cfree
			} else if it.auto_cross[1] {
				coff = 0
			} else {
				#partial switch it.align {
				case .End:
					coff = cfree
				case .Center:
					coff = cfree / 2
				case .Baseline:
					if row {
						coff = ln.baseline - it.baseline - it.m_cross[0]
					}
				}
			}
			coff += it.m_cross[0]
			if final {
				fw, fh: f32
				if row {
					fw = it.target
					fh = cross_len
				} else {
					fw = cross_len
					fh = it.target
				}
				layout_box(ctx, it.ni, {fw, fh}, {fw, fh}, cb, true)
				cn = &ctx.nodes[it.ni]
				mp := main_pos
				if reverse {
					total_main := main_def ? main_size : used
					mp = total_main - main_pos - it.target
				}
				cp := ln.pos + coff
				if s.flex_wrap == .Wrap_Reverse && cross_def {
					cp = cross_size - cp - cross_len
				}
				if row {
					cn.pos = origin + {mp, cp}
				} else {
					cn.pos = origin + {cp, mp}
				}
			}
		}
		max_main = max(max_main, pos)
	}

	if final {
		n = &ctx.nodes[ni]
		// first baseline from the first item of the first line
		if len(items) > 0 {
			fc := &ctx.nodes[items[0].ni]
			if fc.baseline >= 0 {
				n.baseline = fc.pos.y + fc.baseline
			}
		}
	}
	if row {
		return {max_main, total_cross}
	}
	return {total_cross, max_main}
}

@(private)
item_baseline :: proc(ctx: ^Context, it: ^Flex_Item, cb: [2]f32) -> f32 {
	cn := &ctx.nodes[it.ni]
	if cn.kind == .Text {
		pr := &ctx.paras[cn.para]
		paragraph_shape(pr, &ctx.fonts, &ctx.theme, ctx.frame_alloc)
		pb := pad_border(&cn.style)
		paragraph_layout(pr, &ctx.fonts, max(0, it.target - pb[1] - pb[3]))
		if len(pr.lines) > 0 {
			return pr.lines[0].baseline + pb[0]
		}
	}
	// first text descendant
	for c := cn.first; c >= 0; c = ctx.nodes[c].next {
		cc := &ctx.nodes[c]
		if cc.kind == .Text {
			pr := &ctx.paras[cc.para]
			paragraph_shape(pr, &ctx.fonts, &ctx.theme, ctx.frame_alloc)
			if len(pr.spans) > 0 {
				sp := &pr.spans[0]
				f := &ctx.fonts.faces[sp.face]
				lh := line_height_px(&sp.style)
				pb := pad_border(&cn.style)
				return pb[0] + (lh - (f.ascent + f.descent) * sp.size) / 2 + f.ascent * sp.size
			}
		}
	}
	return it.cross
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

@(private)
Grid_Item :: struct {
	ni:       i32,
	col, row: int,
	cspan:    int,
	rspan:    int,
}

@(private)
layout_grid :: proc(ctx: ^Context, ni: i32, inner_w, inner_h: f32, cb_h: f32, final: bool) -> [2]f32 {
	n := &ctx.nodes[ni]
	s := n.style
	pb := pad_border(&s)
	origin := [2]f32{pb[3], pb[0]}
	cb := [2]f32{inner_w, cb_h}
	col_flow := s.grid_flow == .Column || s.grid_flow == .Column_Dense

	ncols := int(s.grid_cols.count)
	nrows_explicit := int(s.grid_rows.count)
	items := make([dynamic]Grid_Item, 0, 16, context.temp_allocator)
	for c := n.first; c >= 0; c = ctx.nodes[c].next {
		cn := &ctx.nodes[c]
		if !in_flow(cn) {
			continue
		}
		append(&items, Grid_Item{ni = c})
	}
	if len(items) == 0 {
		return {0, 0}
	}
	if ncols == 0 && !col_flow {
		// implicit columns from explicit placements
		ncols = 1
		for it in items {
			cs := &ctx.nodes[it.ni].style
			if cs.col_start > 0 {
				ncols = max(ncols, int(cs.col_start) + int(max(cs.col_span, 1)) - 1)
			}
			if cs.col_end > 1 {
				ncols = max(ncols, int(cs.col_end) - 1)
			}
		}
	}
	nrows := max(nrows_explicit, 1)

	// placement with an occupancy grid
	MAXR :: 512
	occ := make(map[[2]int]bool, 64, context.temp_allocator)
	cursor := [2]int{0, 0} // (row, col) for row flow, (col, row) for col flow
	max_col := ncols
	max_row := 0
	for &it in items {
		cs := &ctx.nodes[it.ni].style
		cspan := int(cs.col_span)
		if cspan < 0 {
			cspan = max(ncols, 1)
		}
		if cspan == 0 {
			cspan = 1
		}
		rspan := int(cs.row_span)
		if rspan < 0 {
			rspan = max(nrows, 1)
		}
		if rspan == 0 {
			rspan = 1
		}
		if cs.col_start > 0 && cs.col_end > cs.col_start {
			cspan = int(cs.col_end - cs.col_start)
		} else if cs.col_start == 0 && cs.col_end > 1 && cs.col_span > 0 {
			// col-end-N with span: start = end - span
		}
		if cs.row_start > 0 && cs.row_end > cs.row_start {
			rspan = int(cs.row_end - cs.row_start)
		}
		fixed_col := cs.col_start > 0 ? int(cs.col_start) - 1 : -1
		if fixed_col < 0 && cs.col_end > 1 {
			fixed_col = max(0, int(cs.col_end) - 1 - cspan)
		}
		fixed_row := cs.row_start > 0 ? int(cs.row_start) - 1 : -1
		if fixed_row < 0 && cs.row_end > 1 {
			fixed_row = max(0, int(cs.row_end) - 1 - rspan)
		}
		fits :: proc(occ: ^map[[2]int]bool, r, c, rs, cs: int) -> bool {
			for rr in r ..< r + rs {
				for cc in c ..< c + cs {
					if occ[{rr, cc}] {
						return false
					}
				}
			}
			return true
		}
		if !col_flow {
			cols := max(ncols, 1)
			cspan = min(cspan, cols)
			r, c: int
			if fixed_col >= 0 && fixed_row >= 0 {
				r = fixed_row
				c = fixed_col
			} else if fixed_col >= 0 {
				r = fixed_row >= 0 ? fixed_row : 0
				for !fits(&occ, r, fixed_col, rspan, cspan) && r < MAXR {
					r += 1
				}
				c = fixed_col
			} else {
				r = fixed_row >= 0 ? fixed_row : cursor[0]
				c = fixed_row >= 0 ? 0 : cursor[1]
				for r < MAXR {
					if c + cspan > cols {
						c = 0
						r += 1
						continue
					}
					if fits(&occ, r, c, rspan, cspan) {
						break
					}
					c += 1
				}
				if fixed_row < 0 {
					cursor = {r, c + cspan}
				}
			}
			it.row = r
			it.col = c
		} else {
			rows := max(nrows, 1)
			rspan = min(rspan, rows)
			c := fixed_col >= 0 ? fixed_col : cursor[0]
			r := fixed_row >= 0 ? fixed_row : cursor[1]
			for c < MAXR {
				if r + rspan > rows {
					r = 0
					c += 1
					continue
				}
				if fits(&occ, r, c, rspan, cspan) {
					break
				}
				r += 1
			}
			cursor = {c, r + rspan}
			it.row = r
			it.col = c
		}
		it.cspan = cspan
		it.rspan = rspan
		for rr in it.row ..< it.row + rspan {
			for cc in it.col ..< it.col + cspan {
				occ[{rr, cc}] = true
			}
		}
		max_col = max(max_col, it.col + cspan)
		max_row = max(max_row, it.row + rspan)
	}
	ncols = max(max_col, 1)
	nrows = max(max_row, nrows_explicit, 1)

	track_of :: proc(t: ^Grid_Template, auto_t: Track, i: int) -> Track {
		if i < int(t.count) {
			return t.tracks[i]
		}
		return auto_t
	}

	// column sizes
	colw := make([]f32, ncols, context.temp_allocator)
	gap_x := s.gap[1]
	gap_y := s.gap[0]
	avail_w := inner_w - gap_x * f32(ncols - 1)
	fr_total: f32 = 0
	fixed_sum: f32 = 0
	for ci in 0 ..< ncols {
		t := track_of(&s.grid_cols, s.auto_cols, ci)
		switch t.kind {
		case .Px:
			colw[ci] = t.v
		case .Percent:
			colw[ci] = inner_w < INF * 0.5 ? inner_w * t.v / 100 : 0
		case .Fr:
			fr_total += t.v
			continue
		case .Auto, .Min_Content, .Max_Content:
			w: f32 = 0
			for it in items {
				if it.col == ci && it.cspan == 1 {
					iw := intrinsic(ctx, it.ni)
					m := outer_h(&ctx.nodes[it.ni].style)
					w = max(w, (t.kind == .Min_Content ? iw.x : iw.y) + m)
				}
			}
			colw[ci] = w
		}
		fixed_sum += colw[ci]
	}
	if fr_total > 0 {
		if inner_w < INF * 0.5 {
			rest := max(0, avail_w - fixed_sum)
			// auto tracks shrink if fr tracks... (keep simple: fr share the rest)
			for ci in 0 ..< ncols {
				t := track_of(&s.grid_cols, s.auto_cols, ci)
				if t.kind == .Fr {
					colw[ci] = rest * t.v / fr_total
				}
			}
		} else {
			// indefinite: size fr tracks to max-content, equalized per fr unit
			unit: f32 = 0
			for it in items {
				t := track_of(&s.grid_cols, s.auto_cols, it.col)
				if t.kind == .Fr && it.cspan == 1 {
					iw := intrinsic(ctx, it.ni)
					unit = max(unit, (iw.y + outer_h(&ctx.nodes[it.ni].style)) / max(t.v, 0.01))
				}
			}
			for ci in 0 ..< ncols {
				t := track_of(&s.grid_cols, s.auto_cols, ci)
				if t.kind == .Fr {
					colw[ci] = unit * t.v
				}
			}
		}
	} else if inner_w < INF * 0.5 && s.justify_items == .Stretch {
		// auto tracks expand to fill (CSS: auto tracks stretch when justify-content normal)
		auto_n := 0
		for ci in 0 ..< ncols {
			if track_of(&s.grid_cols, s.auto_cols, ci).kind == .Auto {
				auto_n += 1
			}
		}
		rest := avail_w - fixed_sum
		if auto_n > 0 && rest > 0 && s.grid_cols.count == 0 {
			for ci in 0 ..< ncols {
				if track_of(&s.grid_cols, s.auto_cols, ci).kind == .Auto {
					colw[ci] += rest / f32(auto_n)
				}
			}
		}
	}
	colx := make([]f32, ncols + 1, context.temp_allocator)
	for ci in 0 ..< ncols {
		colx[ci + 1] = colx[ci] + colw[ci] + (ci < ncols - 1 ? gap_x : 0)
	}
	span_w :: proc(colx: []f32, c, span: int, gap: f32) -> f32 {
		end := min(c + span, len(colx) - 1)
		w := colx[end] - colx[c]
		if end < len(colx) - 1 {
			w -= gap
		}
		return w
	}

	// row sizes
	rowh := make([]f32, nrows, context.temp_allocator)
	row_fr: f32 = 0
	for ri in 0 ..< nrows {
		t := track_of(&s.grid_rows, s.auto_rows, ri)
		if t.kind == .Px {
			rowh[ri] = t.v
		} else if t.kind == .Fr {
			row_fr += t.v
		}
	}
	item_h := make([]f32, len(items), context.temp_allocator)
	for it, k in items {
		cs := &ctx.nodes[it.ni].style
		w := span_w(colx, it.col, it.cspan, gap_x) - cs.margin[1] - cs.margin[3]
		ji := cs.justify_self == .Auto ? s.justify_items : cs.justify_self
		fw: f32 = -1
		if ji == .Stretch && cs.width.kind == .Auto {
			fw = max(0, w)
		}
		sz := layout_box(ctx, it.ni, {max(0, w), INF}, {fw, -1}, {w, INF}, false)
		item_h[k] = sz.y + cs.margin[0] + cs.margin[2]
		if it.rspan == 1 {
			t := track_of(&s.grid_rows, s.auto_rows, it.row)
			if t.kind != .Px && it.row < nrows {
				if t.kind != .Fr || inner_h >= INF * 0.5 {
					rowh[it.row] = max(rowh[it.row], item_h[k])
				}
			}
		}
	}
	// spanning items: grow last spanned row
	for it, k in items {
		if it.rspan > 1 {
			sum: f32 = 0
			for ri in it.row ..< min(it.row + it.rspan, nrows) {
				sum += rowh[ri]
			}
			sum += gap_y * f32(it.rspan - 1)
			if item_h[k] > sum {
				last := min(it.row + it.rspan, nrows) - 1
				rowh[last] += item_h[k] - sum
			}
		}
	}
	if row_fr > 0 && inner_h < INF * 0.5 {
		used: f32 = 0
		for ri in 0 ..< nrows {
			if track_of(&s.grid_rows, s.auto_rows, ri).kind != .Fr {
				used += rowh[ri]
			}
		}
		rest := max(0, inner_h - used - gap_y * f32(nrows - 1))
		for ri in 0 ..< nrows {
			t := track_of(&s.grid_rows, s.auto_rows, ri)
			if t.kind == .Fr {
				rowh[ri] = max(rowh[ri], rest * t.v / row_fr)
			}
		}
	}
	rowy := make([]f32, nrows + 1, context.temp_allocator)
	for ri in 0 ..< nrows {
		rowy[ri + 1] = rowy[ri] + rowh[ri] + (ri < nrows - 1 ? gap_y : 0)
	}

	if final {
		for it in items {
			cn := &ctx.nodes[it.ni]
			cs := &cn.style
			cw := span_w(colx, it.col, it.cspan, gap_x)
			end_r := min(it.row + it.rspan, nrows)
			ch := rowy[end_r] - rowy[it.row] - (end_r < nrows ? gap_y : 0)
			ji := cs.justify_self == .Auto ? s.justify_items : cs.justify_self
			ai := cs.align_self == .Auto ? s.align_items : cs.align_self
			aw := cw - cs.margin[1] - cs.margin[3]
			ah := ch - cs.margin[0] - cs.margin[2]
			fw: f32 = -1
			fh: f32 = -1
			if ji == .Stretch && cs.width.kind == .Auto && cs.aspect == 0 {
				fw = max(0, aw)
			}
			if (ai == .Stretch || ai == .Auto) && cs.height.kind == .Auto && cs.aspect == 0 {
				fh = max(0, ah)
			}
			sz := layout_box(ctx, it.ni, {max(0, aw), max(0, ah)}, {fw, fh}, {cw, ch}, true)
			cn = &ctx.nodes[it.ni]
			x := colx[it.col] + cs.margin[3]
			y := rowy[it.row] + cs.margin[0]
			#partial switch ji {
			case .Center:
				x += (aw - sz.x) / 2
			case .End:
				x += aw - sz.x
			}
			#partial switch ai {
			case .Center:
				y += (ah - sz.y) / 2
			case .End:
				y += ah - sz.y
			}
			cn.pos = origin + {x, y}
		}
	}
	return {colx[ncols], rowy[nrows]}
}

// ---------------------------------------------------------------------------
// Absolute / fixed positioning
// ---------------------------------------------------------------------------

@(private)
layout_absolute_children :: proc(ctx: ^Context, cbi: i32) {
	cbn := &ctx.nodes[cbi]
	is_cb := cbi == 0 || cbn.style.position != .Static
	if !is_cb {
		return
	}
	// find absolute descendants whose containing block is cbi
	// (walk subtree; nodes are stored in creation order so descendants follow cbi)
	end := i32(len(ctx.nodes))
	for i := cbi + 1; i < end; i += 1 {
		an := &ctx.nodes[i]
		if an.cb != cbi || an.style.display == .None {
			continue
		}
		if an.style.position != .Absolute && an.style.position != .Fixed {
			continue
		}
		cbw: f32
		cbh: f32
		bo := [2]f32{cbn.style.border_w[3], cbn.style.border_w[0]}
		if an.style.position == .Fixed {
			cbw = ctx.viewport.x
			cbh = ctx.viewport.y
			bo = {0, 0}
		} else {
			cbw = cbn.size.x - cbn.style.border_w[1] - cbn.style.border_w[3]
			cbh = cbn.size.y - cbn.style.border_w[0] - cbn.style.border_w[2]
		}
		s := &an.style
		l, lok := resolve(ctx, s.inset[3], cbw)
		r, rok := resolve(ctx, s.inset[1], cbw)
		t, tok := resolve(ctx, s.inset[0], cbh)
		b, bok := resolve(ctx, s.inset[2], cbh)
		m := s.margin
		forced := [2]f32{-1, -1}
		if lok && rok && s.width.kind == .Auto {
			forced.x = max(0, cbw - l - r - m[1] - m[3])
		}
		if tok && bok && s.height.kind == .Auto {
			forced.y = max(0, cbh - t - b - m[0] - m[2])
		}
		availw := cbw
		if lok {
			availw -= l
		}
		if rok {
			availw -= r
		}
		sz := layout_box(ctx, i, {max(0, availw - m[1] - m[3]), cbh}, forced, {cbw, cbh}, true)
		an = &ctx.nodes[i]
		x: f32
		y: f32
		if lok {
			x = l + m[3]
			if rok && s.margin_auto[1] && s.margin_auto[3] {
				x = l + (cbw - l - r - sz.x) / 2
			}
		} else if rok {
			x = cbw - r - sz.x - m[1]
		} else {
			// static position approximation: parent's content origin relative to CB
			x = static_offset(ctx, i, cbi).x + m[3]
		}
		if tok {
			y = t + m[0]
			if bok && s.margin_auto[0] && s.margin_auto[2] {
				y = t + (cbh - t - b - sz.y) / 2
			}
		} else if bok {
			y = cbh - b - sz.y - m[2]
		} else {
			y = static_offset(ctx, i, cbi).y + m[0]
		}
		an.abs_set = true
		an.abs_pos = bo + {x, y}
	}
}

@(private)
static_offset :: proc(ctx: ^Context, ni: i32, cbi: i32) -> [2]f32 {
	// offset of the node's parent content box from the CB padding box
	p := ctx.nodes[ni].parent
	off: [2]f32
	if p >= 0 {
		pn := &ctx.nodes[p]
		pb := pad_border(&pn.style)
		off = {pb[3], pb[0]}
		q := p
		for q >= 0 && q != cbi {
			off += ctx.nodes[q].pos
			q = ctx.nodes[q].parent
		}
		cbn := &ctx.nodes[cbi]
		off -= {cbn.style.border_w[3], cbn.style.border_w[0]}
	}
	return off
}

@(private)
_unused_layout :: proc() -> f32 {
	return math.F32_EPSILON
}

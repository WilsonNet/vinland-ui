package vui

import "core:math"
import "core:slice"

// ---------------------------------------------------------------------------
// Draw list. One instanced quad per command; a single uber-shader renders
// rounded boxes (fill/gradient/border), gaussian box shadows, inset shadows,
// atlas glyphs/icons and images. Coordinates are *physical* pixels.
// ---------------------------------------------------------------------------

Cmd_Kind :: enum u32 {
	RRect        = 0,
	Shadow       = 1,
	Inset_Shadow = 2,
	Glyph        = 3,
	Image        = 4,
	Segment      = 5,
	Arc          = 6,
	Area         = 7,
}

// GPU instance layout (15 x vec4). Keep in sync with the backend shader.
Draw_Cmd :: struct {
	size:     [4]f32, // w, h, -, -
	radii:    [4]f32, // tl tr br bl
	fill0:    [4]f32, // color / gradient from / glyph color / image tint
	fill1:    [4]f32, // gradient to   | inset: hole rect (x y w h, local)
	fill2:    [4]f32, // gradient via  | inset: hole radii
	border_w: [4]f32, // t r b l
	border_c: [4]f32,
	grad:     [4]f32, // kind, angle(rad), from_pos, to_pos
	params:   [4]f32, // cmd kind, blur sigma, border style, via_pos (or -1)
	uv:       [4]f32, // atlas/image rect (px or normalized)
	clip:     [4]f32, // x0 y0 x1 y1 (physical, world)
	clip_r:   [4]f32, // clip corner radii (world px)
	xf:       [4]f32, // 2x2 matrix (a b c d), world = M * local + t
	xt:       [4]f32, // t.x t.y, filter index, stripe period
	extra:    [4]f32, // stripe line width, -, -, -
}

Draw_Batch :: struct {
	first: i32,
	count: i32,
	image: Image_Id, // 0 = glyph atlas
}

Draw_List :: struct {
	cmds:      [dynamic]Draw_Cmd,
	batches:   [dynamic]Draw_Batch,
	filters:   [dynamic]Color_Matrix,
	clear:     Color,
	size:      [2]f32, // physical framebuffer size
	atlas_size: [2]f32,
}

draw_list_init :: proc(d: ^Draw_List) {
	d.cmds = make([dynamic]Draw_Cmd, 0, 4096)
	d.batches = make([dynamic]Draw_Batch, 0, 64)
	d.filters = make([dynamic]Color_Matrix, 0, 8)
}

draw_list_destroy :: proc(d: ^Draw_List) {
	delete(d.cmds)
	delete(d.batches)
	delete(d.filters)
}

@(private)
Paint_State :: struct {
	clip:    Rect, // physical world
	clip_r:  [4]f32,
	opacity: f32,
	filter:  i32,
	xf:      Xform, // logical-space absolute transform
}

// Hard cap on instances per frame (~60 MB of instance data). A runaway build loop must not
// be able to allocate unbounded GPU buffers or submit seconds of fill work: a long GPU
// job trips the amdgpu ring timeout and resets the GPU under the desktop compositor.
MAX_DRAW_CMDS :: 1 << 18
// Color-matrix filters per frame; the shaders index a fixed uniform array of this size.
MAX_DRAW_FILTERS :: 16

@(private)
emit :: proc(ctx: ^Context, c: Draw_Cmd, image: Image_Id = 0) {
	d := &ctx.draw
	// Cull quads that cannot produce a fragment (the fragment shader discards everything
	// outside the clip rect anyway). Written so NaN geometry is also dropped.
	{
		kind := u32(c.params.x)
		pad: f32 = 1
		if kind == u32(Cmd_Kind.Shadow) {
			pad = 3 * c.params.y + 2
		} else if kind == u32(Cmd_Kind.Glyph) || kind == u32(Cmd_Kind.Image) || kind == u32(Cmd_Kind.Area) {
			pad = 0
		}
		lx0, ly0 := -pad, -pad
		lx1, ly1 := c.size.x + pad, c.size.y + pad
		a, b, cc, dd := c.xf.x, c.xf.y, c.xf.z, c.xf.w
		ex := abs(a) * (lx1 - lx0) * 0.5 + abs(b) * (ly1 - ly0) * 0.5
		ey := abs(cc) * (lx1 - lx0) * 0.5 + abs(dd) * (ly1 - ly0) * 0.5
		mx := (lx0 + lx1) * 0.5
		my := (ly0 + ly1) * 0.5
		cx := a * mx + b * my + c.xt.x
		cy := cc * mx + dd * my + c.xt.y
		visible := cx + ex > c.clip.x && cx - ex < c.clip.z && cy + ey > c.clip.y && cy - ey < c.clip.w
		if !visible {
			return
		}
	}
	if len(d.cmds) >= MAX_DRAW_CMDS {
		return
	}
	n := len(d.batches)
	if n == 0 || d.batches[n - 1].image != image {
		append(&d.batches, Draw_Batch{first = i32(len(d.cmds)), count = 0, image = image})
		n += 1
	}
	append(&d.cmds, c)
	d.batches[n - 1].count += 1
}

@(private)
base_cmd :: proc(ctx: ^Context, ps: ^Paint_State, r: Rect, kind: Cmd_Kind) -> Draw_Cmd {
	c: Draw_Cmd
	sc := ctx.scale
	// world = S * (xf * (local_logical + r.xy)) ; local physical = local_logical * S
	// => world = xf.m * local_phys + S * (xf.m * r.xy + xf.t)
	t := ps.xf.m * [2]f32{r.x, r.y} + ps.xf.t
	c.size = {r.w * sc, r.h * sc, 0, 0}
	c.xf = {ps.xf.m[0, 0], ps.xf.m[0, 1], ps.xf.m[1, 0], ps.xf.m[1, 1]}
	c.xt = {t.x * sc, t.y * sc, f32(ps.filter), 0}
	c.clip = {ps.clip.x, ps.clip.y, ps.clip.x + ps.clip.w, ps.clip.y + ps.clip.h}
	c.clip_r = ps.clip_r
	c.params = {f32(kind), 0, 0, -1}
	return c
}

// Snaps a logical rect to whole physical pixels (only when untransformed).
@(private)
snap_rect :: proc(ctx: ^Context, ps: ^Paint_State, r: Rect) -> Rect {
	if !xform_is_identity(ps.xf) {
		return r
	}
	sc := ctx.scale
	x0 := math.round((r.x + ps.xf.t.x) * sc) / sc - ps.xf.t.x
	y0 := math.round((r.y + ps.xf.t.y) * sc) / sc - ps.xf.t.y
	x1 := math.round((r.x + r.w + ps.xf.t.x) * sc) / sc - ps.xf.t.x
	y1 := math.round((r.y + r.h + ps.xf.t.y) * sc) / sc - ps.xf.t.y
	return {x0, y0, x1 - x0, y1 - y0}
}

@(private)
snap_w :: proc(ctx: ^Context, w: f32) -> f32 {
	if w <= 0 {
		return 0
	}
	return max(1, math.round(w * ctx.scale))
}

@(private)
col4 :: proc "contextless" (c: Color, opacity: f32) -> [4]f32 {
	return {c.r, c.g, c.b, c.a * opacity}
}

@(private)
scaled_radii :: proc(ctx: ^Context, r: [4]f32, w, h: f32) -> [4]f32 {
	// CSS radius clamping: scale down so adjacent radii fit
	f: f32 = 1
	if r[0] + r[1] > w {
		f = min(f, w / (r[0] + r[1]))
	}
	if r[3] + r[2] > w {
		f = min(f, w / (r[3] + r[2]))
	}
	if r[0] + r[3] > h {
		f = min(f, h / (r[0] + r[3]))
	}
	if r[1] + r[2] > h {
		f = min(f, h / (r[1] + r[2]))
	}
	f = max(f, 0)
	return r * f * ctx.scale
}

// Public helpers for custom drawing (logical coordinates, current paint state not applied).
draw_rect :: proc(ctx: ^Context, r: Rect, color: Color, radius: f32 = 0) {
	ps := Paint_State{clip = NO_CLIP, opacity = 1, xf = XFORM_IDENTITY}
	c := base_cmd(ctx, &ps, r, .RRect)
	c.radii = scaled_radii(ctx, {radius, radius, radius, radius}, r.w, r.h)
	c.fill0 = col4(color, 1)
	emit(ctx, c)
}

// Anti-aliased line segment with round caps (logical coordinates).
draw_line :: proc(ctx: ^Context, a, b: [2]f32, color: Color, thickness: f32 = 1) {
	hw := thickness * 0.5
	x0 := min(a.x, b.x) - hw - 1
	y0 := min(a.y, b.y) - hw - 1
	r := Rect{x0, y0, abs(a.x - b.x) + thickness + 2, abs(a.y - b.y) + thickness + 2}
	ps := Paint_State{clip = NO_CLIP, opacity = 1, xf = XFORM_IDENTITY}
	c := base_cmd(ctx, &ps, r, .Segment)
	sc := ctx.scale
	c.fill0 = col4(color, 1)
	c.fill1 = {(a.x - x0) * sc, (a.y - y0) * sc, (b.x - x0) * sc, (b.y - y0) * sc}
	c.fill2 = {hw * sc, 0, 0, 0}
	emit(ctx, c)
}

// Connected line segments.
draw_polyline :: proc(ctx: ^Context, pts: [][2]f32, color: Color, thickness: f32 = 1) {
	for i in 1 ..< len(pts) {
		draw_line(ctx, pts[i - 1], pts[i], color, thickness)
	}
}

// Stroked circular arc with round caps. Angles in radians, clockwise from +x (screen y down).
draw_arc :: proc(ctx: ^Context, center: [2]f32, radius, start, sweep: f32, color: Color, thickness: f32 = 1) {
	ext := radius + thickness * 0.5 + 1
	r := Rect{center.x - ext, center.y - ext, ext * 2, ext * 2}
	ps := Paint_State{clip = NO_CLIP, opacity = 1, xf = XFORM_IDENTITY}
	c := base_cmd(ctx, &ps, r, .Arc)
	sc := ctx.scale
	a0 := math.mod(start, math.TAU)
	if a0 < 0 {
		a0 += math.TAU
	}
	c.fill0 = col4(color, 1)
	c.fill1 = {radius * sc, thickness * 0.5 * sc, a0, clamp(sweep, 0, math.TAU)}
	emit(ctx, c)
}

// Filled area between a polyline (x ascending) and a horizontal baseline, with a
// vertical gradient from `top` (at the highest point) to `bottom` (at the baseline).
// Chart fills: frequency responses, envelopes, sparklines.
draw_area :: proc(ctx: ^Context, pts: [][2]f32, base_y: f32, top: Color, bottom: Color) {
	if len(pts) < 2 {
		return
	}
	hi := base_y
	for p in pts {
		hi = min(hi, p.y)
	}
	span := max(base_y - hi, 1e-3)
	sc := ctx.scale
	ps := Paint_State{clip = NO_CLIP, opacity = 1, xf = XFORM_IDENTITY}
	for i in 1 ..< len(pts) {
		a, b := pts[i - 1], pts[i]
		if b.x <= a.x {
			continue
		}
		y0 := min(a.y, b.y) - 1
		if y0 >= base_y {
			continue
		}
		r := Rect{a.x, y0, b.x - a.x, base_y - y0}
		c := base_cmd(ctx, &ps, r, .Area)
		c.fill0 = col4(color_lerp(top, bottom, clamp((y0 - hi) / span, 0, 1)), 1)
		c.fill2 = col4(bottom, 1)
		c.fill1 = {(a.y - y0) * sc, (b.y - y0) * sc, 0, 0}
		emit(ctx, c)
	}
}

// Filled circle.
draw_circle :: proc(ctx: ^Context, center: [2]f32, radius: f32, color: Color) {
	draw_rect(ctx, {center.x - radius, center.y - radius, radius * 2, radius * 2}, color, radius)
}

// ---------------------------------------------------------------------------
// Paint traversal
// ---------------------------------------------------------------------------

paint_root :: proc(ctx: ^Context) {
	d := &ctx.draw
	clear(&d.cmds)
	clear(&d.batches)
	clear(&d.filters)
	append(&d.filters, COLOR_MATRIX_IDENTITY)
	clear(&ctx.hits)
	sc := ctx.scale
	d.size = {math.round(ctx.viewport.x * sc), math.round(ctx.viewport.y * sc)}
	root := &ctx.nodes[0]
	root.rect = {0, 0, ctx.viewport.x, ctx.viewport.y}
	ps := Paint_State{clip = {0, 0, d.size.x, d.size.y}, opacity = 1, xf = XFORM_IDENTITY}
	d.clear = root.style.bg
	paint_node(ctx, 0, {0, 0}, &ps, -1)
	// fixed overlays last, sorted by z
	if len(ctx.overlays) > 0 {
		slice.stable_sort_by(ctx.overlays[:], proc(a, b: i32) -> bool {
			ctx := g_ctx
			return ctx.nodes[a].style.z < ctx.nodes[b].style.z
		})
		for oi in ctx.overlays {
			on := &ctx.nodes[oi]
			ops := Paint_State{clip = {0, 0, d.size.x, d.size.y}, opacity = 1, xf = XFORM_IDENTITY}
			paint_node(ctx, oi, {0, 0}, &ops, -1, true)
			_ = on
		}
	}
	d.atlas_size = {f32(ctx.atlas.w), f32(ctx.atlas.h)}
}

@(private)
node_hit :: proc(ctx: ^Context, ni: i32, ps: ^Paint_State, parent_hit: i32, radius: [4]f32) -> i32 {
	n := &ctx.nodes[ni]
	sc := ctx.scale
	h := Hit{
		id        = n.id,
		parent    = parent_hit,
		rect      = n.rect,
		clip      = {ps.clip.x / sc, ps.clip.y / sc, ps.clip.w / sc, ps.clip.h / sc},
		cursor    = n.style.cursor,
		pointer   = n.style.pointer_events && .No_Hit not_in n.flags && n.style.visibility == .Visible,
		focusable = .Focusable in n.flags,
		text_input = .Text_Input in n.flags,
		scroll    = {.Scroll_X in n.flags, .Scroll_Y in n.flags},
		radius    = radius,
	}
	if !xform_is_identity(ps.xf) || ps.xf.t != {0, 0} {
		// node rect is in pre-transform absolute coords; ps.xf maps it to world
		h.has_xf = true
		h.inv = xform_inverse(ps.xf)
	}
	if h.cursor == .Auto {
		h.cursor = n.kind == .Text && n.style.user_select ? .Text : .Default
		if .Focusable in n.flags {
			h.cursor = .Default
		}
	}
	append(&ctx.hits, h)
	return i32(len(ctx.hits) - 1)
}

@(private)
anim_values :: proc(ctx: ^Context, n: ^Node) -> (translate: [2]f32, scale: [2]f32, rotate: f32, opacity: f32) {
	s := &n.style
	st := n.state
	tx, _ := resolve(ctx, s.translate[0], n.size.x)
	ty, _ := resolve(ctx, s.translate[1], n.size.y)
	scale = s.scale
	rotate = s.rotate
	opacity = s.opacity
	if st != nil {
		v := track_step(ctx, &st.tr_xf, {tx, ty, rotate, 0}, .Transform in s.transition, s)
		tx, ty, rotate = v[0], v[1], v[2]
		sv := track_step(ctx, &st.tr_scale, {scale.x, scale.y, 0, 0}, .Transform in s.transition, s)
		scale = {sv[0], sv[1]}
		ov := track_step(ctx, &st.tr_opacity, {opacity, 0, 0, 0}, .Opacity in s.transition, s)
		opacity = ov[0]
	}
	switch s.animation {
	case .None:
	case .Spin:
		rotate += f32(math.mod(ctx.time, 1.0)) * 360
		ctx.animating = true
	case .Ping:
		pp := f32(math.mod(ctx.time, 1.0))
		k: f32 = 1
		if pp < 0.75 {
			k = ease(EASE_OUT, pp / 0.75)
		}
		scale *= 1 + k
		opacity *= 1 - k
		ctx.animating = true
	case .Pulse:
		pp := f32(math.mod(ctx.time, 2.0)) / 2
		tri := pp < 0.5 ? pp * 2 : (1 - pp) * 2
		opacity *= 1 - 0.5 * ease({0.4, 0, 0.6, 1}, tri)
		ctx.animating = true
	case .Bounce:
		pp := f32(math.mod(ctx.time, 1.0))
		k: f32
		if pp < 0.5 {
			k = 1 - ease({0, 0, 0.2, 1}, pp / 0.5)
		} else {
			k = ease({0.8, 0, 1, 1}, (pp - 0.5) / 0.5)
		}
		ty += -0.25 * n.size.y * k
		ctx.animating = true
	}
	translate = {tx, ty}
	return
}

@(private)
build_filter :: proc(ctx: ^Context, s: ^Style, parent: i32) -> i32 {
	if s.brightness == 1 && s.contrast == 1 && s.grayscale == 0 && s.hue_rotate == 0 && s.invert == 0 && s.saturate == 1 && s.sepia == 0 {
		return parent
	}
	m := COLOR_MATRIX_IDENTITY
	if s.brightness != 1 {
		m = color_matrix_mul(cm_brightness(s.brightness), m)
	}
	if s.contrast != 1 {
		m = color_matrix_mul(cm_contrast(s.contrast), m)
	}
	if s.grayscale != 0 {
		m = color_matrix_mul(cm_grayscale(s.grayscale), m)
	}
	if s.hue_rotate != 0 {
		m = color_matrix_mul(cm_hue_rotate(s.hue_rotate), m)
	}
	if s.invert != 0 {
		m = color_matrix_mul(cm_invert(s.invert), m)
	}
	if s.saturate != 1 {
		m = color_matrix_mul(cm_saturate(s.saturate), m)
	}
	if s.sepia != 0 {
		m = color_matrix_mul(cm_sepia(s.sepia), m)
	}
	if parent > 0 {
		m = color_matrix_mul(ctx.draw.filters[parent], m)
	}
	if len(ctx.draw.filters) >= MAX_DRAW_FILTERS {
		// out of shader slots: keep the inherited filter rather than index past the array
		return parent
	}
	append(&ctx.draw.filters, m)
	return i32(len(ctx.draw.filters) - 1)
}

@(private)
paint_node :: proc(ctx: ^Context, ni: i32, parent_origin: [2]f32, pps: ^Paint_State, parent_hit: i32, overlay_pass := false) {
	n := &ctx.nodes[ni]
	s := &n.style
	if s.display == .None {
		return
	}
	if s.position == .Fixed && !overlay_pass && ni != 0 {
		append(&ctx.overlays, ni)
		return
	}
	// absolute position
	origin: [2]f32
	if n.abs_set {
		if s.position == .Fixed {
			origin = n.abs_pos
		} else {
			cbn := &ctx.nodes[n.cb]
			origin = {cbn.rect.x, cbn.rect.y} + n.abs_pos
		}
	} else {
		origin = parent_origin + n.pos
	}
	if s.position == .Relative || s.position == .Sticky {
		l, lok := resolve(ctx, s.inset[3], n.size.x)
		t, tok := resolve(ctx, s.inset[0], n.size.y)
		if lok {
			origin.x += l
		} else if r, rok := resolve(ctx, s.inset[1], n.size.x); rok {
			origin.x -= r
		}
		if tok {
			origin.y += t
		} else if b, bok := resolve(ctx, s.inset[2], n.size.y); bok {
			origin.y -= b
		}
	}
	n.rect = {origin.x, origin.y, n.size.x, n.size.y}
	if n.state != nil {
		n.state.rect = n.rect
	}

	ps := pps^
	translate, scale, rotate, opacity := anim_values(ctx, n)
	ps.opacity *= opacity
	if s.visibility != .Visible || ps.opacity <= 0.001 {
		// still record hit so hover state stays coherent; invisible elements do not receive pointer
		return
	}
	if translate != {0, 0} || scale != {1, 1} || rotate != 0 || s.skew != {0, 0} {
		o := [2]f32{origin.x + n.size.x * s.origin.x, origin.y + n.size.y * s.origin.y}
		rad := rotate * math.PI / 180
		cr := math.cos(rad)
		sr := math.sin(rad)
		kx := math.tan(s.skew.x * math.PI / 180)
		ky := math.tan(s.skew.y * math.PI / 180)
		rot := matrix[2, 2]f32{cr, -sr, sr, cr}
		sk := matrix[2, 2]f32{1, kx, ky, 1}
		scm := matrix[2, 2]f32{scale.x, 0, 0, scale.y}
		local := Xform{m = rot * sk * scm}
		// translate(o + translate) * local * translate(-o)
		local.t = o + translate - local.m * o
		ps.xf = xform_mul(ps.xf, local)
	}
	ps.filter = build_filter(ctx, s, ps.filter)
	n.xform = ps.xf
	n.opacity = ps.opacity

	radius := s.radius
	hit := node_hit(ctx, ni, &ps, parent_hit, scaled_radii(ctx, radius, n.size.x, n.size.y) / ctx.scale)

	r := snap_rect(ctx, &ps, n.rect)
	paint_box(ctx, n, &ps, r)

	// content
	switch n.kind {
	case .Text:
		paint_text(ctx, n, &ps, r)
	case .Icon:
		paint_icon(ctx, n, &ps, r)
	case .Image:
		paint_image(ctx, n, &ps, r)
	case .Custom:
		if n.custom != nil {
			n.custom(ctx, r, n.custom_data)
		}
	case .Box:
	}

	// children
	cps := ps
	scroll: [2]f32
	if n.state != nil {
		scroll = n.state.scroll
	}
	clips_x := clips(s.overflow_x)
	clips_y := clips(s.overflow_y)
	if clips_x || clips_y {
		bw := s.border_w
		inner := Rect{r.x + bw[3], r.y + bw[0], r.w - bw[1] - bw[3], r.h - bw[0] - bw[2]}
		if !clips_x {
			inner.x = -1e6
			inner.w = 2e6
		}
		if !clips_y {
			inner.y = -1e6
			inner.h = 2e6
		}
		if xform_is_identity(ps.xf) {
			sc := ctx.scale
			wr := Rect{(inner.x + ps.xf.t.x) * sc, (inner.y + ps.xf.t.y) * sc, inner.w * sc, inner.h * sc}
			cps.clip = rect_intersect(ps.clip, wr)
			if radius != {0, 0, 0, 0} && clips_x && clips_y {
				cps.clip_r = scaled_radii(ctx, {max(0, radius[0] - bw[3]), max(0, radius[1] - bw[1]), max(0, radius[2] - bw[1]), max(0, radius[3] - bw[3])}, inner.w, inner.h)
			}
		}
	}
	child_origin := [2]f32{origin.x, origin.y} - scroll

	// paint order: negative z, in-flow non-positioned, positioned (z >= 0 sorted)
	has_z := false
	for c := n.first; c >= 0; c = ctx.nodes[c].next {
		cn := &ctx.nodes[c]
		if cn.style.z_set || cn.style.position != .Static {
			has_z = true
			break
		}
	}
	if !has_z {
		for c := n.first; c >= 0; c = ctx.nodes[c].next {
			paint_node(ctx, c, child_origin, &cps, hit)
		}
	} else {
		order := make([dynamic]i32, 0, n.child_count, context.temp_allocator)
		for c := n.first; c >= 0; c = ctx.nodes[c].next {
			append(&order, c)
		}
		key :: proc(n: ^Node) -> i32 {
			if n.style.z_set {
				return n.style.z < 0 ? -1 : 1
			}
			return n.style.position != .Static ? 1 : 0
		}
		slice.stable_sort_by(order[:], proc(a, b: i32) -> bool {
			ctx := g_ctx
			na := &ctx.nodes[a]
			nb := &ctx.nodes[b]
			ka := na.style.z_set ? (na.style.z < 0 ? -1 : 1) : (na.style.position != .Static ? 1 : 0)
			kb := nb.style.z_set ? (nb.style.z < 0 ? -1 : 1) : (nb.style.position != .Static ? 1 : 0)
			if ka != kb {
				return ka < kb
			}
			za := na.style.z_set ? na.style.z : 0
			zb := nb.style.z_set ? nb.style.z : 0
			return za < zb
		})
		_ = key
		for c in order {
			paint_node(ctx, c, child_origin, &cps, hit)
		}
	}

	// scrollbars
	if n.state != nil && (.Scroll_Y in n.flags || .Scroll_X in n.flags) {
		paint_scrollbars(ctx, n, &ps, r, hit)
	}

	// outline (painted above content)
	if s.outline_w > 0 && s.outline_style != .None && s.outline_style != .Hidden {
		oc := s.outline_color_set ? s.outline_color : s.color
		ow := s.outline_w
		off := s.outline_offset
		orr := Rect{r.x - off - ow, r.y - off - ow, r.w + 2 * (off + ow), r.h + 2 * (off + ow)}
		c := base_cmd(ctx, &ps, orr, .RRect)
		rr := radius + (off + ow)
		for &v in rr {
			v = max(v, 0)
		}
		c.radii = scaled_radii(ctx, rr, orr.w, orr.h)
		bw := snap_w(ctx, ow)
		c.border_w = {bw, bw, bw, bw}
		c.border_c = col4(oc, ps.opacity)
		c.params[2] = f32(line_style_code(s.outline_style))
		emit(ctx, c)
	}
}

@(private)
line_style_code :: proc "contextless" (l: Line_Style) -> int {
	#partial switch l {
	case .Dashed:
		return 1
	case .Dotted:
		return 2
	case .Double:
		return 3
	}
	return 0
}

@(private)
shadow_list :: proc(ctx: ^Context, n: ^Node) -> (Shadow_Set, f32) {
	s := &n.style
	st := n.state
	cur := s.shadows
	if s.shadow_color_set {
		for i in 0 ..< cur.count {
			a := cur.items[i].color.a
			c := s.shadow_color
			cur.items[i].color = c
			if !s.shadow_alpha_set {
				cur.items[i].color.a = c.a * (a > 0 ? 1 : 0)
				// keep the size's own alpha when the color has no explicit opacity
				cur.items[i].color.a = a
				cur.items[i].color = {c.r, c.g, c.b, a}
			}
		}
	}
	if st == nil {
		return cur, 1
	}
	return cur, 1
}

@(private)
paint_box :: proc(ctx: ^Context, n: ^Node, ps: ^Paint_State, r: Rect) {
	s := &n.style
	st := n.state
	op := ps.opacity
	colors_on := .Colors in s.transition

	bg := s.bg
	if st != nil {
		bg = track_color(ctx, &st.tr_bg, bg, colors_on, s)
	}
	radius := s.radius
	rad := scaled_radii(ctx, radius, r.w, r.h)

	// box shadows (outer), ring offset, ring — painted below the background
	shadows, _ := shadow_list(ctx, n)
	shadow_mix: f32 = 1
	prev: Shadow_Set
	if st != nil {
		if shadows != st.cur_shadow {
			if .Shadow in s.transition && st.tr_shadow.init {
				st.prev_shadow = st.cur_shadow
				st.shadow_t0 = ctx.time
			} else {
				st.prev_shadow = {}
			}
			st.cur_shadow = shadows
			st.tr_shadow.init = true
		}
		if st.prev_shadow.count > 0 {
			dur := f64(max(s.duration_ms, 1)) / 1000
			k := f32((ctx.time - st.shadow_t0) / dur)
			if k >= 1 {
				st.prev_shadow = {}
			} else {
				shadow_mix = ease(s.easing, max(k, 0))
				prev = st.prev_shadow
				ctx.animating = true
			}
		}
	}
	draw_shadows :: proc(ctx: ^Context, ps: ^Paint_State, r: Rect, radius: [4]f32, set: Shadow_Set, alpha: f32) {
		for i := set.count - 1; i >= 0; i -= 1 {
			sh := set.items[i]
			if sh.inset || sh.color.a <= 0 {
				continue
			}
			sp := sh.spread
			sr := Rect{r.x + sh.offset.x - sp, r.y + sh.offset.y - sp, r.w + 2 * sp, r.h + 2 * sp}
			if sr.w <= 0 || sr.h <= 0 {
				continue
			}
			c := base_cmd(ctx, ps, sr, .Shadow)
			rr := radius
			for &v in rr {
				v = max(0, v + sp)
			}
			c.radii = scaled_radii(ctx, rr, sr.w, sr.h)
			c.fill0 = col4(sh.color, ps.opacity * alpha)
			c.params[1] = sh.blur / 2 * ctx.scale
			emit(ctx, c)
		}
	}
	if prev.count > 0 {
		draw_shadows(ctx, ps, r, radius, prev, 1 - shadow_mix)
	}
	draw_shadows(ctx, ps, r, radius, shadows, shadow_mix)

	// drop-shadow filter approximated as box shadow on boxes
	if s.drop_shadows.count > 0 && (bg.a > 0 || n.kind == .Box) {
		ds := s.drop_shadows
		if s.drop_shadow_color_set {
			for i in 0 ..< ds.count {
				ds.items[i].color = s.drop_shadow_color
			}
		}
		draw_shadows(ctx, ps, r, radius, ds, 1)
	}

	ring_c := s.ring_color_set ? s.ring_color : s.color
	if st != nil && s.ring_w > 0 {
		ring_c = track_color(ctx, &st.tr_ring, ring_c, colors_on, s)
	}
	if s.ring_w > 0 && !s.ring_inset {
		ow := s.ring_offset_w
		rw := s.ring_w
		// ring: solid band from offset to offset+width
		rr := Rect{r.x - ow - rw, r.y - ow - rw, r.w + 2 * (ow + rw), r.h + 2 * (ow + rw)}
		c := base_cmd(ctx, ps, rr, .RRect)
		rads := radius
		for &v in rads {
			v = max(0, v + ow + rw)
		}
		c.radii = scaled_radii(ctx, rads, rr.w, rr.h)
		bw := snap_w(ctx, rw)
		c.border_w = {bw, bw, bw, bw}
		c.border_c = col4(ring_c, ps.opacity)
		if ow > 0 {
			c.fill0 = col4(s.ring_offset_color, ps.opacity)
		}
		emit(ctx, c)
	}

	// background + border
	border_any := s.border_w != {0, 0, 0, 0} && s.border_style != .None && s.border_style != .Hidden
	has_grad := s.gradient.kind != .None
	if bg.a > 0 || border_any || has_grad {
		c := base_cmd(ctx, ps, r, .RRect)
		c.radii = rad
		c.fill0 = col4(bg, op)
		if has_grad {
			g := &s.gradient
			if g.kind == .Stripes {
				c.grad = {4, g.angle * math.PI / 180, 0, 1}
				sc := s.fill_set ? s.fill : s.color
				c.fill1 = col4(sc, op)
				c.xt[3] = g.period * ctx.scale
				c.extra[0] = max(1, g.line * ctx.scale)
			} else {
				c.grad = {f32(g.kind), g.angle * math.PI / 180, g.from_pos, g.to_pos == 0 ? 1 : g.to_pos}
				c.fill0 = col4(g.from, op)
				c.fill1 = col4(g.to, op)
				if g.has_via {
					c.fill2 = col4(g.via, op)
					c.params[3] = g.via_pos
				}
				if bg.a > 0 {
					// gradient over a background color: draw bg first
					cb := base_cmd(ctx, ps, r, .RRect)
					cb.radii = rad
					cb.fill0 = col4(bg, op)
					emit(ctx, cb)
				}
			}
		}
		if border_any {
			bcs := s.border_color
			uniform := true
			for i in 1 ..< 4 {
				if !color_eq(bcs[i], bcs[0]) {
					uniform = false
				}
			}
			for i in 0 ..< 4 {
				c.border_w[i] = snap_w(ctx, s.border_w[i])
			}
			c.params[2] = f32(line_style_code(s.border_style))
			if !s.border_color_set {
				bcs = {s.color, s.color, s.color, s.color} // currentColor default
				uniform = true
			}
			if uniform {
				bc := bcs[0]
				if st != nil {
					bc = track_color(ctx, &st.tr_border, bc, colors_on, s)
				}
				c.border_c = col4(bc, op)
				emit(ctx, c)
			} else {
				// fill first, then each side separately
				bw := c.border_w
				c.border_w = {}
				if bg.a > 0 || has_grad {
					emit(ctx, c)
				}
				for i in 0 ..< 4 {
					if bw[i] <= 0 {
						continue
					}
					sc := base_cmd(ctx, ps, r, .RRect)
					sc.radii = rad
					sc.border_w[i] = bw[i]
					sc.border_c = col4(bcs[i], op)
					sc.params[2] = f32(line_style_code(s.border_style))
					emit(ctx, sc)
				}
			}
		} else {
			emit(ctx, c)
		}
	}

	// inset shadows and inset rings (above background)
	inset := s.inset_shadows
	if s.inset_shadow_color_set {
		for i in 0 ..< inset.count {
			inset.items[i].color = {s.inset_shadow_color.r, s.inset_shadow_color.g, s.inset_shadow_color.b, s.inset_shadow_color.a < 1 ? s.inset_shadow_color.a : inset.items[i].color.a}
		}
	}
	for i := shadows.count - 1; i >= 0; i -= 1 {
		if shadows.items[i].inset {
			emit_inset(ctx, ps, r, radius, shadows.items[i])
		}
	}
	for i := inset.count - 1; i >= 0; i -= 1 {
		sh := inset.items[i]
		sh.inset = true
		emit_inset(ctx, ps, r, radius, sh)
	}
	if s.inset_ring_w > 0 || (s.ring_w > 0 && s.ring_inset) {
		w := s.inset_ring_w > 0 ? s.inset_ring_w : s.ring_w
		ic := s.inset_ring_w > 0 ? (s.inset_ring_color_set ? s.inset_ring_color : s.color) : ring_c
		c := base_cmd(ctx, ps, r, .RRect)
		c.radii = rad
		bw := snap_w(ctx, w)
		c.border_w = {bw, bw, bw, bw}
		c.border_c = col4(ic, op)
		emit(ctx, c)
	}
}

@(private)
emit_inset :: proc(ctx: ^Context, ps: ^Paint_State, r: Rect, radius: [4]f32, sh: Shadow) {
	if sh.color.a <= 0 {
		return
	}
	c := base_cmd(ctx, ps, r, .Inset_Shadow)
	c.radii = scaled_radii(ctx, radius, r.w, r.h)
	sc := ctx.scale
	sp := sh.spread
	hole := Rect{sh.offset.x + sp, sh.offset.y + sp, r.w - 2 * sp, r.h - 2 * sp}
	c.fill1 = {hole.x * sc, hole.y * sc, max(0, hole.w) * sc, max(0, hole.h) * sc}
	hr := radius
	for &v in hr {
		v = max(0, v - sp)
	}
	c.fill2 = hr * sc
	c.fill0 = col4(sh.color, ps.opacity)
	c.params[1] = sh.blur / 2 * sc
	emit(ctx, c)
}

@(private)
paint_scrollbars :: proc(ctx: ^Context, n: ^Node, ps: ^Paint_State, r: Rect, owner_hit: i32) {
	st := n.state
	s := &n.style
	hover := st.hovered || ctx.drag_thumb == n.id
	thick: f32 = ctx.drag_thumb == n.id ? 8 : 6
	pad: f32 = 2
	base := ctx.dark ? Color{1, 1, 1, 0.22} : Color{0, 0, 0, 0.22}
	if tok, ok := ctx.theme.colors["scrollbar"]; ok {
		base = ctx.dark ? tok.dark : tok.light
	}
	// overlay scrollbars: visible while hovered or scrolling, then fade out
	since := f32(ctx.time - st.scroll_active_t)
	vis: f32 = 0
	if ctx.drag_thumb == n.id {
		vis = 1
	} else if since < 0.9 {
		vis = 1
	} else if since < 1.3 {
		vis = 1 - (since - 0.9) / 0.4
	}
	if st.hovered {
		vis = max(vis, 0.6)
	}
	if since < 1.3 {
		ctx.animating = true
	}
	base.a *= vis
	if hover && ctx.drag_thumb == n.id {
		base.a *= 1.6
	}
	bw := s.border_w
	vw := r.w - bw[1] - bw[3]
	vh := r.h - bw[0] - bw[2]
	if .Scroll_Y in n.flags && st.scroll_max.y > 0.5 {
		content := vh + st.scroll_max.y
		th := max(24, vh * vh / content)
		ty := (vh - th) * st.scroll.y / st.scroll_max.y
		tr := Rect{r.x + r.w - bw[1] - thick - pad, r.y + bw[0] + ty, thick, th}
		c := base_cmd(ctx, ps, tr, .RRect)
		c.radii = scaled_radii(ctx, {99, 99, 99, 99}, tr.w, tr.h)
		c.fill0 = col4(base, ps.opacity)
		emit(ctx, c)
		append(&ctx.hits, Hit{id = n.id, parent = owner_hit, rect = {tr.x - 4, tr.y, tr.w + 6, tr.h}, clip = NO_CLIP, thumb = 1, cursor = .Default, inv = XFORM_IDENTITY})
	}
	if .Scroll_X in n.flags && st.scroll_max.x > 0.5 {
		content := vw + st.scroll_max.x
		tw := max(24, vw * vw / content)
		tx := (vw - tw) * st.scroll.x / st.scroll_max.x
		tr := Rect{r.x + bw[3] + tx, r.y + r.h - bw[2] - thick - pad, tw, thick}
		c := base_cmd(ctx, ps, tr, .RRect)
		c.radii = scaled_radii(ctx, {99, 99, 99, 99}, tr.w, tr.h)
		c.fill0 = col4(base, ps.opacity)
		emit(ctx, c)
		append(&ctx.hits, Hit{id = n.id, parent = owner_hit, rect = {tr.x, tr.y - 4, tr.w, tr.h + 6}, clip = NO_CLIP, thumb = 2, cursor = .Default, inv = XFORM_IDENTITY})
	}
}

// ---------------------------------------------------------------------------
// Text, icons, images
// ---------------------------------------------------------------------------

@(private)
emit_glyph :: proc(ctx: ^Context, ps: ^Paint_State, face: Face_Id, glyph: u16, size: f32, pen: [2]f32, color: Color) {
	sc := ctx.scale
	if xform_is_identity(ps.xf) {
		// physical pen position: snap baseline, quantize x to subpixel steps
		wx := (pen.x + ps.xf.t.x) * sc
		wy := math.round((pen.y + ps.xf.t.y) * sc)
		ix := math.floor(wx)
		sub := int(math.floor((wx - ix) * SUBPIXEL_STEPS + 0.5))
		if sub >= SUBPIXEL_STEPS {
			sub = 0
			ix += 1
		}
		e, ok := atlas_glyph(&ctx.atlas, &ctx.fonts, face, glyph, size * sc, sub)
		if !ok || e.w == 0 {
			return
		}
		c: Draw_Cmd
		c.size = {f32(e.w), f32(e.h), 0, 0}
		c.xf = {1, 0, 0, 1}
		c.xt = {ix + f32(e.ox), wy + f32(e.oy), f32(ps.filter), 0}
		c.clip = {ps.clip.x, ps.clip.y, ps.clip.x + ps.clip.w, ps.clip.y + ps.clip.h}
		c.clip_r = ps.clip_r
		c.params = {f32(Cmd_Kind.Glyph), 0, 0, -1}
		c.uv = {f32(e.x), f32(e.y), f32(e.w), f32(e.h)}
		c.fill0 = col4(color, ps.opacity)
		emit(ctx, c)
		return
	}
	// transformed: render at the transformed scale magnitude
	e, ok := atlas_glyph(&ctx.atlas, &ctx.fonts, face, glyph, size * sc, 0)
	if !ok || e.w == 0 {
		return
	}
	r := Rect{pen.x + f32(e.ox) / sc, pen.y + f32(e.oy) / sc, f32(e.w) / sc, f32(e.h) / sc}
	c := base_cmd(ctx, ps, r, .Glyph)
	c.uv = {f32(e.x), f32(e.y), f32(e.w), f32(e.h)}
	c.fill0 = col4(color, ps.opacity)
	emit(ctx, c)
}

@(private)
paint_text :: proc(ctx: ^Context, n: ^Node, ps: ^Paint_State, r: Rect) {
	if n.para < 0 {
		return
	}
	pr := &ctx.paras[n.para]
	if len(pr.spans) == 0 {
		return
	}
	s := &n.style
	pb := pad_border(s)
	ox := n.rect.x + pb[3]
	oy := n.rect.y + pb[0]
	// a text element that is itself a flex/grid container aligns its text block
	if is_flex(s.display) || is_grid(s.display) {
		inner_w := n.size.x - pb[1] - pb[3]
		inner_h := n.size.y - pb[0] - pb[2]
		fw := inner_w - pr.width
		fh := inner_h - pr.height
		jx, ay: f32
		if is_grid(s.display) {
			#partial switch s.justify_items {
			case .Center:
				jx = fw / 2
			case .End:
				jx = fw
			}
			if s.justify == .Center {
				jx = fw / 2
			}
			#partial switch s.align_items {
			case .Center:
				ay = fh / 2
			case .End:
				ay = fh
			}
		} else {
			row := s.flex_dir == .Row || s.flex_dir == .Row_Reverse
			main_free := row ? fw : fh
			cross_free := row ? fh : fw
			mo, co: f32
			#partial switch s.justify {
			case .Center, .Around, .Evenly:
				mo = main_free / 2
			case .End:
				mo = main_free
			}
			#partial switch s.align_items {
			case .Center:
				co = cross_free / 2
			case .End:
				co = cross_free
			case .Baseline:
			}
			if row {
				jx, ay = mo, co
			} else {
				jx, ay = co, mo
			}
		}
		ox += max(jx, 0)
		oy += max(ay, 0)
	}
	// single-run text nodes animate their color with the node's transition
	fg_anim: Maybe(Color)
	if n.state != nil && len(pr.spans) == 1 {
		fg_anim = track_color(ctx, &n.state.tr_fg, s.color, .Colors in s.transition, s)
	}
	for li in 0 ..< len(pr.lines) {
		line := &pr.lines[li]
		lx := ox + line.x
		// span backgrounds
		k := line.first
		end := line.first + line.count
		for k < end {
			g := &pr.glyphs[k]
			sp := &pr.spans[g.span]
			j := k
			for j + 1 < end && pr.glyphs[j + 1].span == g.span {
				j += 1
			}
			if sp.style.bg.a > 0 || sp.style.border_w != {0, 0, 0, 0} {
				x0 := lx + pr.glyphs[k].x - (.Span_Start in pr.glyphs[k].flags ? sp.pad[3] : 0)
				gl := &pr.glyphs[j]
				x1 := lx + gl.x + gl.adv
				top := oy + line.baseline - sp.ascent - sp.pad[0]
				bot := oy + line.baseline + sp.descent + sp.pad[2]
				br := snap_rect(ctx, ps, {x0, top, x1 - x0, bot - top})
				c := base_cmd(ctx, ps, br, .RRect)
				c.radii = scaled_radii(ctx, sp.style.radius, br.w, br.h)
				c.fill0 = col4(sp.style.bg, ps.opacity)
				if sp.style.border_w != {0, 0, 0, 0} {
					for bi in 0 ..< 4 {
						c.border_w[bi] = snap_w(ctx, sp.style.border_w[bi])
					}
					bc := sp.style.border_color_set ? sp.style.border_color[0] : sp.style.color
					c.border_c = col4(bc, ps.opacity)
				}
				emit(ctx, c)
			}
			k = j + 1
		}
		// glyphs + decorations
		k = line.first
		for k < end {
			g := &pr.glyphs[k]
			sp := &pr.spans[g.span]
			col := sp.style.color
			if fc, ok := fg_anim.?; ok {
				col = fc
			}
			// text shadows (offset only)
			ts := sp.style.text_shadows
			for ti := ts.count - 1; ti >= 0; ti -= 1 {
				sh := ts.items[ti]
				shc := sp.style.text_shadow_color_set ? sp.style.text_shadow_color : sh.color
				if sp.style.text_shadow_color_set && sh.color.a < 1 && sp.style.text_shadow_color.a >= 1 {
					shc.a = min(1, sh.color.a * 4)
				}
				if .Space not_in g.flags && .Newline not_in g.flags {
					emit_glyph(ctx, ps, sp.face, g.glyph, sp.size, {lx + g.x + sh.offset.x, oy + line.baseline + sh.offset.y}, shc)
				}
			}
			if .Space not_in g.flags && .Newline not_in g.flags && g.glyph != 0 {
				emit_glyph(ctx, ps, sp.face, g.glyph, sp.size, {lx + g.x, oy + line.baseline}, col)
			}
			k += 1
		}
		if pr.has_ellipsis && pr.ellipsis_line == i32(li) {
			eg := pr.ellipsis_glyph
			sp := &pr.spans[eg.span]
			col := sp.style.color
			if fc, ok := fg_anim.?; ok {
				col = fc
			}
			emit_glyph(ctx, ps, sp.face, eg.glyph, sp.size, {lx + eg.x, oy + line.baseline}, col)
		}
		// decorations per span run
		k = line.first
		for k < end {
			g := &pr.glyphs[k]
			sp := &pr.spans[g.span]
			j := k
			for j + 1 < end && pr.glyphs[j + 1].span == g.span {
				j += 1
			}
			if sp.style.decoration != {} {
				f := &ctx.fonts.faces[sp.face]
				dc := sp.style.decoration_color_set ? sp.style.decoration_color : sp.style.color
				if fc, ok := fg_anim.?; ok && !sp.style.decoration_color_set {
					dc = fc
				}
				th := sp.style.decoration_thickness > 0 ? sp.style.decoration_thickness : max(f.underline_th * sp.size, 1)
				x0 := lx + pr.glyphs[k].x
				// trim trailing spaces
				jj := j
				for jj > k && (.Space in pr.glyphs[jj].flags) {
					jj -= 1
				}
				x1 := lx + pr.glyphs[jj].x + pr.glyphs[jj].adv
				base := oy + line.baseline
				if .Underline in sp.style.decoration {
					uy := base - f.underline_pos * sp.size + sp.style.underline_offset
					emit_line(ctx, ps, x0, x1, uy, th, dc, sp.style.decoration_style)
				}
				if .Line_Through in sp.style.decoration {
					uy := base - f.ascent * sp.size * 0.3
					emit_line(ctx, ps, x0, x1, uy, th, dc, sp.style.decoration_style)
				}
				if .Overline in sp.style.decoration {
					uy := base - f.ascent * sp.size
					emit_line(ctx, ps, x0, x1, uy, th, dc, sp.style.decoration_style)
				}
			}
			k = j + 1
		}
	}
}

@(private)
emit_line :: proc(ctx: ^Context, ps: ^Paint_State, x0, x1, y, th: f32, col: Color, style: Line_Style) {
	sc := ctx.scale
	thp := max(1, math.round(th * sc)) / sc
	yy := math.round(y * sc) / sc
	if style == .Double {
		c := base_cmd(ctx, ps, {x0, yy, x1 - x0, thp}, .RRect)
		c.fill0 = col4(col, ps.opacity)
		emit(ctx, c)
		c2 := base_cmd(ctx, ps, {x0, yy + thp * 2, x1 - x0, thp}, .RRect)
		c2.fill0 = col4(col, ps.opacity)
		emit(ctx, c2)
		return
	}
	if style == .Wavy {
		// zig-zag via small segments
		step := max(thp * 3, 3 / sc)
		x := x0
		up := true
		for x < x1 {
			w := min(step, x1 - x)
			c := base_cmd(ctx, ps, {x, yy + (up ? 0 : thp), w, thp}, .RRect)
			c.fill0 = col4(col, ps.opacity)
			emit(ctx, c)
			x += step
			up = !up
		}
		return
	}
	c := base_cmd(ctx, ps, {x0, yy, x1 - x0, thp}, .RRect)
	c.fill0 = col4(col, ps.opacity)
	if style == .Dashed || style == .Dotted {
		c.border_w = {thp * sc, 0, 0, 0}
		c.border_c = c.fill0
		c.fill0 = {}
		c.params[2] = style == .Dashed ? 1 : 2
	}
	emit(ctx, c)
}

@(private)
paint_icon :: proc(ctx: ^Context, n: ^Node, ps: ^Paint_State, r: Rect) {
	s := &n.style
	pb := pad_border(s)
	ir := Rect{r.x + pb[3], r.y + pb[0], r.w - pb[1] - pb[3], r.h - pb[0] - pb[2]}
	if ir.w <= 0 || ir.h <= 0 {
		return
	}
	col := s.fill_set ? s.fill : s.color
	if n.state != nil {
		col = track_color(ctx, &n.state.tr_fill, col, .Colors in s.transition, s)
	}
	sc := ctx.scale
	if xform_is_identity(ps.xf) {
		x := math.round((ir.x + ps.xf.t.x) * sc)
		y := math.round((ir.y + ps.xf.t.y) * sc)
		w := math.round(ir.w * sc)
		h := math.round(ir.h * sc)
		e, ok := atlas_icon(&ctx.atlas, ctx, n.icon, w, h)
		if !ok {
			return
		}
		c: Draw_Cmd
		c.size = {f32(e.w), f32(e.h), 0, 0}
		c.xf = {1, 0, 0, 1}
		c.xt = {x, y, f32(ps.filter), 0}
		c.clip = {ps.clip.x, ps.clip.y, ps.clip.x + ps.clip.w, ps.clip.y + ps.clip.h}
		c.clip_r = ps.clip_r
		c.params = {f32(Cmd_Kind.Glyph), 0, 0, -1}
		c.uv = {f32(e.x), f32(e.y), f32(e.w), f32(e.h)}
		c.fill0 = col4(col, ps.opacity)
		emit(ctx, c)
		return
	}
	e, ok := atlas_icon(&ctx.atlas, ctx, n.icon, ir.w * sc, ir.h * sc)
	if !ok {
		return
	}
	c := base_cmd(ctx, ps, ir, .Glyph)
	c.uv = {f32(e.x), f32(e.y), f32(e.w), f32(e.h)}
	c.fill0 = col4(col, ps.opacity)
	emit(ctx, c)
}

@(private)
paint_image :: proc(ctx: ^Context, n: ^Node, ps: ^Paint_State, r: Rect) {
	if n.image == 0 || int(n.image) > len(ctx.images) {
		return
	}
	s := &n.style
	pb := pad_border(s)
	box := Rect{r.x + pb[3], r.y + pb[0], r.w - pb[1] - pb[3], r.h - pb[0] - pb[2]}
	sz := image_size(ctx, n.image)
	if sz.x <= 0 || sz.y <= 0 || box.w <= 0 || box.h <= 0 {
		return
	}
	// object-fit
	dst := box
	uv := [4]f32{0, 0, 1, 1}
	ar := sz.x / sz.y
	bar := box.w / box.h
	fit := s.object_fit
	if fit == .Scale_Down {
		fit = (sz.x > box.w || sz.y > box.h) ? .Contain : .None
	}
	switch fit {
	case .Fill:
	case .Contain:
		if ar > bar {
			h := box.w / ar
			dst = {box.x, box.y + (box.h - h) * s.object_pos.y, box.w, h}
		} else {
			w := box.h * ar
			dst = {box.x + (box.w - w) * s.object_pos.x, box.y, w, box.h}
		}
	case .Cover:
		if ar > bar {
			vw := bar / ar
			uv = {(1 - vw) * s.object_pos.x, 0, vw, 1}
		} else {
			vh := ar / bar
			uv = {0, (1 - vh) * s.object_pos.y, 1, vh}
		}
	case .None, .Scale_Down:
		w := sz.x
		h := sz.y
		dst = {box.x + (box.w - w) * s.object_pos.x, box.y + (box.h - h) * s.object_pos.y, w, h}
	}
	c := base_cmd(ctx, ps, dst, .Image)
	c.uv = uv
	c.fill0 = {1, 1, 1, ps.opacity}
	// clip to the element's rounded box
	if s.radius != {0, 0, 0, 0} && xform_is_identity(ps.xf) {
		sc := ctx.scale
		wr := Rect{(r.x + ps.xf.t.x) * sc, (r.y + ps.xf.t.y) * sc, r.w * sc, r.h * sc}
		cl := rect_intersect(ps.clip, wr)
		c.clip = {cl.x, cl.y, cl.x + cl.w, cl.y + cl.h}
		c.clip_r = scaled_radii(ctx, s.radius, r.w, r.h)
	}
	emit(ctx, c, n.image)
}

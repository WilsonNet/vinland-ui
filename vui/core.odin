package vui

import "base:runtime"
import "core:hash"
import "core:math"
import "core:mem"
import "core:mem/virtual"
import "core:strings"

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

Id :: distinct u64
Image_Id :: distinct u32

Rect :: struct {
	x, y, w, h: f32,
}

rect_contains :: proc "contextless" (r: Rect, p: [2]f32) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h
}

rect_intersect :: proc "contextless" (a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	return {x0, y0, max(0, x1 - x0), max(0, y1 - y0)}
}

INF :: f32(1e9)
ROOT_ID :: Id(0x9e3779b97f4a7c15)
NO_CLIP :: Rect{-1e9, -1e9, 2e9, 2e9}

Node_Kind :: enum u8 {
	Box,
	Text,
	Icon,
	Image,
	Custom,
}

Node_Flag :: enum u8 {
	Focusable,
	Text_Input,
	Has_Group,
	Scroll_X,
	Scroll_Y,
	No_Hit,
	Measured_Intrinsic,
	Overlay,
}
Node_Flags :: bit_set[Node_Flag;u16]

// Mutable 2D affine transform: p' = m * p + t
Xform :: struct {
	m: matrix[2, 2]f32,
	t: [2]f32,
}

XFORM_IDENTITY :: Xform {
	m = 1,
}

xform_apply :: proc "contextless" (x: Xform, p: [2]f32) -> [2]f32 {
	return x.m * p + x.t
}

xform_mul :: proc "contextless" (a, b: Xform) -> Xform {
	// a after b
	return {m = a.m * b.m, t = a.m * b.t + a.t}
}

xform_inverse :: proc "contextless" (x: Xform) -> Xform {
	det := x.m[0, 0] * x.m[1, 1] - x.m[0, 1] * x.m[1, 0]
	if abs(det) < 1e-12 {
		return XFORM_IDENTITY
	}
	inv := matrix[2, 2]f32{
		x.m[1, 1] / det, -x.m[0, 1] / det,
		-x.m[1, 0] / det, x.m[0, 0] / det,
	}
	return {m = inv, t = -(inv * x.t)}
}

xform_is_identity :: proc "contextless" (x: Xform) -> bool {
	return x.m[0, 0] == 1 && x.m[1, 1] == 1 && x.m[0, 1] == 0 && x.m[1, 0] == 0
}

Custom_Draw :: #type proc(ctx: ^Context, rect: Rect, data: rawptr)

Measure_Entry :: struct {
	key:  [5]f32,
	size: [2]f32,
}

Node :: struct {
	id:          Id,
	kind:        Node_Kind,
	flags:       Node_Flags,
	parent:      i32,
	first:       i32,
	last:        i32,
	next:        i32,
	child_count: i32,
	index:       i32, // among siblings
	cb:          i32, // containing block for absolute/fixed
	style:       Style,
	cs:          ^Class_Set,
	class:       string,
	match:       Variants,
	para:        i32, // paragraph index, -1 = none
	icon:        Icon,
	image:       Image_Id,
	custom:      Custom_Draw,
	custom_data: rawptr,
	debug_name:  string,
	// layout results (logical px)
	pos:         [2]f32, // relative to parent border-box (before scroll)
	size:        [2]f32, // border box
	content:     [2]f32, // scrollable content extent (from padding-box origin)
	baseline:    f32, // first baseline from border-box top, -1 none
	abs_set:     bool,
	abs_pos:     [2]f32, // for absolutely positioned nodes: offset from CB border-box
	rect:        Rect, // absolute, untransformed
	clip:        Rect, // absolute clip in effect
	xform:       Xform, // absolute transform (logical px)
	opacity:     f32, // accumulated
	filter:      i32,
	intrinsic:   [2]f32, // min-content, max-content border-box widths
	mcache:      [4]Measure_Entry,
	mcache_n:    u8,
	state:       ^Elem_State,
}

// Animated value with CSS-transition semantics.
Anim_Track :: struct {
	from:   [4]f32,
	to:     [4]f32,
	start:  f64,
	init:   bool,
	moving: bool,
}

Edit_State :: struct {
	cursor:   int,
	anchor:   int,
	scroll_x: f32,
	blink_t:  f64,
	dragging: bool,
}

Elem_State :: struct {
	last_frame:     u64,
	hovered:        bool,
	active:         bool,
	focused:        bool,
	focus_visible:  bool,
	clicked:        bool,
	right_clicked:  bool,
	double_clicked: bool,
	clicked_self:   bool, // clicked, and this element was the topmost hit (not a descendant)
	pressed_now:    bool,
	released_now:   bool,
	prev_children:  i32,
	scroll:         [2]f32,
	scroll_target:  [2]f32,
	scroll_max:     [2]f32,
	scroll_active_t: f64, // last time the scroll offset moved
	rect:           Rect,
	tr_bg:          Anim_Track,
	tr_fg:          Anim_Track,
	tr_border:      Anim_Track,
	tr_ring:        Anim_Track,
	tr_fill:        Anim_Track,
	tr_opacity:     Anim_Track,
	tr_xf:          Anim_Track, // translate x, translate y, rotate, scale
	tr_scale:       Anim_Track,
	tr_shadow:      Anim_Track, // crossfade progress
	tr_size:        Anim_Track,
	prev_shadow:    Shadow_Set,
	cur_shadow:     Shadow_Set,
	shadow_t0:      f64,
	edit:           Edit_State,
	user:           rawptr,
	user_free:      proc(p: rawptr),
}

Mouse_Button :: enum u8 {
	Left,
	Right,
	Middle,
}
Mouse_Buttons :: bit_set[Mouse_Button;u8]

Key :: enum u8 {
	Tab,
	Enter,
	Escape,
	Backspace,
	Delete,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	Space,
	A,
	C,
	V,
	X,
	Z,
	Y,
	K,
	F1,
	F5,
	F12,
	Slash,
}
Keys :: bit_set[Key;u32]

Mod :: enum u8 {
	Shift,
	Ctrl,
	Alt,
	Super,
}
Mods :: bit_set[Mod;u8]

Input :: struct {
	mouse:        [2]f32, // logical px
	mouse_inside: bool,
	buttons:      Mouse_Buttons,
	pressed:      Mouse_Buttons,
	released:     Mouse_Buttons,
	click_count:  int,
	wheel:        [2]f32, // logical px to scroll (positive y = content moves up)
	keys_pressed: Keys, // includes repeats
	keys_down:    Keys,
	mods:         Mods,
	text:         string, // text typed this frame (utf8)
}

Image_Def :: struct {
	w, h:     int,
	pixels:   []u8, // RGBA8, straight alpha
	dirty:    bool,
	handle:   u64, // backend texture handle
	freed:    bool,
	external: bool, // handle owned by the host (e.g. a game render target); never uploaded or freed
	flip_y:   bool, // external GL render targets are stored bottom-up
	nearest:  bool, // sample without filtering (pixel maps such as a minimap); GPU backends
}

Hit :: struct {
	id:        Id,
	parent:    i32,
	rect:      Rect, // logical, untransformed local rect in absolute coords
	clip:      Rect,
	inv:       Xform, // inverse of node transform (absolute)
	has_xf:    bool,
	cursor:    Cursor,
	pointer:   bool,
	focusable: bool,
	text_input: bool,
	scroll:    [2]bool,
	thumb:     i8, // scrollbar thumb: 0 none, 1 vertical, 2 horizontal
	radius:    [4]f32,
}

Clipboard_Get :: #type proc(allocator: mem.Allocator) -> string
Clipboard_Set :: #type proc(s: string)

Context :: struct {
	theme:        Theme,
	dark:         bool,
	fonts:        Fonts,
	atlas:        Atlas,
	icons:        [dynamic]Icon_Def,
	images:       [dynamic]Image_Def,
	image_names:  map[string]Image_Id,
	class_cache:  map[string]^Class_Set,
	cache_version: u64,
	states:       map[Id]^Elem_State,
	arena:        virtual.Arena, // native: growing virtual-memory arena
	dyn_arena:    mem.Dynamic_Arena, // wasm: no virtual memory, use a block arena
	frame_alloc:  mem.Allocator,
	nodes:        [dynamic]Node,
	paras:        [dynamic]Paragraph,
	stack:        [dynamic]i32,
	positioned:   [dynamic]i32,
	groups:       [dynamic]i32,
	id_stack:     [dynamic]Id,
	occ:          map[u64]u32,
	pending_key:  u64,
	has_pending_key: bool,
	frame:        u64,
	time:         f64,
	dt:           f32,
	viewport:     [2]f32,
	scale:        f32,
	input:        Input,
	hits:         [dynamic]Hit,
	hover_id:     Id,
	press_id:     Id,
	focus_id:     Id,
	focus_visible: bool,
	focus_next:   bool,
	focus_prev:   bool,
	drag_thumb:   Id,
	drag_axis:    int,
	drag_start:   [2]f32,
	drag_scroll0: f32,
	cursor:       Cursor,
	animating:    bool,
	text_input_wanted: bool,
	text_input_rect: Rect,
	draw:         Draw_List,
	overlays:     [dynamic]i32,
	root:         i32,
	clipboard_get: Clipboard_Get,
	clipboard_set: Clipboard_Set,
	text_gamma:   f32,
	grade:        Grade,
	debug_unknown_classes: bool,
	last_layout_ms: f32,
	scroll_requests: [dynamic]Scroll_Request,
}

// Colour grade applied to every UI pixel in the fragment shader (all backends). Game HUDs use
// it to sit inside a painted world instead of on top of it: pull saturation and contrast down,
// warm the tint, and add stable grain and low-frequency mottling so flat fills read as worn
// material. Text keeps its edges (no grain). Zero value = off.
Grade :: struct {
	enabled:    bool,
	saturation: f32, // 1 = unchanged
	contrast:   f32, // 1 = unchanged, around mid grey
	grain:      f32, // fine per-pixel noise amplitude (0..0.2)
	mottle:     f32, // low-frequency blotch amplitude (0..0.3)
	tint:       [3]f32, // multiplier, {1,1,1} = unchanged
	scale:      f32, // mottle feature size in logical px (default 48)
}

GRADE_PAINTED :: Grade{enabled = true, saturation = 0.78, contrast = 0.94, grain = 0.06, mottle = 0.16, tint = {1.0, 0.95, 0.86}, scale = 46}

// Packs the grade for the shader uniforms u_grade / u_grade_tint.
grade_uniforms :: proc "contextless" (g: Grade, px_scale: f32) -> (grade, tint: [4]f32) {
	if !g.enabled {
		return {1, 1, 0, 0}, {1, 1, 1, 0}
	}
	sc := g.scale > 0 ? g.scale : 48
	return {g.saturation, g.contrast, g.grain, g.mottle}, {g.tint[0], g.tint[1], g.tint[2], sc * max(px_scale, 1)}
}

Scroll_Request :: struct {
	id:     Id,
	offset: f32,
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

@(private, thread_local)
g_ctx: ^Context

ctx_get :: proc "contextless" () -> ^Context {
	return g_ctx
}

init :: proc(ctx: ^Context, theme := Theme{}) {
	ctx^ = {}
	ctx.theme = theme
	if ctx.theme.spacing == 0 {
		ctx.theme = theme_default()
	}
	when ODIN_OS == .JS {
		mem.dynamic_arena_init(&ctx.dyn_arena, block_size = 1 << 20)
		ctx.frame_alloc = mem.dynamic_arena_allocator(&ctx.dyn_arena)
	} else {
		_ = virtual.arena_init_growing(&ctx.arena)
		ctx.frame_alloc = virtual.arena_allocator(&ctx.arena)
	}
	atlas_init(&ctx.atlas)
	ctx.scale = 1
	ctx.text_gamma = 1
	draw_list_init(&ctx.draw)
	g_ctx = ctx
}

destroy :: proc(ctx: ^Context) {
	for _, cs in ctx.class_cache {
		class_set_destroy(cs)
	}
	delete(ctx.class_cache)
	for _, st in ctx.states {
		if st.user != nil && st.user_free != nil {
			st.user_free(st.user)
		}
		free(st)
	}
	delete(ctx.states)
	atlas_destroy(&ctx.atlas)
	for &f in ctx.fonts.faces {
		delete(f.family)
		delete(f.glyphs)
	}
	delete(ctx.fonts.faces)
	for _, l in ctx.fonts.families {
		delete(l)
	}
	delete(ctx.fonts.families)
	for d in ctx.icons {
		delete(d.vertices)
	}
	delete(ctx.icons)
	for img in ctx.images {
		delete(img.pixels)
	}
	delete(ctx.images)
	for k in ctx.image_names {
		delete(k)
	}
	delete(ctx.image_names)
	delete(ctx.hits)
	delete(ctx.scroll_requests)
	draw_list_destroy(&ctx.draw)
	theme_destroy(&ctx.theme)
	when ODIN_OS == .JS {
		mem.dynamic_arena_destroy(&ctx.dyn_arena)
	} else {
		virtual.arena_destroy(&ctx.arena)
	}
	if g_ctx == ctx {
		g_ctx = nil
	}
}

make_current :: proc(ctx: ^Context) {
	g_ctx = ctx
}

set_dark :: proc(dark: bool) {
	g_ctx.dark = dark
}

is_dark :: proc() -> bool {
	return g_ctx.dark
}

theme :: proc() -> ^Theme {
	return &g_ctx.theme
}

// Call after mutating ctx.theme so cached class sets are rebuilt.
theme_changed :: proc() {
	g_ctx.theme.version += 1
}

@(private)
class_set_for :: proc(ctx: ^Context, class: string) -> ^Class_Set {
	if ctx.cache_version != ctx.theme.version {
		for _, cs in ctx.class_cache {
			class_set_destroy(cs)
		}
		clear(&ctx.class_cache)
		ctx.cache_version = ctx.theme.version
	}
	if cs, ok := ctx.class_cache[class]; ok {
		return cs
	}
	cs := parse_classes(&ctx.theme, class)
	ctx.class_cache[cs.source] = cs
	return cs
}

// Unknown utilities seen so far (debugging aid).
unknown_classes :: proc(ctx: ^Context, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for _, cs in ctx.class_cache {
		for u in cs.unknown {
			append(&out, u)
		}
	}
	return out[:]
}

// ---------------------------------------------------------------------------
// Frame
// ---------------------------------------------------------------------------

begin_frame :: proc(ctx: ^Context, input: Input, viewport: [2]f32, scale: f32, time: f64) {
	g_ctx = ctx
	ctx.frame += 1
	dt := f32(time - ctx.time)
	if ctx.frame == 1 || dt < 0 || dt > 0.25 {
		dt = 1.0 / 60
	}
	ctx.dt = dt
	ctx.time = time
	ctx.viewport = viewport
	ctx.scale = scale > 0 ? scale : 1
	ctx.input = input
	ctx.animating = false
	ctx.text_input_wanted = false
	if ctx.atlas.reset_requested {
		atlas_clear(&ctx.atlas)
	}

	when ODIN_OS == .JS {
		mem.dynamic_arena_free_all(&ctx.dyn_arena)
	} else {
		virtual.arena_free_all(&ctx.arena)
	}
	fa := ctx.frame_alloc
	ctx.nodes = make([dynamic]Node, 0, 512, fa)
	ctx.paras = make([dynamic]Paragraph, 0, 128, fa)
	ctx.stack = make([dynamic]i32, 0, 64, fa)
	ctx.positioned = make([dynamic]i32, 0, 64, fa)
	ctx.groups = make([dynamic]i32, 0, 16, fa)
	ctx.id_stack = make([dynamic]Id, 0, 16, fa)
	ctx.overlays = make([dynamic]i32, 0, 16, fa)
	ctx.occ = make(map[u64]u32, 512, fa)
	ctx.has_pending_key = false

	process_input(ctx)

	// root
	root := Node{
		id     = ROOT_ID,
		kind   = .Box,
		parent = -1,
		first  = -1,
		last   = -1,
		next   = -1,
		para   = -1,
		cb     = -1,
	}
	root.style = style_default()
	root.style.font_family = ctx.theme.default_font
	root.style.width = px(viewport.x)
	root.style.height = px(viewport.y)
	root.style.display = .Block
	root.state = state_get(ctx, root.id)
	append(&ctx.nodes, root)
	ctx.root = 0
	append(&ctx.stack, 0)
	append(&ctx.positioned, 0)
}

// Lays out, paints and prepares hit testing data. Returns the frame's draw list.
end_frame :: proc(ctx: ^Context) -> ^Draw_List {
	// close any unbalanced scopes
	resize(&ctx.stack, 1)
	layout_root(ctx)
	paint_root(ctx)
	gc_states(ctx)
	return &ctx.draw
}

@(private)
gc_states :: proc(ctx: ^Context) {
	if ctx.frame % 120 != 0 {
		return
	}
	stale := make([dynamic]Id, context.temp_allocator)
	for id, st in ctx.states {
		if ctx.frame - st.last_frame > 300 {
			append(&stale, id)
		}
	}
	for id in stale {
		st := ctx.states[id]
		if st.user != nil && st.user_free != nil {
			st.user_free(st.user)
		}
		delete_key(&ctx.states, id)
		free(st)
	}
}

state_get :: proc(ctx: ^Context, id: Id) -> ^Elem_State {
	st, ok := ctx.states[id]
	if !ok {
		st = new(Elem_State)
		st.scroll_active_t = -1000 // never scrolled yet
		ctx.states[id] = st
	}
	st.last_frame = ctx.frame
	return st
}

// ---------------------------------------------------------------------------
// Ids
// ---------------------------------------------------------------------------

@(private)
mix64 :: proc "contextless" (h: u64, v: u64) -> u64 {
	x := h ~ v
	x *= 0xff51afd7ed558ccd
	x ~= x >> 33
	x *= 0xc4ceb9fe1a85ec53
	x ~= x >> 33
	return x
}

hash_string :: proc "contextless" (s: string) -> u64 {
	return hash.fnv64a(transmute([]byte)s)
}

// Sets an explicit key for the next element (stable identity across reorders).
key :: proc(k: union {
		int,
		string,
	}) {
	ctx := g_ctx
	switch v in k {
	case int:
		ctx.pending_key = mix64(0x51ed27, u64(v))
	case string:
		ctx.pending_key = mix64(0xa0761d6478bd642f, hash_string(v))
	}
	ctx.has_pending_key = true
}

push_id :: proc(k: union {
		int,
		string,
	}) {
	ctx := g_ctx
	base := Id(0)
	if len(ctx.id_stack) > 0 {
		base = ctx.id_stack[len(ctx.id_stack) - 1]
	}
	v: u64
	switch x in k {
	case int:
		v = u64(x)
	case string:
		v = hash_string(x)
	}
	append(&ctx.id_stack, Id(mix64(u64(base) ~ 0x2545f4914f6cdd1d, v)))
}

pop_id :: proc() {
	ctx := g_ctx
	if len(ctx.id_stack) > 0 {
		pop(&ctx.id_stack)
	}
}

@(private)
make_id :: proc(ctx: ^Context, parent: ^Node, loc: runtime.Source_Code_Location) -> Id {
	base := u64(parent.id)
	if len(ctx.id_stack) > 0 {
		base = mix64(base, u64(ctx.id_stack[len(ctx.id_stack) - 1]))
	}
	if ctx.has_pending_key {
		ctx.has_pending_key = false
		return Id(mix64(base, ctx.pending_key))
	}
	site := mix64(u64(uintptr(raw_data(loc.file_path))), u64(loc.line) << 16 | u64(loc.column))
	k := mix64(base, site)
	n := ctx.occ[k]
	ctx.occ[k] = n + 1
	return Id(mix64(k, u64(n)))
}

// Id that the next element opened at `loc` under the current parent would get. Mostly for tests.
id_of :: proc(name: string) -> Id {
	ctx := g_ctx
	parent := &ctx.nodes[ctx.stack[len(ctx.stack) - 1]]
	return Id(mix64(u64(parent.id), mix64(0xa0761d6478bd642f, hash_string(name))))
}

// ---------------------------------------------------------------------------
// Tree building
// ---------------------------------------------------------------------------

Elem_Flag :: enum u8 {
	Selected,
	Checked,
	Disabled,
	Open,
	Focusable,
	No_Hit,
}
Elem_Flags :: bit_set[Elem_Flag;u8]

@(private)
open_node :: proc(ctx: ^Context, kind: Node_Kind, class: string, flags: Elem_Flags, loc: runtime.Source_Code_Location) -> i32 {
	pi := ctx.stack[len(ctx.stack) - 1]
	parent := &ctx.nodes[pi]
	n: Node
	n.kind = kind
	n.parent = pi
	n.first = -1
	n.last = -1
	n.next = -1
	n.para = -1
	n.baseline = -1
	n.index = parent.child_count
	n.id = make_id(ctx, parent, loc)
	n.class = class
	st := state_get(ctx, n.id)
	n.state = st

	// variant matching state
	m: Variants
	if st.hovered {
		m += {.Hover}
	}
	if st.active {
		m += {.Active}
	}
	if st.focused {
		m += {.Focus, .Focus_Within}
		if ctx.focus_visible {
			m += {.Focus_Visible}
		}
	}
	if .Disabled in flags {
		m += {.Disabled}
	} else {
		m += {.Enabled}
	}
	if .Selected in flags {
		m += {.Selected}
	}
	if .Checked in flags {
		m += {.Checked}
	}
	if .Open in flags {
		m += {.Open}
	}
	if ctx.dark {
		m += {.Dark}
	} else {
		m += {.Light}
	}
	if n.index == 0 {
		m += {.First}
	} else {
		m += {.Not_First}
	}
	pst := parent.state
	if pst != nil && pst.prev_children > 0 && n.index == pst.prev_children - 1 {
		m += {.Last}
		if n.index == 0 {
			m += {.Only}
		}
	} else {
		m += {.Not_Last}
	}
	if n.index % 2 == 0 {
		m += {.Odd}
	} else {
		m += {.Even}
	}
	if len(ctx.groups) > 0 {
		g := &ctx.nodes[ctx.groups[len(ctx.groups) - 1]]
		if g.state.hovered {
			m += {.Group_Hover}
		}
		if g.state.focused {
			m += {.Group_Focus}
		}
		if g.state.active {
			m += {.Group_Active}
		}
		if .Selected in g.match {
			m += {.Group_Selected}
		}
	}
	// focus-within propagates from previous frame focus chain
	n.match = m

	// style resolution
	n.style = style_default()
	style_inherit(&n.style, &parent.style)
	ms := Match_State{flags = m, viewport = ctx.viewport.x}
	if parent.cs != nil && parent.cs.has_children {
		apply_class_set(&n.style, parent.cs, &Match_State{flags = parent.match, viewport = ctx.viewport.x}, ctx.dark, true)
	}
	if class != "" {
		cs := class_set_for(ctx, class)
		n.cs = cs
		n.class = cs.source // cache-owned: callers may pass temp strings (cx, tprintf)
		apply_class_set(&n.style, cs, &ms, ctx.dark)
		if cs.is_group {
			n.flags += {.Has_Group}
		}
	}
	// parent-driven spacing (space-x/y, divide-x/y)
	ps := &parent.style
	if n.index > 0 {
		if ps.space.x != 0 {
			if ps.space_reverse.x {
				n.style.margin[1] += ps.space.x
			} else {
				n.style.margin[3] += ps.space.x
			}
		}
		if ps.space.y != 0 {
			if ps.space_reverse.y {
				n.style.margin[2] += ps.space.y
			} else {
				n.style.margin[0] += ps.space.y
			}
		}
		if ps.divide_w.x > 0 {
			side := ps.divide_reverse.x ? 1 : 3
			n.style.border_w[side] = ps.divide_w.x
			if ps.divide_color_set {
				if !n.style.border_color_set {
					n.style.border_color = {n.style.color, n.style.color, n.style.color, n.style.color}
				}
				n.style.border_color[side] = ps.divide_color
				n.style.border_color_set = true
			}
			n.style.border_style = ps.divide_style
		}
		if ps.divide_w.y > 0 {
			side := ps.divide_reverse.y ? 2 : 0
			n.style.border_w[side] = ps.divide_w.y
			if ps.divide_color_set {
				if !n.style.border_color_set {
					n.style.border_color = {n.style.color, n.style.color, n.style.color, n.style.color}
				}
				n.style.border_color[side] = ps.divide_color
				n.style.border_color_set = true
			}
			n.style.border_style = ps.divide_style
		}
	}
	if .Focusable in flags {
		n.flags += {.Focusable}
	}
	if .No_Hit in flags {
		n.flags += {.No_Hit}
	}

	// containing block for absolute children
	switch n.style.position {
	case .Absolute:
		n.cb = ctx.positioned[len(ctx.positioned) - 1]
	case .Fixed:
		n.cb = 0
	case .Static, .Relative, .Sticky:
		n.cb = -1
	}

	idx := i32(len(ctx.nodes))
	append(&ctx.nodes, n)
	parent = &ctx.nodes[pi]
	if parent.last >= 0 {
		ctx.nodes[parent.last].next = idx
	} else {
		parent.first = idx
	}
	parent.last = idx
	parent.child_count += 1
	return idx
}

@(private)
push_scope :: proc(ctx: ^Context, idx: i32) {
	append(&ctx.stack, idx)
	n := &ctx.nodes[idx]
	if n.style.position != .Static {
		append(&ctx.positioned, idx)
	}
	if .Has_Group in n.flags {
		append(&ctx.groups, idx)
	}
}

@(private)
pop_scope :: proc(ctx: ^Context) {
	if len(ctx.stack) <= 1 {
		return
	}
	idx := pop(&ctx.stack)
	n := &ctx.nodes[idx]
	n.state.prev_children = n.child_count
	if n.style.position != .Static && len(ctx.positioned) > 1 && ctx.positioned[len(ctx.positioned) - 1] == idx {
		pop(&ctx.positioned)
	}
	if .Has_Group in n.flags && len(ctx.groups) > 0 && ctx.groups[len(ctx.groups) - 1] == idx {
		pop(&ctx.groups)
	}
}

// Opens a container element. Use with `if`:
//     if ui.div("flex gap-4 p-6") { ... children ... }
@(deferred_none = close)
div :: proc(class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	idx := open_node(ctx, .Box, class, flags, loc)
	push_scope(ctx, idx)
	return true
}

// Opens a container without automatic closing; pair with ui.close(). Useful when
// building helpers that open a scope on behalf of the caller.
open :: proc(class: string = "", flags: Elem_Flags = {}, loc := #caller_location) {
	ctx := g_ctx
	idx := open_node(ctx, .Box, class, flags, loc)
	push_scope(ctx, idx)
}

// Closes the innermost open element (called automatically by `if ui.div(...)`).
close :: proc() {
	pop_scope(g_ctx)
}

// Leaf element without children (dividers, swatches, spacers...).
el :: proc(class: string = "", flags: Elem_Flags = {}, loc := #caller_location) {
	ctx := g_ctx
	idx := open_node(ctx, .Box, class, flags, loc)
	ctx.nodes[idx].state.prev_children = 0
}

// A focusable, clickable container. Query with ui.clicked() inside the scope.
@(deferred_none = close)
pressable :: proc(class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	f := flags
	if .Disabled not_in f {
		f += {.Focusable}
	}
	idx := open_node(ctx, .Box, class, f, loc)
	push_scope(ctx, idx)
	return true
}

// Text paragraph container. Add runs with ui.span().
@(deferred_none = close)
p :: proc(class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	idx := open_node(ctx, .Text, class, flags, loc)
	ctx.nodes[idx].para = new_paragraph(ctx)
	push_scope(ctx, idx)
	return true
}

@(private)
new_paragraph :: proc(ctx: ^Context) -> i32 {
	pr: Paragraph
	pr.spans = make([dynamic]Span, 0, 4, ctx.frame_alloc)
	pr.glyphs = make([dynamic]Text_Glyph, 0, 64, ctx.frame_alloc)
	pr.lines = make([dynamic]Text_Line, 0, 4, ctx.frame_alloc)
	pr.laid_w = -1
	append(&ctx.paras, pr)
	return i32(len(ctx.paras) - 1)
}

// Adds a text run to the current paragraph (inside ui.p). Outside a paragraph it acts like ui.text.
span :: proc(text: string, class: string = "", loc := #caller_location) {
	ctx := g_ctx
	pi := ctx.stack[len(ctx.stack) - 1]
	parent := &ctx.nodes[pi]
	if parent.kind != .Text || parent.para < 0 {
		_text(ctx, text, class, {}, loc)
		return
	}
	sp := Span{text = strings.clone(text, ctx.frame_alloc), node = -1}
	sp.style = parent.style
	sp.style.padding = {}
	sp.style.bg = TRANSPARENT
	sp.style.radius = {}
	sp.style.border_w = {}
	if class != "" {
		cs := class_set_for(ctx, class)
		ms := Match_State{flags = parent.match - {.Hover, .Active}, viewport = ctx.viewport.x}
		apply_class_set(&sp.style, cs, &ms, ctx.dark)
		sp.pad = sp.style.padding
	}
	append(&ctx.paras[parent.para].spans, sp)
}

// A text element (block-level paragraph with a single run).
text :: proc(str: string, class: string = "", flags: Elem_Flags = {}, loc := #caller_location) {
	_text(g_ctx, str, class, flags, loc)
}

@(private)
_text :: proc(ctx: ^Context, str: string, class: string, flags: Elem_Flags, loc: runtime.Source_Code_Location) {
	idx := open_node(ctx, .Text, class, flags, loc)
	n := &ctx.nodes[idx]
	n.para = new_paragraph(ctx)
	sp := Span{text = strings.clone(str, ctx.frame_alloc), node = idx, style = n.style}
	sp.style.padding = {}
	sp.style.bg = TRANSPARENT
	sp.style.border_w = {}
	sp.style.radius = {}
	append(&ctx.paras[n.para].spans, sp)
	n.state.prev_children = 0
}

// Vector icon. Size it with utilities (size-5), color with text-* or fill-*.
icon :: proc(ic: Icon, class: string = "size-5", flags: Elem_Flags = {}, loc := #caller_location) {
	ctx := g_ctx
	idx := open_node(ctx, .Icon, class, flags, loc)
	ctx.nodes[idx].icon = ic
}

// Raster image registered with image_register / image_load.
image :: proc(img: Image_Id, class: string = "", flags: Elem_Flags = {}, loc := #caller_location) {
	ctx := g_ctx
	idx := open_node(ctx, .Image, class, flags, loc)
	ctx.nodes[idx].image = img
}

// Element whose content is drawn by user code (charts, game views, ...).
canvas :: proc(class: string, draw: Custom_Draw, data: rawptr = nil, flags: Elem_Flags = {}, loc := #caller_location) {
	ctx := g_ctx
	idx := open_node(ctx, .Custom, class, flags, loc)
	ctx.nodes[idx].custom = draw
	ctx.nodes[idx].custom_data = data
}

// ---------------------------------------------------------------------------
// Queries on the current (innermost open) element
// ---------------------------------------------------------------------------

@(private)
cur_node :: proc() -> ^Node {
	ctx := g_ctx
	return &ctx.nodes[ctx.stack[len(ctx.stack) - 1]]
}

@(private)
last_node :: proc() -> ^Node {
	ctx := g_ctx
	return &ctx.nodes[len(ctx.nodes) - 1]
}

// Current element (the innermost open scope).
current :: proc() -> ^Node {
	return cur_node()
}

// Most recently created element (useful after leaf calls like ui.el / ui.text).
last :: proc() -> ^Node {
	return last_node()
}

// Mutable style of the innermost open element (apply after classes; affects children opened later).
style :: proc() -> ^Style {
	return &cur_node().style
}

// Style of the most recently created element.
last_style :: proc() -> ^Style {
	return &last_node().style
}

current_id :: proc() -> Id {
	return cur_node().id
}

hovered :: proc() -> bool {
	return cur_node().state.hovered
}
active :: proc() -> bool {
	return cur_node().state.active
}
focused :: proc() -> bool {
	return cur_node().state.focused
}
clicked :: proc() -> bool {
	return cur_node().state.clicked
}
right_clicked :: proc() -> bool {
	return cur_node().state.right_clicked
}
double_clicked :: proc() -> bool {
	return cur_node().state.double_clicked
}
// Clicked on this element itself rather than on a descendant (backdrops, empty areas).
// Clicks are reported to every ancestor of the topmost hit, like DOM event bubbling.
clicked_self :: proc() -> bool {
	return cur_node().state.clicked_self
}

last_hovered :: proc() -> bool {
	return last_node().state.hovered
}
last_clicked :: proc() -> bool {
	return last_node().state.clicked
}

// Rect of the current element as of the previous frame.
prev_rect :: proc() -> Rect {
	return cur_node().state.rect
}

// Persistent per-element storage (Compose `remember`). Returned pointer is stable.
remember :: proc($T: typeid, init: T, loc := #caller_location) -> ^T {
	ctx := g_ctx
	parent := cur_node()
	site := mix64(u64(uintptr(raw_data(loc.file_path))), u64(loc.line) << 16 | u64(loc.column))
	id := Id(mix64(u64(parent.id) ~ 0x7f4a7c159e3779b9, site))
	st := state_get(ctx, id)
	if st.user == nil {
		p := new(T)
		p^ = init
		st.user = p
		st.user_free = proc(ptr: rawptr) {
			free(ptr)
		}
	}
	return cast(^T)st.user
}

focus :: proc(id: Id) {
	ctx := g_ctx
	if ctx.focus_id != 0 {
		if st, ok := ctx.states[ctx.focus_id]; ok {
			st.focused = false
		}
	}
	ctx.focus_id = id
	if st, ok := ctx.states[id]; ok {
		st.focused = true
	}
}

// Requests the scroll container `id` to scroll so that its y offset becomes `y`.
scroll_to :: proc(id: Id, y: f32) {
	append(&g_ctx.scroll_requests, Scroll_Request{id, y})
}

scroll_of :: proc(id: Id) -> [2]f32 {
	if st, ok := g_ctx.states[id]; ok {
		return st.scroll
	}
	return {}
}

rect_of :: proc(id: Id) -> Rect {
	if st, ok := g_ctx.states[id]; ok {
		return st.rect
	}
	return {}
}

// Builds a class string with a temporary allocation: ui.cx("p-4", active ? "bg-sky-500" : "")
cx :: proc(parts: ..string) -> string {
	return strings.join(parts, " ", context.temp_allocator)
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

// Largest image edge accepted (a 4096^2 RGBA texture with mips is ~85 MB of GPU memory,
// shared with the desktop compositor on integrated GPUs). Returns 0 for invalid input.
MAX_IMAGE_SIZE :: 4096

image_register :: proc(ctx: ^Context, rgba: []u8, w, h: int) -> Image_Id {
	if w <= 0 || h <= 0 || w > MAX_IMAGE_SIZE || h > MAX_IMAGE_SIZE || len(rgba) < w * h * 4 {
		return 0
	}
	pix := make([]u8, w * h * 4)
	copy(pix, rgba)
	append(&ctx.images, Image_Def{w = w, h = h, pixels = pix, dirty = true})
	return Image_Id(len(ctx.images))
}

// Registers a texture the host already owns on the GPU (a game render target, a minimap
// texture). vui samples it but never uploads, mip-maps or frees it. Call image_external_update
// when the host recreates the texture. `nearest` samples without filtering on the SDL GPU
// backends (GL samples with the texture's own parameters).
image_register_external :: proc(ctx: ^Context, handle: u64, w, h: int, flip_y := false, nearest := false) -> Image_Id {
	append(&ctx.images, Image_Def{w = w, h = h, handle = handle, external = true, flip_y = flip_y, nearest = nearest})
	return Image_Id(len(ctx.images))
}

image_external_update :: proc(ctx: ^Context, img: Image_Id, handle: u64, w, h: int) {
	if img == 0 || int(img) > len(ctx.images) {
		return
	}
	d := &ctx.images[img - 1]
	d.handle = handle
	d.w = w
	d.h = h
}

// Names an image so classes can reference it: `bg-tex-<name>` paints it as a textured fill.
image_name :: proc(ctx: ^Context, name: string, img: Image_Id) {
	if _, ok := ctx.image_names[name]; ok {
		ctx.image_names[name] = img
		return
	}
	ctx.image_names[strings.clone(name)] = img
}

@(private)
image_lookup :: proc(name: string) -> Image_Id {
	ctx := g_ctx
	if ctx == nil {
		return 0
	}
	return ctx.image_names[name]
}

image_size :: proc(ctx: ^Context, img: Image_Id) -> [2]f32 {
	if img == 0 || int(img) > len(ctx.images) {
		return {}
	}
	d := ctx.images[img - 1]
	return {f32(d.w), f32(d.h)}
}

// ---------------------------------------------------------------------------
// Easing
// ---------------------------------------------------------------------------

// Solves a CSS cubic-bezier timing function at x in [0, 1].
ease :: proc "contextless" (e: Easing, x: f32) -> f32 {
	if x <= 0 {
		return 0
	}
	if x >= 1 {
		return 1
	}
	if e == EASE_LINEAR {
		return x
	}
	bez :: proc "contextless" (a, b, t: f32) -> f32 {
		// 1D cubic with P0=0, P3=1
		u := 1 - t
		return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
	}
	dbez :: proc "contextless" (a, b, t: f32) -> f32 {
		u := 1 - t
		return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
	}
	t := x
	for _ in 0 ..< 8 {
		fx := bez(e[0], e[2], t) - x
		d := dbez(e[0], e[2], t)
		if abs(fx) < 1e-5 {
			break
		}
		if abs(d) < 1e-6 {
			break
		}
		t -= fx / d
	}
	if t < 0 || t > 1 || abs(bez(e[0], e[2], t) - x) > 1e-3 {
		lo: f32 = 0
		hi: f32 = 1
		t = x
		for _ in 0 ..< 24 {
			v := bez(e[0], e[2], t)
			if v < x {
				lo = t
			} else {
				hi = t
			}
			t = (lo + hi) / 2
		}
	}
	return bez(e[1], e[3], t)
}

// Advances a transition track toward `target`. Returns the current value.
track_step :: proc(ctx: ^Context, tr: ^Anim_Track, target: [4]f32, enabled: bool, st: ^Style) -> [4]f32 {
	if !tr.init {
		tr.init = true
		tr.from = target
		tr.to = target
		tr.moving = false
		return target
	}
	cur := track_value(ctx, tr, st)
	if target != tr.to {
		if !enabled || st.duration_ms <= 0 {
			tr.from = target
			tr.to = target
			tr.moving = false
			return target
		}
		tr.from = cur
		tr.to = target
		tr.start = ctx.time + f64(st.delay_ms) / 1000
		tr.moving = true
		cur = track_value(ctx, tr, st)
	}
	if tr.moving {
		ctx.animating = true
	}
	return cur
}

@(private)
track_value :: proc(ctx: ^Context, tr: ^Anim_Track, st: ^Style) -> [4]f32 {
	if !tr.moving {
		return tr.to
	}
	dur := f64(max(st.duration_ms, 1)) / 1000
	x := f32((ctx.time - tr.start) / dur)
	if x >= 1 {
		tr.moving = false
		tr.from = tr.to
		return tr.to
	}
	if x < 0 {
		return tr.from
	}
	k := ease(st.easing, x)
	return tr.from + (tr.to - tr.from) * k
}

track_color :: proc(ctx: ^Context, tr: ^Anim_Track, target: Color, enabled: bool, st: ^Style) -> Color {
	// interpolate premultiplied
	pm := [4]f32{target.r * target.a, target.g * target.a, target.b * target.a, target.a}
	v := track_step(ctx, tr, pm, enabled, st)
	if v.a <= 1e-5 {
		return {target.r, target.g, target.b, 0}
	}
	return {v.r / v.a, v.g / v.a, v.b / v.a, v.a}
}

@(private)
_unused_math :: proc() -> f32 {
	return math.PI
}

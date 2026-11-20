package vui

import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

// Behaviour-only primitives. They draw nothing on their own: every pixel comes from
// the classes you pass, styled through variants (hover:, focus-visible:, checked:, ...).

// A focusable button with a text label. Returns true when activated (click / Enter / Space).
button :: proc(label: string, class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	f := flags
	if .Disabled not_in f {
		f += {.Focusable}
	}
	idx := open_node(ctx, .Text, class, f, loc)
	n := &ctx.nodes[idx]
	n.para = new_paragraph(ctx)
	sp := Span{text = strings.clone(label, ctx.frame_alloc), node = idx, style = n.style}
	sp.style.padding = {}
	sp.style.bg = TRANSPARENT
	sp.style.border_w = {}
	sp.style.radius = {}
	append(&ctx.paras[n.para].spans, sp)
	n.state.prev_children = 0
	if n.style.cursor == .Auto {
		n.style.cursor = .Pointer
	}
	return n.state.clicked && .Disabled not_in flags
}

// Clickable container variant: `if ui.button_box("...") { ui.icon(..) }` then ui.clicked().
@(deferred_none = close)
button_box :: proc(class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	f := flags
	if .Disabled not_in f {
		f += {.Focusable}
	}
	idx := open_node(ctx, .Box, class, f, loc)
	if ctx.nodes[idx].style.cursor == .Auto {
		ctx.nodes[idx].style.cursor = .Pointer
	}
	push_scope(ctx, idx)
	return true
}

// Toggles *value on click. Use `checked:` variants to style the on state.
@(deferred_none = close)
checkbox :: proc(value: ^bool, class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	f := flags
	if value^ {
		f += {.Checked}
	}
	if .Disabled not_in f {
		f += {.Focusable}
	}
	// read last frame's click state before resolving styles
	idx := open_node(ctx, .Box, class, f, loc)
	n := &ctx.nodes[idx]
	if n.state.clicked && .Disabled not_in flags {
		value^ = !value^
		// re-resolve with the new checked state
		n.match ~= {.Checked}
		restyle(ctx, idx)
	}
	if n.style.cursor == .Auto {
		n.style.cursor = .Pointer
	}
	push_scope(ctx, idx)
	return true
}

// Selects `option` into *value on click (radio-group behaviour).
@(deferred_none = close)
radio :: proc(value: ^int, option: int, class: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> bool {
	ctx := g_ctx
	f := flags
	if value^ == option {
		f += {.Checked, .Selected}
	}
	if .Disabled not_in f {
		f += {.Focusable}
	}
	idx := open_node(ctx, .Box, class, f, loc)
	n := &ctx.nodes[idx]
	if n.state.clicked && .Disabled not_in flags && value^ != option {
		value^ = option
		n.match += {.Checked, .Selected}
		restyle(ctx, idx)
	}
	if n.style.cursor == .Auto {
		n.style.cursor = .Pointer
	}
	push_scope(ctx, idx)
	return true
}

@(private)
restyle :: proc(ctx: ^Context, idx: i32) {
	n := &ctx.nodes[idx]
	parent := &ctx.nodes[n.parent]
	n.style = style_default()
	style_inherit(&n.style, &parent.style)
	if parent.cs != nil && parent.cs.has_children {
		apply_class_set(&n.style, parent.cs, &Match_State{flags = parent.match, viewport = ctx.viewport.x}, ctx.dark, true)
	}
	if n.cs != nil {
		apply_class_set(&n.style, n.cs, &Match_State{flags = n.match, viewport = ctx.viewport.x}, ctx.dark)
	}
}

// Horizontal slider. The track is the element itself; draws a thumb + fill using `fill_class`
// and `thumb_class`. Returns true when the value changed.
slider :: proc(value: ^f32, lo, hi: f32, class: string, fill_class: string, thumb_class: string, step: f32 = 0, loc := #caller_location) -> bool {
	ctx := g_ctx
	idx := open_node(ctx, .Box, class, {.Focusable}, loc)
	n := &ctx.nodes[idx]
	st := n.state
	changed := false
	r := st.rect
	if st.active && r.w > 0 {
		t := clamp((ctx.input.mouse.x - r.x) / r.w, 0, 1)
		v := lo + (hi - lo) * t
		if step > 0 {
			v = math.round((v - lo) / step) * step + lo
		}
		if v != value^ {
			value^ = v
			changed = true
		}
	}
	if st.focused {
		dv := step > 0 ? step : (hi - lo) / 100
		if .Left in ctx.input.keys_pressed || .Down in ctx.input.keys_pressed {
			value^ = clamp(value^ - dv, lo, hi)
			changed = true
		}
		if .Right in ctx.input.keys_pressed || .Up in ctx.input.keys_pressed {
			value^ = clamp(value^ + dv, lo, hi)
			changed = true
		}
	}
	if n.style.cursor == .Auto {
		n.style.cursor = .Pointer
	}
	if n.style.position == .Static {
		n.style.position = .Relative
	}
	push_scope(ctx, idx)
	t := hi > lo ? (value^ - lo) / (hi - lo) : 0
	el(fill_class)
	fs := last_style()
	fs.position = .Absolute
	fs.inset = {px(0), AUTO, px(0), px(0)}
	fs.width = pct(t * 100)
	el(thumb_class)
	ts := last_style()
	ts.position = .Absolute
	ts.inset = {pct(50), AUTO, AUTO, pct(t * 100)}
	ts.translate = {pct(-50), pct(-50)}
	pop_scope(ctx)
	return changed
}

// ---------------------------------------------------------------------------
// Text input
// ---------------------------------------------------------------------------

Input_Result :: struct {
	changed:   bool,
	submitted: bool,
}

@(private)
prev_rune_offset :: proc(s: string, i: int) -> int {
	if i <= 0 {
		return 0
	}
	_, size := utf8.decode_last_rune_in_string(s[:i])
	return i - size
}

@(private)
next_rune_offset :: proc(s: string, i: int) -> int {
	if i >= len(s) {
		return len(s)
	}
	_, size := utf8.decode_rune_in_string(s[i:])
	return i + size
}

@(private)
word_left :: proc(s: string, i: int) -> int {
	j := i
	for j > 0 && s[j - 1] == ' ' {
		j -= 1
	}
	for j > 0 && s[j - 1] != ' ' {
		j -= 1
	}
	return j
}

@(private)
word_right :: proc(s: string, i: int) -> int {
	j := i
	for j < len(s) && s[j] == ' ' {
		j += 1
	}
	for j < len(s) && s[j] != ' ' {
		j += 1
	}
	return j
}

// Single-line text field editing `buf`. Style the box with `class`; placeholder color
// with `placeholder:text-*`, caret with `caret-*`, selection with `selection:bg-*`.
text_input :: proc(buf: ^[dynamic]u8, class: string = "", placeholder: string = "", flags: Elem_Flags = {}, loc := #caller_location) -> (res: Input_Result) {
	ctx := g_ctx
	idx := open_node(ctx, .Box, class, flags + {.Focusable}, loc)
	n := &ctx.nodes[idx]
	n.flags += {.Text_Input}
	if n.style.cursor == .Auto {
		n.style.cursor = .Text
	}
	if n.style.overflow_x == .Visible {
		n.style.overflow_x = .Hidden
	}
	st := n.state
	ed := &st.edit
	s := string(buf[:])
	ed.cursor = clamp(ed.cursor, 0, len(s))
	ed.anchor = clamp(ed.anchor, 0, len(s))
	in_ := &ctx.input
	style_copy := n.style
	pb := pad_border(&style_copy)

	if st.focused && .Disabled not_in flags {
		ctx.text_input_wanted = true
		ctx.text_input_rect = st.rect
		shift := .Shift in in_.mods
		ctrl := .Ctrl in in_.mods || .Super in in_.mods
		lo := min(ed.cursor, ed.anchor)
		hi := max(ed.cursor, ed.anchor)
		delete_sel :: proc(buf: ^[dynamic]u8, ed: ^Edit_State) -> bool {
			lo := min(ed.cursor, ed.anchor)
			hi := max(ed.cursor, ed.anchor)
			if lo == hi {
				return false
			}
			remove_range(buf, lo, hi)
			ed.cursor = lo
			ed.anchor = lo
			return true
		}
		move :: proc(ed: ^Edit_State, to: int, shift: bool) {
			ed.cursor = to
			if !shift {
				ed.anchor = to
			}
		}
		k := in_.keys_pressed
		if ctrl && .A in k {
			ed.anchor = 0
			ed.cursor = len(s)
		}
		if ctrl && (.C in k || .X in k) && lo != hi && ctx.clipboard_set != nil {
			ctx.clipboard_set(s[lo:hi])
			if .X in k {
				res.changed = delete_sel(buf, ed) || res.changed
			}
		}
		if ctrl && .V in k && ctx.clipboard_get != nil {
			clip := ctx.clipboard_get(context.temp_allocator)
			clip, _ = strings.replace_all(clip, "\n", " ", context.temp_allocator)
			delete_sel(buf, ed)
			inject_at(buf, ed.cursor, ..transmute([]u8)clip)
			ed.cursor += len(clip)
			ed.anchor = ed.cursor
			res.changed = true
		}
		if len(in_.text) > 0 && !ctrl {
			delete_sel(buf, ed)
			inject_at(buf, ed.cursor, ..transmute([]u8)in_.text)
			ed.cursor += len(in_.text)
			ed.anchor = ed.cursor
			res.changed = true
		}
		s = string(buf[:])
		if .Backspace in k {
			if !delete_sel(buf, ed) && ed.cursor > 0 {
				from := ctrl ? word_left(s, ed.cursor) : prev_rune_offset(s, ed.cursor)
				remove_range(buf, from, ed.cursor)
				ed.cursor = from
				ed.anchor = from
			}
			res.changed = true
		}
		s = string(buf[:])
		if .Delete in k {
			if !delete_sel(buf, ed) && ed.cursor < len(s) {
				to := ctrl ? word_right(s, ed.cursor) : next_rune_offset(s, ed.cursor)
				remove_range(buf, ed.cursor, to)
			}
			res.changed = true
		}
		s = string(buf[:])
		if .Left in k {
			if lo != hi && !shift {
				move(ed, lo, false)
			} else {
				move(ed, ctrl ? word_left(s, ed.cursor) : prev_rune_offset(s, ed.cursor), shift)
			}
		}
		if .Right in k {
			if lo != hi && !shift {
				move(ed, hi, false)
			} else {
				move(ed, ctrl ? word_right(s, ed.cursor) : next_rune_offset(s, ed.cursor), shift)
			}
		}
		if .Home in k {
			move(ed, 0, shift)
		}
		if .End in k {
			move(ed, len(s), shift)
		}
		if .Enter in k {
			res.submitted = true
		}
		if k != {} || len(in_.text) > 0 {
			ed.blink_t = ctx.time
		}
	}
	s = string(buf[:])

	// caret positioning by mouse
	offsets, xs := caret_stops(&ctx.fonts, &ctx.theme, s, &style_copy)
	if st.pressed_now || (st.active && ed.dragging) {
		mx := in_.mouse.x - st.rect.x - pb[3] + ed.scroll_x
		best := 0
		bd := f32(1e9)
		for x, i in xs {
			d := abs(x - mx)
			if d < bd {
				bd = d
				best = i
			}
		}
		ed.cursor = offsets[best]
		if st.pressed_now && .Shift not_in in_.mods {
			ed.anchor = ed.cursor
		}
		if st.pressed_now && in_.click_count >= 2 {
			ed.anchor = word_left(s, ed.cursor)
			ed.cursor = word_right(s, ed.cursor)
		}
		ed.dragging = true
		ed.blink_t = ctx.time
	}
	if !st.active {
		ed.dragging = false
	}

	cursor_x: f32 = 0
	anchor_x: f32 = 0
	for o, i in offsets {
		if o == ed.cursor {
			cursor_x = xs[i]
		}
		if o == ed.anchor {
			anchor_x = xs[i]
		}
	}
	inner_w := st.rect.w - pb[1] - pb[3]
	if inner_w > 0 {
		if cursor_x - ed.scroll_x > inner_w - 2 {
			ed.scroll_x = cursor_x - inner_w + 2
		}
		if cursor_x - ed.scroll_x < 0 {
			ed.scroll_x = cursor_x
		}
		ed.scroll_x = max(0, min(ed.scroll_x, max(0, xs[len(xs) - 1] - inner_w + 2)))
	}

	push_scope(ctx, idx)
	{
		// content: selection, text/placeholder, caret
		if st.focused && ed.cursor != ed.anchor {
			sel := style_copy.selection_set ? style_copy.selection_bg : Color{0.2, 0.5, 1, 0.3}
			x0 := min(cursor_x, anchor_x) - ed.scroll_x
			x1 := max(cursor_x, anchor_x) - ed.scroll_x
			el()
			ss := last_style()
			ss.position = .Absolute
			ss.inset = {px(pb[0]), AUTO, px(pb[2]), px(pb[3] + x0)}
			ss.width = px(x1 - x0)
			ss.bg = sel
			last_node().flags += {.No_Hit}
		}
		show := s
		if len(s) == 0 && placeholder != "" {
			show = placeholder
		}
		text(show, "whitespace-pre")
		ts := last_style()
		if len(s) == 0 {
			ts.color = style_copy.placeholder_set ? style_copy.placeholder : fade(style_copy.color, 0.45)
		}
		ts.margin[3] = -ed.scroll_x
		last_node().flags += {.No_Hit}
		blink := math.mod(ctx.time - ed.blink_t, 1.06) < 0.53
		if st.focused {
			ctx.animating = true
			if blink {
				lh := line_height_px(&style_copy)
				el()
				cs := last_style()
				cs.position = .Absolute
				cs.width = px(max(1, 1.5 / ctx.scale * ctx.scale))
				cs.height = px(lh)
				cs.inset = {pct(50), AUTO, AUTO, px(pb[3] + cursor_x - ed.scroll_x)}
				cs.translate = {px(0), pct(-50)}
				cs.bg = style_copy.caret_set ? style_copy.caret : style_copy.color
				last_node().flags += {.No_Hit}
			}
		}
	}
	pop_scope(ctx)
	if ctx.nodes[idx].style.position == .Static {
		ctx.nodes[idx].style.position = .Relative
	}
	return
}

// ---------------------------------------------------------------------------
// Debug dump (used by the control CLI)
// ---------------------------------------------------------------------------

// Writes the current tree (as of the last end_frame) as JSON lines into sb.
debug_tree :: proc(ctx: ^Context, sb: ^strings.Builder, max_depth := 64) {
	strings.write_string(sb, "[")
	first := true
	walk :: proc(ctx: ^Context, ni: i32, depth: int, max_depth: int, sb: ^strings.Builder, first: ^bool) {
		if depth > max_depth {
			return
		}
		n := &ctx.nodes[ni]
		if n.style.display == .None {
			return
		}
		if !first^ {
			strings.write_string(sb, ",")
		}
		first^ = false
		txt := ""
		if n.para >= 0 {
			pr := &ctx.paras[n.para]
			b := strings.builder_make(context.temp_allocator)
			for sp in pr.spans {
				strings.write_string(&b, sp.text)
			}
			txt = strings.to_string(b)
		}
		fmt.sbprintf(sb, `{{"i":%d,"d":%d,"id":"%x","k":"%v","x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f`, ni, depth, u64(n.id), n.kind, n.rect.x, n.rect.y, n.rect.w, n.rect.h)
		if n.class != "" {
			strings.write_string(sb, `,"c":`)
			json_str(sb, n.class)
		}
		if txt != "" {
			strings.write_string(sb, `,"t":`)
			json_str(sb, txt)
		}
		if n.state != nil && n.state.hovered {
			strings.write_string(sb, `,"hover":true`)
		}
		if n.state != nil && n.state.focused {
			strings.write_string(sb, `,"focus":true`)
		}
		strings.write_string(sb, "}")
		for c := n.first; c >= 0; c = ctx.nodes[c].next {
			walk(ctx, c, depth + 1, max_depth, sb, first)
		}
	}
	if len(ctx.nodes) > 0 {
		walk(ctx, 0, 0, max_depth, sb, &first)
	}
	strings.write_string(sb, "]")
}

json_str :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(sb, `\"`)
		case '\\':
			strings.write_string(sb, `\\`)
		case '\n':
			strings.write_string(sb, `\n`)
		case '\t':
			strings.write_string(sb, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(sb, `\u%04x`, r)
			} else {
				strings.write_rune(sb, r)
			}
		}
	}
	strings.write_byte(sb, '"')
}

// Finds the first node whose text contains `needle` (case-insensitive). Returns its center.
find_text :: proc(ctx: ^Context, needle: string, nth := 0) -> (center: [2]f32, ok: bool) {
	lower := strings.to_lower(needle, context.temp_allocator)
	count := 0
	for &n, i in ctx.nodes {
		if n.para < 0 || n.style.display == .None || n.rect.w <= 0 {
			continue
		}
		_ = i
		pr := &ctx.paras[n.para]
		b := strings.builder_make(context.temp_allocator)
		for sp in pr.spans {
			strings.write_string(&b, sp.text)
		}
		t := strings.to_lower(strings.to_string(b), context.temp_allocator)
		if strings.contains(t, lower) {
			if count == nth {
				c := [2]f32{n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2}
				return xform_apply(n.xform, c), true
			}
			count += 1
		}
	}
	return {}, false
}

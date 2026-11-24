package vui

import "core:math"

// Hit testing runs at the start of a frame against the previous frame's layout
// (immediate-mode one-frame latency). Interaction results are written into the
// persistent Elem_State of each element, so builder code can query them.

@(private)
hit_test_point :: proc(h: ^Hit, p: [2]f32) -> bool {
	q := p
	if h.has_xf {
		q = xform_apply(h.inv, p)
	}
	if !rect_contains(h.clip, p) {
		return false
	}
	if !rect_contains(h.rect, q) {
		return false
	}
	// rounded corners
	r := h.rect
	lx := q.x - r.x
	ly := q.y - r.y
	check :: proc(dx, dy, rad: f32) -> bool {
		return dx * dx + dy * dy <= rad * rad
	}
	if rad := h.radius[0]; rad > 0 && lx < rad && ly < rad {
		return check(rad - lx, rad - ly, rad)
	}
	if rad := h.radius[1]; rad > 0 && lx > r.w - rad && ly < rad {
		return check(lx - (r.w - rad), rad - ly, rad)
	}
	if rad := h.radius[2]; rad > 0 && lx > r.w - rad && ly > r.h - rad {
		return check(lx - (r.w - rad), ly - (r.h - rad), rad)
	}
	if rad := h.radius[3]; rad > 0 && lx < rad && ly > r.h - rad {
		return check(rad - lx, ly - (r.h - rad), rad)
	}
	return true
}

// Index of the topmost hit under p (or -1).
hit_at :: proc(ctx: ^Context, p: [2]f32) -> i32 {
	for i := len(ctx.hits) - 1; i >= 0; i -= 1 {
		h := &ctx.hits[i]
		if !h.pointer && h.thumb == 0 {
			continue
		}
		if hit_test_point(h, p) {
			return i32(i)
		}
	}
	return -1
}

@(private)
process_input :: proc(ctx: ^Context) {
	in_ := &ctx.input
	// reset per-frame flags
	for _, st in ctx.states {
		st.hovered = false
		st.clicked = false
		st.right_clicked = false
		st.double_clicked = false
		st.clicked_self = false
		st.pressed_now = false
		st.released_now = false
	}

	// scroll requests
	for req in ctx.scroll_requests {
		if st, ok := ctx.states[req.id]; ok {
			st.scroll_target.y = clamp(req.offset, 0, max(st.scroll_max.y, 0))
		}
	}
	clear(&ctx.scroll_requests)

	top: i32 = -1
	if in_.mouse_inside {
		top = hit_at(ctx, in_.mouse)
	}
	ctx.cursor = .Default
	ctx.hover_id = 0

	// scrollbar thumb dragging
	if ctx.drag_thumb != 0 {
		if .Left in in_.buttons {
			if st, ok := ctx.states[ctx.drag_thumb]; ok {
				axis := ctx.drag_axis
				r := st.rect
				track := axis == 1 ? r.h : r.w
				content := track + st.scroll_max[axis]
				ratio := content > 0 ? track / content : 1
				delta := (axis == 1 ? in_.mouse.y - ctx.drag_start.y : in_.mouse.x - ctx.drag_start.x) / max(ratio, 0.01)
				v := clamp(ctx.drag_scroll0 + delta, 0, st.scroll_max[axis])
				st.scroll_target[axis] = v
				st.scroll[axis] = v
			}
			ctx.cursor = .Default
			top = -1
		} else {
			ctx.drag_thumb = 0
		}
	}

	if top >= 0 {
		h := &ctx.hits[top]
		if h.thumb != 0 {
			if .Left in in_.pressed {
				ctx.drag_thumb = h.id
				ctx.drag_axis = h.thumb == 1 ? 1 : 0
				ctx.drag_start = in_.mouse
				if st, ok := ctx.states[h.id]; ok {
					ctx.drag_scroll0 = st.scroll[ctx.drag_axis]
				}
			}
			// thumb hover keeps owner hovered
			if st, ok := ctx.states[h.id]; ok {
				st.hovered = true
			}
			top = -1
		} else {
			ctx.hover_id = h.id
			ctx.cursor = h.cursor
			i := top
			for i >= 0 {
				hh := &ctx.hits[i]
				if hh.thumb == 0 {
					if st, ok := ctx.states[hh.id]; ok {
						st.hovered = true
					}
				}
				i = hh.parent
			}
		}
	}

	// press / release
	if .Left in in_.pressed && top >= 0 {
		ctx.press_id = ctx.hits[top].id
		new_focus: Id = 0
		i := top
		for i >= 0 {
			hh := &ctx.hits[i]
			if st, ok := ctx.states[hh.id]; ok {
				st.active = true
				st.pressed_now = true
			}
			if new_focus == 0 && (hh.focusable || hh.text_input) {
				new_focus = hh.id
			}
			i = hh.parent
		}
		set_focus(ctx, new_focus, false)
	} else if .Left in in_.pressed && top < 0 && ctx.drag_thumb == 0 {
		set_focus(ctx, 0, false)
	}
	if .Left in in_.released {
		for id, st in ctx.states {
			if st.active {
				st.active = false
				st.released_now = true
				if st.hovered {
					st.clicked = true
					st.clicked_self = id == ctx.press_id && ctx.hover_id == id
					if in_.click_count >= 2 {
						st.double_clicked = true
					}
				}
				_ = id
			}
		}
		ctx.press_id = 0
	}
	if .Right in in_.released && top >= 0 {
		i := top
		for i >= 0 {
			hh := &ctx.hits[i]
			if st, ok := ctx.states[hh.id]; ok {
				st.right_clicked = true
			}
			i = hh.parent
		}
	}

	// keyboard focus traversal
	if .Tab in in_.keys_pressed {
		forward := .Shift not_in in_.mods
		move_focus(ctx, forward)
	}
	if ctx.focus_id != 0 {
		if st, ok := ctx.states[ctx.focus_id]; ok {
			if (.Enter in in_.keys_pressed || .Space in in_.keys_pressed) && !is_text_input_focused(ctx) {
				st.clicked = true
			}
			if .Escape in in_.keys_pressed {
				set_focus(ctx, 0, false)
			}
		}
	}

	// wheel: innermost scroll container under the pointer that can move
	if (in_.wheel.x != 0 || in_.wheel.y != 0) && in_.mouse_inside {
		wtop := hit_at(ctx, in_.mouse)
		dx := in_.wheel.x
		dy := in_.wheel.y
		if .Shift in in_.mods && dx == 0 {
			dx = dy
			dy = 0
		}
		i := wtop
		for i >= 0 && (dx != 0 || dy != 0) {
			hh := &ctx.hits[i]
			if st, ok := ctx.states[hh.id]; ok && hh.thumb == 0 {
				if hh.scroll[1] && dy != 0 {
					before := st.scroll_target.y
					st.scroll_target.y = clamp(st.scroll_target.y + dy, 0, max(st.scroll_max.y, 0))
					if st.scroll_target.y != before {
						dy = 0
					}
				}
				if hh.scroll[0] && dx != 0 {
					before := st.scroll_target.x
					st.scroll_target.x = clamp(st.scroll_target.x + dx, 0, max(st.scroll_max.x, 0))
					if st.scroll_target.x != before {
						dx = 0
					}
				}
			}
			i = hh.parent
		}
	}

	// smooth scrolling
	k := 1 - math.exp(-ctx.dt * 22)
	for _, st in ctx.states {
		for a in 0 ..< 2 {
			st.scroll_target[a] = clamp(st.scroll_target[a], 0, max(st.scroll_max[a], 0))
			d := st.scroll_target[a] - st.scroll[a]
			if abs(d) < 0.25 {
				st.scroll[a] = st.scroll_target[a]
			} else {
				st.scroll[a] += d * k
				st.scroll_active_t = ctx.time
				ctx.animating = true
			}
		}
	}
}

@(private)
is_text_input_focused :: proc(ctx: ^Context) -> bool {
	for h in ctx.hits {
		if h.id == ctx.focus_id {
			return h.text_input
		}
	}
	return false
}

@(private)
set_focus :: proc(ctx: ^Context, id: Id, visible: bool) {
	if ctx.focus_id == id {
		ctx.focus_visible = visible && id != 0
		return
	}
	if ctx.focus_id != 0 {
		if st, ok := ctx.states[ctx.focus_id]; ok {
			st.focused = false
		}
	}
	ctx.focus_id = id
	ctx.focus_visible = visible
	if id != 0 {
		if st, ok := ctx.states[id]; ok {
			st.focused = true
			st.edit.blink_t = ctx.time
		}
	}
}

@(private)
move_focus :: proc(ctx: ^Context, forward: bool) {
	order := make([dynamic]Id, context.temp_allocator)
	for h in ctx.hits {
		if h.focusable || h.text_input {
			append(&order, h.id)
		}
	}
	if len(order) == 0 {
		return
	}
	cur := -1
	for id, i in order {
		if id == ctx.focus_id {
			cur = i
			break
		}
	}
	next: int
	if cur < 0 {
		next = forward ? 0 : len(order) - 1
	} else {
		next = (cur + (forward ? 1 : len(order) - 1)) % len(order)
	}
	set_focus(ctx, order[next], true)
}

// True when the pointer rests on an element that takes pointer events (last processed frame).
// Hosts that draw a world under the UI (games, map views) route clicks to the world only when
// this is false: lay the HUD out with `pointer-events-none` on full-screen wrappers and
// `pointer-events-auto` on the panels that should catch the mouse.
pointer_over_ui :: proc {
	pointer_over_ui_hover,
	pointer_over_ui_at,
}

// Hover-based: the element under the pointer when the last frame began.
pointer_over_ui_hover :: proc(ctx: ^Context) -> bool {
	if ctx.press_id != 0 && ctx.press_id != ROOT_ID {
		return true // a press that started on UI keeps the pointer captured until release
	}
	return ctx.hover_id != 0 && ctx.hover_id != ROOT_ID
}

// Position-based: hit-tests p against the last laid-out frame. Use this when the host decides
// where a click goes *before* it builds this frame's UI (a game that builds its HUD after the
// camera update, so world-anchored labels never lag a frame).
pointer_over_ui_at :: proc(ctx: ^Context, p: [2]f32) -> bool {
	if ctx.press_id != 0 && ctx.press_id != ROOT_ID {
		return true
	}
	top := hit_at(ctx, p)
	return top >= 0 && ctx.hits[top].id != ROOT_ID
}

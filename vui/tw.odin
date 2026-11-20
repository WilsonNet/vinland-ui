package vui

import "core:strconv"
import "core:strings"

// Utility-class engine. A class string such as
//     "flex items-center gap-4 rounded-xl bg-white p-6 shadow-lg dark:bg-gray-800 hover:bg-sky-50"
// is parsed once into a Class_Set (cached by string) of Rules. Each frame the rules whose
// variants match the element's state are applied, in order, on top of the inherited style.

Variant :: enum u8 {
	Hover,
	Focus,
	Focus_Visible,
	Focus_Within,
	Active,
	Disabled,
	Enabled,
	Group_Hover,
	Group_Focus,
	Group_Active,
	Group_Selected,
	First,
	Last,
	Odd,
	Even,
	Only,
	Dark,
	Light,
	Selected,
	Checked,
	Open,
	Children,
	Placeholder,
	Selection,
	Not_First,
	Not_Last,
	Empty,
}
Variants :: bit_set[Variant;u32]

Prop :: enum u16 {
	None,
	Group,
	Display,
	Position,
	Flex_Dir,
	Flex_Wrap,
	Justify,
	Align_Items,
	Align_Self,
	Align_Content,
	Justify_Items,
	Justify_Self,
	Place_Content,
	Place_Items,
	Place_Self,
	Grow,
	Shrink,
	Basis,
	Flex,
	Order,
	Gap,
	Grid_Cols,
	Grid_Rows,
	Auto_Cols,
	Auto_Rows,
	Grid_Flow,
	Col_Span,
	Col_Start,
	Col_End,
	Row_Span,
	Row_Start,
	Row_End,
	Width,
	Height,
	Min_W,
	Min_H,
	Max_W,
	Max_H,
	Aspect,
	Padding,
	Margin,
	Inset,
	Z,
	Overflow_X,
	Overflow_Y,
	Box_Sizing,
	Space,
	Space_Reverse,
	Divide_W,
	Divide_Reverse,
	Divide_Color,
	Divide_Style,
	Bg_Color,
	Bg_Gradient,
	Grad_From,
	Grad_Via,
	Grad_To,
	Grad_From_Pos,
	Grad_Via_Pos,
	Grad_To_Pos,
	Bg_Stripes,
	Bg_None,
	Border_W,
	Border_Color,
	Border_Current,
	Border_Style,
	Radius,
	Shadow,
	Shadow_Color,
	Inset_Shadow,
	Inset_Shadow_Color,
	Ring_W,
	Ring_Color,
	Ring_Inset,
	Inset_Ring_W,
	Inset_Ring_Color,
	Ring_Offset_W,
	Ring_Offset_Color,
	Outline_W,
	Outline_Color,
	Outline_Offset,
	Outline_Style,
	Opacity,
	Visibility,
	Translate,
	Scale,
	Rotate,
	Skew,
	Origin,
	Transform_None,
	Blur,
	Brightness,
	Contrast,
	Grayscale,
	Hue_Rotate,
	Invert,
	Saturate,
	Sepia,
	Drop_Shadow,
	Drop_Shadow_Color,
	Filter_None,
	Backdrop_Blur,
	Backdrop_Opacity,
	Object_Fit,
	Object_Pos,
	Cursor,
	Pointer_Events,
	User_Select,
	Accent,
	Caret,
	Fill,
	Transition,
	Duration,
	Delay,
	Ease,
	Animation,
	Font_Family,
	Font_Size,
	Line_Height,
	Font_Weight,
	Italic,
	Tracking,
	Text_Color,
	Text_Align,
	Text_Transform,
	Decoration,
	Decoration_Color,
	Decoration_Style,
	Decoration_Thickness,
	Underline_Offset,
	White_Space,
	Text_Wrap,
	Word_Break,
	Truncate,
	Text_Overflow,
	Line_Clamp,
	Indent,
	Font_Variant,
	Text_Shadow,
	Text_Shadow_Color,
	List_Style,
	List_Pos,
}

Rule :: struct {
	variants: Variants,
	bp_min:   f32, // viewport min-width, 0 = none
	bp_max:   f32, // viewport max-width (exclusive), 0 = none
	prop:     Prop,
	mask:     u8, // sides / corners / axes
	i:        i32,
	f:        [4]f32,
	sz:       Size,
	tok:      Color_Token,
	s:        string,
	idx:      i32, // into Class_Set.shadows / grids
}

Class_Set :: struct {
	source:   string,
	rules:    []Rule,
	shadows:  []Shadow_Set,
	grids:    []Grid_Template,
	unknown:  []string, // utilities that did not parse (debug)
	is_group: bool,
	has_children: bool,
	variants_used: Variants,
}

@(private)
Builder :: struct {
	theme:    ^Theme,
	rules:    [dynamic]Rule,
	shadows:  [dynamic]Shadow_Set,
	grids:    [dynamic]Grid_Template,
	unknown:  [dynamic]string,
	variants: Variants,
	bp_min:   f32,
	bp_max:   f32,
	is_group: bool,
}

@(private)
push :: proc(b: ^Builder, r: Rule) {
	rr := r
	rr.variants = b.variants
	rr.bp_min = b.bp_min
	rr.bp_max = b.bp_max
	append(&b.rules, rr)
}

// Parses a class string. Results are owned by the class cache in Context.
parse_classes :: proc(t: ^Theme, src: string, allocator := context.allocator) -> ^Class_Set {
	context.allocator = allocator
	b := Builder{theme = t}
	s := src
	for tok in strings.fields_iterator(&s) {
		parse_token(&b, tok)
	}
	cs := new(Class_Set)
	cs.source = strings.clone(src)
	cs.rules = b.rules[:]
	cs.shadows = b.shadows[:]
	cs.grids = b.grids[:]
	cs.unknown = b.unknown[:]
	cs.is_group = b.is_group
	for r in cs.rules {
		cs.variants_used += r.variants
		if .Children in r.variants {
			cs.has_children = true
		}
	}
	return cs
}

class_set_destroy :: proc(cs: ^Class_Set) {
	delete(cs.source)
	for r in cs.rules {
		if r.s != "" {
			delete(r.s)
		}
	}
	delete(cs.rules)
	delete(cs.shadows)
	delete(cs.grids)
	for u in cs.unknown {
		delete(u)
	}
	delete(cs.unknown)
	free(cs)
}

@(private)
parse_token :: proc(b: ^Builder, tok: string) {
	// split variants on ':' outside brackets
	parts: [8]string
	n := 0
	depth := 0
	start := 0
	for i in 0 ..< len(tok) {
		switch tok[i] {
		case '[', '(':
			depth += 1
		case ']', ')':
			depth -= 1
		case ':':
			if depth == 0 && n < 7 {
				parts[n] = tok[start:i]
				n += 1
				start = i + 1
			}
		}
	}
	parts[n] = tok[start:]
	n += 1

	b.variants = {}
	b.bp_min = 0
	b.bp_max = 0
	for v in parts[:n - 1] {
		if !parse_variant(b, v) {
			append(&b.unknown, strings.clone(tok))
			return
		}
	}
	util := parts[n - 1]
	util = strings.trim_prefix(util, "!")
	util = strings.trim_suffix(util, "!")
	neg := false
	if strings.has_prefix(util, "-") {
		neg = true
		util = util[1:]
	}
	if !parse_utility(b, util, neg) {
		append(&b.unknown, strings.clone(tok))
	}
}

@(private)
parse_variant :: proc(b: ^Builder, v: string) -> bool {
	switch v {
	case "hover":
		b.variants += {.Hover}
	case "focus":
		b.variants += {.Focus}
	case "focus-visible":
		b.variants += {.Focus_Visible}
	case "focus-within":
		b.variants += {.Focus_Within}
	case "active":
		b.variants += {.Active}
	case "disabled":
		b.variants += {.Disabled}
	case "enabled":
		b.variants += {.Enabled}
	case "group-hover":
		b.variants += {.Group_Hover}
	case "group-focus", "group-focus-within", "group-focus-visible":
		b.variants += {.Group_Focus}
	case "group-active":
		b.variants += {.Group_Active}
	case "group-aria-selected", "group-data-selected", "group-selected":
		b.variants += {.Group_Selected}
	case "first":
		b.variants += {.First}
	case "last":
		b.variants += {.Last}
	case "odd":
		b.variants += {.Odd}
	case "even":
		b.variants += {.Even}
	case "only":
		b.variants += {.Only}
	case "not-first":
		b.variants += {.Not_First}
	case "not-last":
		b.variants += {.Not_Last}
	case "empty":
		b.variants += {.Empty}
	case "dark":
		b.variants += {.Dark}
	case "light", "not-dark":
		b.variants += {.Light}
	case "aria-selected", "data-selected", "selected", "aria-current", "data-active":
		b.variants += {.Selected}
	case "checked", "aria-checked", "data-checked":
		b.variants += {.Checked}
	case "open", "data-open", "aria-expanded":
		b.variants += {.Open}
	case "*":
		b.variants += {.Children}
	case "placeholder", "placeholder-shown":
		b.variants += {.Placeholder}
	case "selection":
		b.variants += {.Selection}
	case "motion-safe", "contrast-more", "pointer-fine", "any-pointer-fine", "hover-hover":
	// always true on desktop
	case "motion-reduce", "print", "contrast-less", "pointer-coarse", "forced-colors":
		b.bp_min = 1e9 // never matches
	case:
		if bp, ok := b.theme.breakpoints[v]; ok {
			b.bp_min = bp
			return true
		}
		if strings.has_prefix(v, "max-") {
			if bp, ok := b.theme.breakpoints[v[4:]]; ok {
				b.bp_max = bp
				return true
			}
		}
		if strings.has_prefix(v, "min-[") || strings.has_prefix(v, "max-[") {
			if px_, ok := parse_length(strings.trim(v[4:], "[]")); ok {
				if v[1] == 'i' {
					b.bp_min = px_
				} else {
					b.bp_max = px_
				}
				return true
			}
		}
		if strings.has_prefix(v, "group-") || strings.has_prefix(v, "peer-") || strings.has_prefix(v, "in-") || strings.has_prefix(v, "has-") || strings.has_prefix(v, "data-") || strings.has_prefix(v, "aria-") || strings.has_prefix(v, "supports-") || strings.has_prefix(v, "@") {
			b.bp_min = 1e9 // unsupported: rule never applies (but class still parses)
			return true
		}
		return false
	}
	return true
}

// ---------- value helpers ----------

@(private)
arbitrary :: proc(s: string) -> (string, bool) {
	if len(s) >= 2 && s[0] == '[' && s[len(s) - 1] == ']' {
		return s[1:len(s) - 1], true
	}
	return "", false
}

@(private)
parse_num :: proc(s: string) -> (f32, bool) {
	if s == "" {
		return 0, false
	}
	for c in s {
		if !((c >= '0' && c <= '9') || c == '.') {
			return 0, false
		}
	}
	return strconv.parse_f32(s)
}

@(private)
spacing :: proc(t: ^Theme, s: string) -> (f32, bool) {
	if s == "px" {
		return 1, true
	}
	if s == "0" {
		return 0, true
	}
	if a, ok := arbitrary(s); ok {
		return parse_length(a)
	}
	if n, ok := parse_num(s); ok {
		return n * t.spacing, true
	}
	return 0, false
}

@(private)
fraction :: proc(s: string) -> (f32, bool) {
	slash := strings.index_byte(s, '/')
	if slash <= 0 {
		return 0, false
	}
	a, aok := parse_num(s[:slash])
	c, cok := parse_num(s[slash + 1:])
	if !aok || !cok || c == 0 {
		return 0, false
	}
	return a / c * 100, true
}

@(private)
arbitrary_size :: proc(a: string) -> (Size, bool) {
	if strings.has_suffix(a, "%") {
		v, ok := strconv.parse_f32(a[:len(a) - 1])
		return pct(v), ok
	}
	if strings.has_suffix(a, "vw") {
		v, ok := strconv.parse_f32(a[:len(a) - 2])
		return {.Vw, v}, ok
	}
	if strings.has_suffix(a, "vh") {
		v, ok := strconv.parse_f32(a[:len(a) - 2])
		return {.Vh, v}, ok
	}
	v, ok := parse_length(a)
	return px(v), ok
}

// Sizing values for w-*, h-*, min-*, max-*, basis-*, inset, translate.
@(private)
size_value :: proc(t: ^Theme, s: string, horizontal: bool, allow_containers: bool) -> (Size, bool) {
	switch s {
	case "auto":
		return AUTO, true
	case "full":
		return pct(100), true
	case "screen", "dvw", "svw", "lvw", "dvh", "svh", "lvh":
		if s == "screen" {
			return horizontal ? Size{.Vw, 100} : Size{.Vh, 100}, true
		}
		return s[len(s) - 1] == 'w' ? Size{.Vw, 100} : Size{.Vh, 100}, true
	case "min":
		return {.Min_Content, 0}, true
	case "max":
		return {.Max_Content, 0}, true
	case "fit":
		return {.Fit_Content, 0}, true
	case "px":
		return px(1), true
	case "none":
		return {.Auto, 0}, true
	}
	if a, ok := arbitrary(s); ok {
		return arbitrary_size(a)
	}
	if f, ok := fraction(s); ok {
		return pct(f), true
	}
	if n, ok := parse_num(s); ok {
		return px(n * t.spacing), true
	}
	if allow_containers {
		if c, ok := t.containers[s]; ok {
			return px(c), true
		}
		if strings.has_prefix(s, "screen-") {
			if bp, bok := t.breakpoints[s[7:]]; bok {
				return px(bp), true
			}
		}
	}
	return {}, false
}

// Color with optional "/50" or "/[0.37]" opacity modifier.
@(private)
color_value :: proc(t: ^Theme, s: string) -> (tok: Color_Token, ok: bool) {
	name := s
	alpha: f32 = 1
	has_alpha := false
	if a, aok := arbitrary(s); aok {
		c, cok := parse_css_color(strings.trim_space(a))
		return {c, c}, cok
	}
	slash := strings.last_index_byte(s, '/')
	if slash > 0 && !strings.has_suffix(s, "]") || (slash > 0 && strings.contains(s[slash:], "[")) {
		mod := s[slash + 1:]
		name = s[:slash]
		if a, aok := arbitrary(mod); aok {
			v, vok := strconv.parse_f32(strings.trim_suffix(a, "%"))
			if !vok {
				return {}, false
			}
			alpha = strings.has_suffix(a, "%") || v > 1 ? v / 100 : v
		} else {
			v, vok := parse_num(mod)
			if !vok {
				return {}, false
			}
			alpha = v / 100
		}
		has_alpha = true
	}
	if a, aok := arbitrary(name); aok {
		c, cok := parse_css_color(a)
		if !cok {
			return {}, false
		}
		tok = {c, c}
	} else {
		tok, ok = t.colors[name]
		if !ok {
			return {}, false
		}
	}
	if has_alpha {
		tok.light.a *= alpha
		tok.dark.a *= alpha
	}
	return tok, true
}

@(private)
is_color :: proc(t: ^Theme, s: string) -> bool {
	_, ok := color_value(t, s)
	return ok || s == "current" || s == "inherit"
}

@(private)
color_rule :: proc(b: ^Builder, prop: Prop, s: string, mask: u8 = 0) -> bool {
	if s == "current" || s == "inherit" {
		if prop == .Border_Color {
			push(b, {prop = .Border_Current})
			return true
		}
		r := Rule{prop = prop, mask = mask, i = 1} // i=1 means currentColor
		push(b, r)
		return true
	}
	tok, ok := color_value(b.theme, s)
	if !ok {
		return false
	}
	push(b, {prop = prop, tok = tok, mask = mask})
	return true
}

// "t r b l" side masks
SIDE_T :: 1
SIDE_R :: 2
SIDE_B :: 4
SIDE_L :: 8
SIDES_ALL :: 15
SIDES_X :: SIDE_L | SIDE_R
SIDES_Y :: SIDE_T | SIDE_B

@(private)
side_mask :: proc(prefix: string) -> (u8, bool) {
	switch prefix {
	case "":
		return SIDES_ALL, true
	case "x", "inline":
		return SIDES_X, true
	case "y", "block":
		return SIDES_Y, true
	case "t":
		return SIDE_T, true
	case "r", "e", "inline-end":
		return SIDE_R, true
	case "b":
		return SIDE_B, true
	case "l", "s", "inline-start":
		return SIDE_L, true
	}
	return 0, false
}

// corners tl=1 tr=2 br=4 bl=8
@(private)
corner_mask :: proc(prefix: string) -> (u8, bool) {
	switch prefix {
	case "":
		return 15, true
	case "t":
		return 1 | 2, true
	case "r", "e":
		return 2 | 4, true
	case "b":
		return 4 | 8, true
	case "l", "s":
		return 1 | 8, true
	case "tl", "ss":
		return 1, true
	case "tr", "se":
		return 2, true
	case "br", "ee":
		return 4, true
	case "bl", "es":
		return 8, true
	}
	return 0, false
}

@(private)
parse_track_list :: proc(t: ^Theme, s: string) -> (g: Grid_Template, ok: bool) {
	if n, nok := parse_num(s); nok {
		c := int(n)
		if c < 1 || c > MAX_TRACKS {
			return {}, false
		}
		for i in 0 ..< c {
			g.tracks[i] = {.Fr, 1}
		}
		g.count = u8(c)
		return g, true
	}
	if s == "none" {
		return {}, true
	}
	if s == "subgrid" {
		g.subgrid = true
		return g, true
	}
	a, aok := arbitrary(s)
	if !aok {
		return {}, false
	}
	list := a
	for part in strings.split_iterator(&list, "_") {
		if part == "" {
			continue
		}
		if g.count >= MAX_TRACKS {
			break
		}
		tr: Track
		switch {
		case strings.has_suffix(part, "fr"):
			v, vok := strconv.parse_f32(part[:len(part) - 2])
			if !vok {
				return {}, false
			}
			tr = {.Fr, v}
		case part == "auto":
			tr = {.Auto, 0}
		case part == "min-content":
			tr = {.Min_Content, 0}
		case part == "max-content":
			tr = {.Max_Content, 0}
		case strings.has_prefix(part, "minmax("):
			// minmax(a,b): use max part
			inner := strings.trim_suffix(part[7:], ")")
			comma := strings.index_byte(inner, ',')
			if comma < 0 {
				return {}, false
			}
			mx := inner[comma + 1:]
			if strings.has_suffix(mx, "fr") {
				v, _ := strconv.parse_f32(mx[:len(mx) - 2])
				tr = {.Fr, v}
			} else {
				v, _ := parse_length(mx)
				tr = {.Px, v}
			}
		case strings.has_suffix(part, "%"):
			v, _ := strconv.parse_f32(part[:len(part) - 1])
			tr = {.Percent, v}
		case:
			v, vok := parse_length(part)
			if !vok {
				return {}, false
			}
			tr = {.Px, v}
		}
		g.tracks[g.count] = tr
		g.count += 1
	}
	return g, true
}

@(private)
shadow_with_color :: proc(set: Shadow_Set) -> Shadow_Set {
	return set
}

@(private)
parse_arbitrary_shadow :: proc(a: string) -> (Shadow_Set, bool) {
	// "0_35px_35px_rgba(0,0,0,0.25)" or "0_0_0_1px_#000"
	set: Shadow_Set
	list := a
	for one in strings.split_iterator(&list, ",") {
		_ = one
		break
	}
	s: Shadow
	nums: [4]f32
	nn := 0
	rest := a
	inset := false
	parts := strings.split(rest, "_", context.temp_allocator)
	color := rgb(0, 0.25)
	// rejoin rgba(...) fragments split by underscores
	i := 0
	for i < len(parts) {
		p := parts[i]
		if p == "inset" {
			inset = true
		} else if strings.has_prefix(p, "#") || strings.has_prefix(p, "rgb") {
			col := p
			for !strings.contains(col, ")") && strings.has_prefix(col, "rgb") && i + 1 < len(parts) {
				i += 1
				col = strings.concatenate({col, " ", parts[i]}, context.temp_allocator)
			}
			if c, ok := parse_css_color(col); ok {
				color = c
			}
		} else if v, ok := parse_length(p); ok && nn < 4 {
			nums[nn] = v
			nn += 1
		}
		i += 1
	}
	if nn < 2 {
		return {}, false
	}
	s.offset = {nums[0], nums[1]}
	s.blur = nums[2]
	s.spread = nums[3]
	s.color = color
	s.inset = inset
	set.items[0] = s
	set.count = 1
	return set, true
}

@(private)
parse_ease :: proc(a: string) -> (Easing, bool) {
	// cubic-bezier(0.95,0.05,0.795,0.035)
	open := strings.index_byte(a, '(')
	close := strings.last_index_byte(a, ')')
	if open < 0 || close < open {
		return {}, false
	}
	inner := a[open + 1:close]
	e: Easing
	k := 0
	for p in strings.split_iterator(&inner, ",") {
		if k >= 4 {
			break
		}
		v, ok := strconv.parse_f32(strings.trim_space(p))
		if !ok {
			return {}, false
		}
		e[k] = v
		k += 1
	}
	return e, k == 4
}

// ---------- utilities ----------

@(private)
parse_utility :: proc(b: ^Builder, u: string, neg: bool) -> bool {
	t := b.theme
	sign: f32 = neg ? -1 : 1

	// exact keywords first
	switch u {
	case "group":
		b.is_group = true
		push(b, {prop = .Group})
		return true
	case "peer":
		return true
	case "block":
		push(b, {prop = .Display, i = i32(Display.Block)})
		return true
	case "flex":
		push(b, {prop = .Display, i = i32(Display.Flex)})
		return true
	case "grid":
		push(b, {prop = .Display, i = i32(Display.Grid)})
		return true
	case "inline":
		push(b, {prop = .Display, i = i32(Display.Inline)})
		return true
	case "inline-block":
		push(b, {prop = .Display, i = i32(Display.Inline_Block)})
		return true
	case "inline-flex":
		push(b, {prop = .Display, i = i32(Display.Inline_Flex)})
		return true
	case "inline-grid":
		push(b, {prop = .Display, i = i32(Display.Inline_Grid)})
		return true
	case "hidden":
		push(b, {prop = .Display, i = i32(Display.None)})
		return true
	case "contents":
		push(b, {prop = .Display, i = i32(Display.Contents)})
		return true
	case "flow-root", "table", "table-row", "table-cell", "list-item":
		push(b, {prop = .Display, i = i32(Display.Block)})
		return true
	case "static":
		push(b, {prop = .Position, i = i32(Position.Static)})
		return true
	case "relative":
		push(b, {prop = .Position, i = i32(Position.Relative)})
		return true
	case "absolute":
		push(b, {prop = .Position, i = i32(Position.Absolute)})
		return true
	case "fixed":
		push(b, {prop = .Position, i = i32(Position.Fixed)})
		return true
	case "sticky":
		push(b, {prop = .Position, i = i32(Position.Sticky)})
		return true
	case "flex-row":
		push(b, {prop = .Flex_Dir, i = i32(Flex_Dir.Row)})
		return true
	case "flex-col":
		push(b, {prop = .Flex_Dir, i = i32(Flex_Dir.Column)})
		return true
	case "flex-row-reverse":
		push(b, {prop = .Flex_Dir, i = i32(Flex_Dir.Row_Reverse)})
		return true
	case "flex-col-reverse":
		push(b, {prop = .Flex_Dir, i = i32(Flex_Dir.Column_Reverse)})
		return true
	case "flex-wrap":
		push(b, {prop = .Flex_Wrap, i = i32(Flex_Wrap.Wrap)})
		return true
	case "flex-nowrap":
		push(b, {prop = .Flex_Wrap, i = i32(Flex_Wrap.No_Wrap)})
		return true
	case "flex-wrap-reverse":
		push(b, {prop = .Flex_Wrap, i = i32(Flex_Wrap.Wrap_Reverse)})
		return true
	case "flex-1":
		push(b, {prop = .Flex, f = {1, 1, 0, 0}, sz = pct(0)})
		return true
	case "flex-auto":
		push(b, {prop = .Flex, f = {1, 1, 0, 0}, sz = AUTO})
		return true
	case "flex-initial":
		push(b, {prop = .Flex, f = {0, 1, 0, 0}, sz = AUTO})
		return true
	case "flex-none":
		push(b, {prop = .Flex, f = {0, 0, 0, 0}, sz = AUTO})
		return true
	case "grow":
		push(b, {prop = .Grow, f = {1, 0, 0, 0}})
		return true
	case "shrink":
		push(b, {prop = .Shrink, f = {1, 0, 0, 0}})
		return true
	case "box-border":
		push(b, {prop = .Box_Sizing, i = 0})
		return true
	case "box-content":
		push(b, {prop = .Box_Sizing, i = 1})
		return true
	case "space-x-reverse":
		push(b, {prop = .Space_Reverse, mask = 1})
		return true
	case "space-y-reverse":
		push(b, {prop = .Space_Reverse, mask = 2})
		return true
	case "divide-x-reverse":
		push(b, {prop = .Divide_Reverse, mask = 1})
		return true
	case "divide-y-reverse":
		push(b, {prop = .Divide_Reverse, mask = 2})
		return true
	case "divide-x":
		push(b, {prop = .Divide_W, mask = 1, f = {1, 0, 0, 0}})
		return true
	case "divide-y":
		push(b, {prop = .Divide_W, mask = 2, f = {1, 0, 0, 0}})
		return true
	case "border":
		push(b, {prop = .Border_W, mask = SIDES_ALL, f = {1, 0, 0, 0}})
		return true
	case "border-solid", "border-dashed", "border-dotted", "border-double", "border-none", "border-hidden":
		push(b, {prop = .Border_Style, i = i32(line_style(u[7:]))})
		return true
	case "divide-solid", "divide-dashed", "divide-dotted", "divide-double", "divide-none":
		push(b, {prop = .Divide_Style, i = i32(line_style(u[7:]))})
		return true
	case "rounded":
		push(b, {prop = .Radius, mask = 15, f = {4, 0, 0, 0}})
		return true
	case "shadow":
		push_shadow(b, .Shadow, t.shadows["sm"])
		return true
	case "ring":
		push(b, {prop = .Ring_W, f = {1, 0, 0, 0}})
		return true
	case "inset-ring":
		push(b, {prop = .Inset_Ring_W, f = {1, 0, 0, 0}})
		return true
	case "ring-inset":
		push(b, {prop = .Ring_Inset})
		return true
	case "outline":
		push(b, {prop = .Outline_W, f = {1, 0, 0, 0}})
		return true
	case "outline-none":
		push(b, {prop = .Outline_Style, i = i32(Line_Style.None)})
		return true
	case "outline-hidden":
		push(b, {prop = .Outline_Style, i = i32(Line_Style.Hidden)})
		return true
	case "outline-solid", "outline-dashed", "outline-dotted", "outline-double":
		push(b, {prop = .Outline_Style, i = i32(line_style(u[8:]))})
		return true
	case "visible":
		push(b, {prop = .Visibility, i = i32(Visibility.Visible)})
		return true
	case "invisible":
		push(b, {prop = .Visibility, i = i32(Visibility.Invisible)})
		return true
	case "collapse":
		push(b, {prop = .Visibility, i = i32(Visibility.Collapse)})
		return true
	case "transform", "transform-gpu", "transform-cpu":
		return true
	case "transform-none":
		push(b, {prop = .Transform_None})
		return true
	case "filter", "backdrop-filter":
		return true
	case "filter-none":
		push(b, {prop = .Filter_None})
		return true
	case "blur":
		push(b, {prop = .Blur, f = {8, 0, 0, 0}})
		return true
	case "grayscale":
		push(b, {prop = .Grayscale, f = {1, 0, 0, 0}})
		return true
	case "invert":
		push(b, {prop = .Invert, f = {1, 0, 0, 0}})
		return true
	case "sepia":
		push(b, {prop = .Sepia, f = {1, 0, 0, 0}})
		return true
	case "drop-shadow":
		push_shadow(b, .Drop_Shadow, t.drop_shadows["sm"])
		return true
	case "transition":
		push(b, {prop = .Transition, i = i32(transmute(u8)Trans_Props{.Colors, .Opacity, .Shadow, .Transform, .Filter})})
		return true
	case "transition-all":
		push(b, {prop = .Transition, i = i32(transmute(u8)Trans_Props{.Colors, .Opacity, .Shadow, .Transform, .Filter, .Size})})
		return true
	case "transition-colors":
		push(b, {prop = .Transition, i = i32(transmute(u8)Trans_Props{.Colors})})
		return true
	case "transition-opacity":
		push(b, {prop = .Transition, i = i32(transmute(u8)Trans_Props{.Opacity})})
		return true
	case "transition-shadow":
		push(b, {prop = .Transition, i = i32(transmute(u8)Trans_Props{.Shadow})})
		return true
	case "transition-transform":
		push(b, {prop = .Transition, i = i32(transmute(u8)Trans_Props{.Transform})})
		return true
	case "transition-none":
		push(b, {prop = .Transition, i = 0})
		return true
	case "animate-none":
		push(b, {prop = .Animation, i = i32(Animation.None)})
		return true
	case "animate-spin":
		push(b, {prop = .Animation, i = i32(Animation.Spin)})
		return true
	case "animate-ping":
		push(b, {prop = .Animation, i = i32(Animation.Ping)})
		return true
	case "animate-pulse":
		push(b, {prop = .Animation, i = i32(Animation.Pulse)})
		return true
	case "animate-bounce":
		push(b, {prop = .Animation, i = i32(Animation.Bounce)})
		return true
	case "italic":
		push(b, {prop = .Italic, i = 1})
		return true
	case "not-italic":
		push(b, {prop = .Italic, i = 0})
		return true
	case "uppercase":
		push(b, {prop = .Text_Transform, i = i32(Text_Transform.Upper)})
		return true
	case "lowercase":
		push(b, {prop = .Text_Transform, i = i32(Text_Transform.Lower)})
		return true
	case "capitalize":
		push(b, {prop = .Text_Transform, i = i32(Text_Transform.Capitalize)})
		return true
	case "normal-case":
		push(b, {prop = .Text_Transform, i = i32(Text_Transform.None)})
		return true
	case "underline":
		push(b, {prop = .Decoration, i = 1, mask = u8(transmute(u8)Decoration{.Underline})})
		return true
	case "overline":
		push(b, {prop = .Decoration, i = 1, mask = u8(transmute(u8)Decoration{.Overline})})
		return true
	case "line-through":
		push(b, {prop = .Decoration, i = 1, mask = u8(transmute(u8)Decoration{.Line_Through})})
		return true
	case "no-underline":
		push(b, {prop = .Decoration, i = 0, mask = 0})
		return true
	case "truncate":
		push(b, {prop = .Truncate})
		return true
	case "text-ellipsis":
		push(b, {prop = .Text_Overflow, i = 1})
		return true
	case "text-clip":
		push(b, {prop = .Text_Overflow, i = 0})
		return true
	case "text-left":
		push(b, {prop = .Text_Align, i = i32(Text_Align.Left)})
		return true
	case "text-center":
		push(b, {prop = .Text_Align, i = i32(Text_Align.Center)})
		return true
	case "text-right":
		push(b, {prop = .Text_Align, i = i32(Text_Align.Right)})
		return true
	case "text-justify":
		push(b, {prop = .Text_Align, i = i32(Text_Align.Justify)})
		return true
	case "text-start":
		push(b, {prop = .Text_Align, i = i32(Text_Align.Start)})
		return true
	case "text-end":
		push(b, {prop = .Text_Align, i = i32(Text_Align.End)})
		return true
	case "text-wrap":
		push(b, {prop = .Text_Wrap, i = i32(Text_Wrap.Wrap)})
		return true
	case "text-nowrap":
		push(b, {prop = .Text_Wrap, i = i32(Text_Wrap.No_Wrap)})
		return true
	case "text-balance":
		push(b, {prop = .Text_Wrap, i = i32(Text_Wrap.Balance)})
		return true
	case "text-pretty":
		push(b, {prop = .Text_Wrap, i = i32(Text_Wrap.Pretty)})
		return true
	case "whitespace-normal":
		push(b, {prop = .White_Space, i = i32(White_Space.Normal)})
		return true
	case "whitespace-nowrap":
		push(b, {prop = .White_Space, i = i32(White_Space.No_Wrap)})
		return true
	case "whitespace-pre":
		push(b, {prop = .White_Space, i = i32(White_Space.Pre)})
		return true
	case "whitespace-pre-wrap":
		push(b, {prop = .White_Space, i = i32(White_Space.Pre_Wrap)})
		return true
	case "whitespace-pre-line":
		push(b, {prop = .White_Space, i = i32(White_Space.Pre_Line)})
		return true
	case "whitespace-break-spaces":
		push(b, {prop = .White_Space, i = i32(White_Space.Break_Spaces)})
		return true
	case "break-normal":
		push(b, {prop = .Word_Break, i = i32(Word_Break.Normal)})
		return true
	case "break-all":
		push(b, {prop = .Word_Break, i = i32(Word_Break.Break_All)})
		return true
	case "break-keep":
		push(b, {prop = .Word_Break, i = i32(Word_Break.Keep_All)})
		return true
	case "wrap-anywhere":
		push(b, {prop = .Word_Break, i = i32(Word_Break.Anywhere)})
		return true
	case "wrap-break-word", "break-words":
		push(b, {prop = .Word_Break, i = i32(Word_Break.Break_Word)})
		return true
	case "wrap-normal":
		push(b, {prop = .Word_Break, i = i32(Word_Break.Normal)})
		return true
	case "tabular-nums":
		push(b, {prop = .Font_Variant, i = 1, mask = u8(transmute(u8)Font_Variants{.Tabular})})
		return true
	case "slashed-zero":
		push(b, {prop = .Font_Variant, i = 1, mask = u8(transmute(u8)Font_Variants{.Slashed_Zero})})
		return true
	case "oldstyle-nums":
		push(b, {prop = .Font_Variant, i = 1, mask = u8(transmute(u8)Font_Variants{.Oldstyle})})
		return true
	case "lining-nums":
		push(b, {prop = .Font_Variant, i = 1, mask = u8(transmute(u8)Font_Variants{.Lining})})
		return true
	case "normal-nums", "proportional-nums", "ordinal", "stacked-fractions", "diagonal-fractions":
		push(b, {prop = .Font_Variant, i = 0, mask = 0})
		return true
	case "antialiased", "subpixel-antialiased":
		return true
	case "pointer-events-none":
		push(b, {prop = .Pointer_Events, i = 0})
		return true
	case "pointer-events-auto":
		push(b, {prop = .Pointer_Events, i = 1})
		return true
	case "select-none":
		push(b, {prop = .User_Select, i = 0})
		return true
	case "select-text", "select-all", "select-auto":
		push(b, {prop = .User_Select, i = 1})
		return true
	case "list-none":
		push(b, {prop = .List_Style, i = 0})
		return true
	case "list-disc":
		push(b, {prop = .List_Style, i = 1})
		return true
	case "list-decimal":
		push(b, {prop = .List_Style, i = 2})
		return true
	case "list-inside":
		push(b, {prop = .List_Pos, i = 1})
		return true
	case "list-outside":
		push(b, {prop = .List_Pos, i = 0})
		return true
	case "bg-none":
		push(b, {prop = .Bg_None})
		return true
	case "isolate", "isolation-auto", "appearance-none", "appearance-auto", "resize", "resize-none", "resize-x", "resize-y", "scroll-smooth", "scroll-auto", "sr-only", "not-sr-only", "forced-color-adjust-auto", "forced-color-adjust-none", "will-change-auto", "will-change-transform", "will-change-scroll", "will-change-contents", "touch-auto", "touch-none", "touch-manipulation", "snap-start", "snap-end", "snap-center", "snap-x", "snap-y", "snap-mandatory", "snap-proximity", "snap-none", "snap-align-none", "snap-normal", "snap-always", "container", "backface-visible", "backface-hidden", "transform-3d", "transform-flat", "field-sizing-content", "field-sizing-fixed", "decoration-clone", "decoration-slice", "box-decoration-clone", "box-decoration-slice", "bg-fixed", "bg-local", "bg-scroll", "bg-clip-border", "bg-clip-padding", "bg-clip-content", "bg-clip-text", "bg-origin-border", "bg-origin-padding", "bg-origin-content", "bg-repeat", "bg-no-repeat", "bg-repeat-x", "bg-repeat-y", "bg-repeat-round", "bg-repeat-space", "bg-auto", "bg-center", "bg-top", "bg-bottom", "bg-left", "bg-right", "table-auto", "table-fixed", "border-collapse", "border-separate", "caption-top", "caption-bottom", "float-left", "float-right", "float-none", "float-start", "float-end", "clear-left", "clear-right", "clear-both", "clear-none", "clear-start", "clear-end", "break-after-auto", "break-before-auto", "break-inside-auto", "align-baseline", "align-top", "align-middle", "align-bottom", "align-text-top", "align-text-bottom", "align-sub", "align-super", "hyphens-none", "hyphens-manual", "hyphens-auto", "mix-blend-normal", "mix-blend-multiply", "mix-blend-screen", "mix-blend-overlay", "bg-blend-normal", "bg-blend-multiply", "content-none", "overscroll-auto", "overscroll-contain", "overscroll-none", "columns-auto", "font-stretch-normal":
		// Parsed and accepted; no visual effect in this renderer (documented in the showroom).
		return true
	case "bg-cover":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.Cover), mask = 1})
		return true
	case "bg-contain":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.Contain), mask = 1})
		return true
	case "object-contain":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.Contain)})
		return true
	case "object-cover":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.Cover)})
		return true
	case "object-fill":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.Fill)})
		return true
	case "object-none":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.None)})
		return true
	case "object-scale-down":
		push(b, {prop = .Object_Fit, i = i32(Object_Fit.Scale_Down)})
		return true
	case "mx-auto":
		push(b, {prop = .Margin, mask = SIDES_X, i = 1})
		return true
	case "my-auto":
		push(b, {prop = .Margin, mask = SIDES_Y, i = 1})
		return true
	case "m-auto":
		push(b, {prop = .Margin, mask = SIDES_ALL, i = 1})
		return true
	case "ml-auto", "ms-auto":
		push(b, {prop = .Margin, mask = SIDE_L, i = 1})
		return true
	case "mr-auto", "me-auto":
		push(b, {prop = .Margin, mask = SIDE_R, i = 1})
		return true
	case "mt-auto":
		push(b, {prop = .Margin, mask = SIDE_T, i = 1})
		return true
	case "mb-auto":
		push(b, {prop = .Margin, mask = SIDE_B, i = 1})
		return true
	case "grid-flow-row":
		push(b, {prop = .Grid_Flow, i = i32(Grid_Flow.Row)})
		return true
	case "grid-flow-col":
		push(b, {prop = .Grid_Flow, i = i32(Grid_Flow.Column)})
		return true
	case "grid-flow-dense", "grid-flow-row-dense":
		push(b, {prop = .Grid_Flow, i = i32(Grid_Flow.Row_Dense)})
		return true
	case "grid-flow-col-dense":
		push(b, {prop = .Grid_Flow, i = i32(Grid_Flow.Column_Dense)})
		return true
	case "col-auto", "row-auto":
		push(b, {prop = u[0] == 'c' ? .Col_Span : .Row_Span, i = 0})
		return true
	case "col-span-full", "row-span-full":
		push(b, {prop = u[0] == 'c' ? .Col_Span : .Row_Span, i = -1})
		return true
	case "font-mono", "font-sans", "font-serif":
		push(b, {prop = .Font_Family, s = strings.clone(u[5:])})
		return true
	case "font-stretch-condensed", "font-stretch-expanded":
		return true
	case "text-shadow":
		push_shadow(b, .Text_Shadow, t.text_shadows["sm"])
		return true
	case "inset-shadow":
		push_shadow(b, .Inset_Shadow, t.inset_shadows["sm"])
		return true
	case "content-normal":
		push(b, {prop = .Align_Content, i = i32(Justify.Normal)})
		return true
	case "bg-stripes":
		push(b, {prop = .Bg_Stripes, f = {10, 1, 0, 0}})
		return true
	}

	// prefixed utilities
	if strings.has_prefix(u, "bg-stripes-") {
		rest := u[11:]
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Bg_Stripes, f = {n, 1, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "justify-") {
		return parse_justify(b, .Justify, u[8:]) || parse_align(b, .Justify_Items, u[8:], "items-") || parse_align(b, .Justify_Self, u[8:], "self-")
	}
	if strings.has_prefix(u, "items-") {
		return parse_align(b, .Align_Items, u[6:], "")
	}
	if strings.has_prefix(u, "self-") {
		return parse_align(b, .Align_Self, u[5:], "")
	}
	if strings.has_prefix(u, "content-") {
		return parse_justify(b, .Align_Content, u[8:])
	}
	if strings.has_prefix(u, "place-content-") {
		return parse_justify(b, .Place_Content, u[14:])
	}
	if strings.has_prefix(u, "place-items-") {
		return parse_align(b, .Place_Items, u[12:], "")
	}
	if strings.has_prefix(u, "place-self-") {
		return parse_align(b, .Place_Self, u[11:], "")
	}
	if strings.has_prefix(u, "grow-") {
		if n, ok := parse_num(u[5:]); ok {
			push(b, {prop = .Grow, f = {n, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "shrink-") {
		if n, ok := parse_num(u[7:]); ok {
			push(b, {prop = .Shrink, f = {n, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "flex-") {
		rest := u[5:]
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Flex, f = {n, 1, 0, 0}, sz = pct(0)})
			return true
		}
		if f, ok := fraction(rest); ok {
			push(b, {prop = .Flex, f = {0, 1, 0, 0}, sz = pct(f)})
			return true
		}
	}
	if strings.has_prefix(u, "basis-") {
		if sz, ok := size_value(t, u[6:], true, true); ok {
			push(b, {prop = .Basis, sz = sz})
			return true
		}
	}
	if strings.has_prefix(u, "order-") {
		rest := u[6:]
		v: f32
		switch rest {
		case "first":
			v = -9999
		case "last":
			v = 9999
		case "none":
			v = 0
		case:
			n, ok := parse_num(rest)
			if !ok {
				return false
			}
			v = n * sign
		}
		push(b, {prop = .Order, i = i32(v)})
		return true
	}
	if strings.has_prefix(u, "gap-") {
		rest := u[4:]
		mask: u8 = 3
		if strings.has_prefix(rest, "x-") {
			mask = 2
			rest = rest[2:]
		} else if strings.has_prefix(rest, "y-") {
			mask = 1
			rest = rest[2:]
		}
		if v, ok := spacing(t, rest); ok {
			push(b, {prop = .Gap, mask = mask, f = {v, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "grid-cols-") || strings.has_prefix(u, "grid-rows-") {
		g, ok := parse_track_list(t, u[10:])
		if !ok {
			return false
		}
		append(&b.grids, g)
		push(b, {prop = u[5] == 'c' ? .Grid_Cols : .Grid_Rows, idx = i32(len(b.grids) - 1)})
		return true
	}
	if strings.has_prefix(u, "auto-cols-") || strings.has_prefix(u, "auto-rows-") {
		rest := u[10:]
		tr: Track
		switch rest {
		case "auto":
			tr = {.Auto, 0}
		case "min":
			tr = {.Min_Content, 0}
		case "max":
			tr = {.Max_Content, 0}
		case "fr":
			tr = {.Fr, 1}
		case:
			g, ok := parse_track_list(t, rest)
			if !ok || g.count == 0 {
				return false
			}
			tr = g.tracks[0]
		}
		push(b, {prop = u[5] == 'c' ? .Auto_Cols : .Auto_Rows, f = {tr.v, 0, 0, 0}, i = i32(tr.kind)})
		return true
	}
	if strings.has_prefix(u, "col-") || strings.has_prefix(u, "row-") {
		is_col := u[0] == 'c'
		rest := u[4:]
		if strings.has_prefix(rest, "span-") {
			if n, ok := parse_num(rest[5:]); ok {
				push(b, {prop = is_col ? .Col_Span : .Row_Span, i = i32(n)})
				return true
			}
		} else if strings.has_prefix(rest, "start-") {
			if n, ok := parse_num(rest[6:]); ok {
				push(b, {prop = is_col ? .Col_Start : .Row_Start, i = i32(n * sign)})
				return true
			}
			if rest[6:] == "auto" {
				push(b, {prop = is_col ? .Col_Start : .Row_Start, i = 0})
				return true
			}
		} else if strings.has_prefix(rest, "end-") {
			if n, ok := parse_num(rest[4:]); ok {
				push(b, {prop = is_col ? .Col_End : .Row_End, i = i32(n * sign)})
				return true
			}
			if rest[4:] == "auto" {
				push(b, {prop = is_col ? .Col_End : .Row_End, i = 0})
				return true
			}
		} else if n, ok := parse_num(rest); ok {
			push(b, {prop = is_col ? .Col_Start : .Row_Start, i = i32(n * sign)})
			return true
		}
	}

	// sizing
	if strings.has_prefix(u, "size-") {
		if sz, ok := size_value(t, u[5:], true, true); ok {
			push(b, {prop = .Width, sz = sz})
			push(b, {prop = .Height, sz = sz})
			return true
		}
	}
	if strings.has_prefix(u, "min-w-") || strings.has_prefix(u, "min-h-") || strings.has_prefix(u, "max-w-") || strings.has_prefix(u, "max-h-") {
		horiz := u[4] == 'w'
		rest := u[6:]
		prop: Prop
		switch u[:5] {
		case "min-w":
			prop = .Min_W
		case "min-h":
			prop = .Min_H
		case "max-w":
			prop = .Max_W
		case "max-h":
			prop = .Max_H
		}
		if sz, ok := size_value(t, rest, horiz, true); ok {
			push(b, {prop = prop, sz = sz})
			return true
		}
		if rest == "prose" {
			push(b, {prop = prop, sz = px(t.containers["prose"])})
			return true
		}
	}
	if strings.has_prefix(u, "w-") || strings.has_prefix(u, "h-") {
		horiz := u[0] == 'w'
		if sz, ok := size_value(t, u[2:], horiz, true); ok {
			push(b, {prop = horiz ? .Width : .Height, sz = sz})
			return true
		}
	}
	if strings.has_prefix(u, "aspect-") {
		rest := u[7:]
		v: f32
		switch rest {
		case "square":
			v = 1
		case "video":
			v = 16.0 / 9.0
		case "auto":
			v = 0
		case:
			if a, ok := arbitrary(rest); ok {
				rest = a
			}
			slash := strings.index_byte(rest, '/')
			if slash > 0 {
				x, _ := strconv.parse_f32(strings.trim_space(rest[:slash]))
				y, _ := strconv.parse_f32(strings.trim_space(rest[slash + 1:]))
				if y == 0 {
					return false
				}
				v = x / y
			} else {
				n, ok := strconv.parse_f32(rest)
				if !ok {
					return false
				}
				v = n
			}
		}
		push(b, {prop = .Aspect, f = {v, 0, 0, 0}})
		return true
	}

	// spacing
	if len(u) >= 2 && (u[0] == 'p' || u[0] == 'm') {
		is_pad := u[0] == 'p'
		dash := strings.index_byte(u, '-')
		if dash > 0 && dash <= 3 {
			side := u[1:dash]
			if mask, ok := side_mask(side); ok {
				rest := u[dash + 1:]
				if v, vok := spacing(t, rest); vok {
					push(b, {prop = is_pad ? .Padding : .Margin, mask = mask, f = {v * sign, 0, 0, 0}})
					return true
				}
			}
		}
	}
	if strings.has_prefix(u, "space-x-") || strings.has_prefix(u, "space-y-") {
		if v, ok := spacing(t, u[8:]); ok {
			push(b, {prop = .Space, mask = u[6] == 'x' ? 1 : 2, f = {v * sign, 0, 0, 0}})
			return true
		}
	}

	// position
	if strings.has_prefix(u, "inset-") || strings.has_prefix(u, "top-") || strings.has_prefix(u, "right-") || strings.has_prefix(u, "bottom-") || strings.has_prefix(u, "left-") || strings.has_prefix(u, "start-") || strings.has_prefix(u, "end-") {
		dash := strings.index_byte(u, '-')
		head := u[:dash]
		rest := u[dash + 1:]
		mask: u8
		switch head {
		case "inset":
			mask = SIDES_ALL
			if strings.has_prefix(rest, "x-") {
				mask = SIDES_X
				rest = rest[2:]
			} else if strings.has_prefix(rest, "y-") {
				mask = SIDES_Y
				rest = rest[2:]
			}
		case "top":
			mask = SIDE_T
		case "right", "end":
			mask = SIDE_R
		case "bottom":
			mask = SIDE_B
		case "left", "start":
			mask = SIDE_L
		}
		if sz, ok := size_value(t, rest, true, false); ok {
			sz.v *= sign
			push(b, {prop = .Inset, mask = mask, sz = sz})
			return true
		}
	}
	if strings.has_prefix(u, "z-") {
		rest := u[2:]
		if rest == "auto" {
			push(b, {prop = .Z, i = 0, mask = 0})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			rest = a
		}
		if n, ok := strconv.parse_int(rest); ok {
			push(b, {prop = .Z, i = i32(n) * i32(sign), mask = 1})
			return true
		}
	}
	if strings.has_prefix(u, "overflow-") {
		rest := u[9:]
		mask: u8 = 3
		if strings.has_prefix(rest, "x-") {
			mask = 1
			rest = rest[2:]
		} else if strings.has_prefix(rest, "y-") {
			mask = 2
			rest = rest[2:]
		}
		o: Overflow
		switch rest {
		case "visible":
			o = .Visible
		case "hidden":
			o = .Hidden
		case "clip":
			o = .Clip
		case "auto":
			o = .Auto
		case "scroll":
			o = .Scroll
		case:
			return false
		}
		if mask & 1 != 0 {
			push(b, {prop = .Overflow_X, i = i32(o)})
		}
		if mask & 2 != 0 {
			push(b, {prop = .Overflow_Y, i = i32(o)})
		}
		return true
	}

	// typography
	if strings.has_prefix(u, "font-") {
		rest := u[5:]
		if w, ok := t.font_weights[rest]; ok {
			push(b, {prop = .Font_Weight, i = i32(w)})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if n, nok := strconv.parse_int(a); nok {
				push(b, {prop = .Font_Weight, i = i32(n)})
				return true
			}
			push(b, {prop = .Font_Family, s = strings.clone(a)})
			return true
		}
		if _, ok := t.fonts[rest]; ok {
			push(b, {prop = .Font_Family, s = strings.clone(rest)})
			return true
		}
		return false
	}
	if strings.has_prefix(u, "text-shadow-") {
		rest := u[12:]
		if set, ok := t.text_shadows[rest]; ok {
			push_shadow(b, .Text_Shadow, set)
			return true
		}
		return color_rule(b, .Text_Shadow_Color, rest)
	}
	if strings.has_prefix(u, "text-") {
		rest := u[5:]
		// text-sm/6 (size with line-height)
		lh: f32 = -1
		lh_px := false
		if slash := strings.index_byte(rest, '/'); slash > 0 {
			if size_tok, ok := t.text_sizes[rest[:slash]]; ok {
				_ = size_tok
				mod := rest[slash + 1:]
				if v, vok := spacing(t, mod); vok {
					lh = v
					lh_px = true
				} else if lv, lok := t.leading[mod]; lok {
					lh = lv
				} else {
					return false
				}
				rest = rest[:slash]
			}
		}
		// arbitrary size with line height: text-[13px]/6
		if strings.has_prefix(rest, "[") {
			if close := strings.index(rest, "]/"); close > 0 {
				if v, vok := parse_length(rest[1:close]); vok {
					mod := rest[close + 2:]
					r := Rule{prop = .Font_Size, f = {v, -1, 0, 0}}
					if sv, sok := spacing(t, mod); sok {
						r.f[1] = sv
						r.i = 1
					} else if lv, lok := t.leading[mod]; lok {
						r.f[1] = lv
					} else {
						return false
					}
					push(b, r)
					return true
				}
			}
		}
		if ts, ok := t.text_sizes[rest]; ok {
			r := Rule{prop = .Font_Size, f = {ts.size, ts.line_height, 0, 0}}
			if lh >= 0 {
				r.f[1] = lh
				r.i = lh_px ? 1 : 0
			}
			push(b, r)
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if v, vok := parse_length(a); vok && !strings.has_prefix(a, "#") {
				push(b, {prop = .Font_Size, f = {v, -1, 0, 0}})
				return true
			}
		}
		return color_rule(b, .Text_Color, rest)
	}
	if strings.has_prefix(u, "leading-") {
		rest := u[8:]
		if v, ok := t.leading[rest]; ok {
			push(b, {prop = .Line_Height, f = {v, 0, 0, 0}, i = 0})
			return true
		}
		if v, ok := spacing(t, rest); ok {
			push(b, {prop = .Line_Height, f = {v, 0, 0, 0}, i = 1})
			return true
		}
		return false
	}
	if strings.has_prefix(u, "tracking-") {
		rest := u[9:]
		if v, ok := t.tracking[rest]; ok {
			push(b, {prop = .Tracking, f = {v * sign, 0, 0, 0}, i = 0})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if strings.has_suffix(a, "em") && !strings.has_suffix(a, "rem") {
				v, _ := strconv.parse_f32(a[:len(a) - 2])
				push(b, {prop = .Tracking, f = {v * sign, 0, 0, 0}, i = 0})
				return true
			}
			v, vok := parse_length(a)
			if vok {
				push(b, {prop = .Tracking, f = {v * sign, 0, 0, 0}, i = 1})
				return true
			}
		}
		return false
	}
	if strings.has_prefix(u, "line-clamp-") {
		rest := u[11:]
		if rest == "none" {
			push(b, {prop = .Line_Clamp, i = 0})
			return true
		}
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Line_Clamp, i = i32(n)})
			return true
		}
	}
	if strings.has_prefix(u, "indent-") {
		if v, ok := spacing(t, u[7:]); ok {
			push(b, {prop = .Indent, f = {v * sign, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "decoration-") {
		rest := u[11:]
		switch rest {
		case "solid", "dashed", "dotted", "double", "wavy":
			push(b, {prop = .Decoration_Style, i = i32(line_style(rest))})
			return true
		case "auto", "from-font":
			push(b, {prop = .Decoration_Thickness, f = {0, 0, 0, 0}})
			return true
		}
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Decoration_Thickness, f = {n, 0, 0, 0}})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if v, vok := parse_length(a); vok {
				push(b, {prop = .Decoration_Thickness, f = {v, 0, 0, 0}})
				return true
			}
		}
		return color_rule(b, .Decoration_Color, rest)
	}
	if strings.has_prefix(u, "underline-offset-") {
		rest := u[17:]
		if rest == "auto" {
			push(b, {prop = .Underline_Offset, f = {0, 0, 0, 0}})
			return true
		}
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Underline_Offset, f = {n * sign, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "list-") {
		return false
	}

	// backgrounds
	if strings.has_prefix(u, "bg-linear-") || strings.has_prefix(u, "bg-gradient-") || u == "bg-radial" || u == "bg-conic" || strings.has_prefix(u, "bg-radial-") || strings.has_prefix(u, "bg-conic-") {
		kind := Gradient_Kind.Linear
		rest := ""
		if strings.has_prefix(u, "bg-linear-") {
			rest = u[10:]
		} else if strings.has_prefix(u, "bg-gradient-") {
			rest = u[12:]
		} else if strings.has_prefix(u, "bg-radial") {
			kind = .Radial
		} else {
			kind = .Conic
			if strings.has_prefix(u, "bg-conic-") {
				rest = u[9:]
			}
		}
		angle: f32 = 180
		if kind == .Linear {
			switch rest {
			case "to-t":
				angle = 0
			case "to-tr":
				angle = 45
			case "to-r":
				angle = 90
			case "to-br":
				angle = 135
			case "to-b":
				angle = 180
			case "to-bl":
				angle = 225
			case "to-l":
				angle = 270
			case "to-tl":
				angle = 315
			case:
				n, ok := parse_num(rest)
				if !ok {
					return false
				}
				angle = n * sign
			}
		} else if kind == .Conic {
			angle = 0
			if rest != "" {
				n, ok := parse_num(rest)
				if !ok {
					return false
				}
				angle = n * sign
			}
		}
		push(b, {prop = .Bg_Gradient, i = i32(kind), f = {angle, 0, 0, 0}})
		return true
	}
	if strings.has_prefix(u, "from-") || strings.has_prefix(u, "via-") || strings.has_prefix(u, "to-") {
		dash := strings.index_byte(u, '-')
		head := u[:dash]
		rest := u[dash + 1:]
		if strings.has_suffix(rest, "%") {
			n, ok := parse_num(rest[:len(rest) - 1])
			if !ok {
				return false
			}
			prop: Prop = head == "from" ? .Grad_From_Pos : head == "via" ? .Grad_Via_Pos : .Grad_To_Pos
			push(b, {prop = prop, f = {n / 100, 0, 0, 0}})
			return true
		}
		prop: Prop = head == "from" ? .Grad_From : head == "via" ? .Grad_Via : .Grad_To
		return color_rule(b, prop, rest)
	}
	if strings.has_prefix(u, "bg-") {
		rest := u[3:]
		return color_rule(b, .Bg_Color, rest)
	}

	// borders
	if strings.has_prefix(u, "rounded-") {
		rest := u[8:]
		corner := ""
		if dash := strings.index_byte(rest, '-'); dash > 0 {
			if _, ok := corner_mask(rest[:dash]); ok {
				corner = rest[:dash]
				rest = rest[dash + 1:]
			}
		} else if m, ok := corner_mask(rest); ok && rest != "" {
			push(b, {prop = .Radius, mask = m, f = {4, 0, 0, 0}})
			return true
		}
		mask, _ := corner_mask(corner)
		v: f32
		if r, ok := t.radius[rest]; ok {
			v = r
		} else if a, ok := arbitrary(rest); ok {
			lv, lok := parse_length(a)
			if !lok {
				return false
			}
			v = lv
		} else {
			return false
		}
		push(b, {prop = .Radius, mask = mask, f = {v, 0, 0, 0}})
		return true
	}
	if strings.has_prefix(u, "border-") {
		rest := u[7:]
		side := ""
		if dash := strings.index_byte(rest, '-'); dash > 0 {
			if _, ok := side_mask(rest[:dash]); ok && dash <= 2 {
				side = rest[:dash]
				rest = rest[dash + 1:]
			}
		} else if m, ok := side_mask(rest); ok && rest != "" {
			push(b, {prop = .Border_W, mask = m, f = {1, 0, 0, 0}})
			return true
		}
		mask, _ := side_mask(side)
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Border_W, mask = mask, f = {n, 0, 0, 0}})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if v, vok := parse_length(a); vok && !strings.has_prefix(a, "#") {
				push(b, {prop = .Border_W, mask = mask, f = {v, 0, 0, 0}})
				return true
			}
		}
		return color_rule(b, .Border_Color, rest, mask)
	}
	if strings.has_prefix(u, "divide-") {
		rest := u[7:]
		if strings.has_prefix(rest, "x-") || strings.has_prefix(rest, "y-") {
			if n, ok := parse_num(rest[2:]); ok {
				push(b, {prop = .Divide_W, mask = rest[0] == 'x' ? 1 : 2, f = {n, 0, 0, 0}})
				return true
			}
		}
		return color_rule(b, .Divide_Color, rest)
	}
	if strings.has_prefix(u, "outline-offset-") {
		if n, ok := parse_num(u[15:]); ok {
			push(b, {prop = .Outline_Offset, f = {n * sign, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "outline-") {
		rest := u[8:]
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Outline_W, f = {n, 0, 0, 0}})
			return true
		}
		return color_rule(b, .Outline_Color, rest)
	}
	if strings.has_prefix(u, "ring-offset-") {
		rest := u[12:]
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Ring_Offset_W, f = {n, 0, 0, 0}})
			return true
		}
		return color_rule(b, .Ring_Offset_Color, rest)
	}
	if strings.has_prefix(u, "inset-ring-") {
		rest := u[11:]
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Inset_Ring_W, f = {n, 0, 0, 0}})
			return true
		}
		return color_rule(b, .Inset_Ring_Color, rest)
	}
	if strings.has_prefix(u, "ring-") {
		rest := u[5:]
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Ring_W, f = {n, 0, 0, 0}})
			return true
		}
		return color_rule(b, .Ring_Color, rest)
	}

	// effects
	if strings.has_prefix(u, "inset-shadow-") {
		rest := u[13:]
		if set, ok := t.inset_shadows[rest]; ok {
			push_shadow(b, .Inset_Shadow, set)
			return true
		}
		return color_rule(b, .Inset_Shadow_Color, rest)
	}
	if strings.has_prefix(u, "shadow-") {
		rest := u[7:]
		if set, ok := t.shadows[rest]; ok {
			push_shadow(b, .Shadow, set)
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if set, sok := parse_arbitrary_shadow(a); sok {
				push_shadow(b, .Shadow, set)
				return true
			}
		}
		return color_rule(b, .Shadow_Color, rest)
	}
	if strings.has_prefix(u, "drop-shadow-") {
		rest := u[12:]
		if set, ok := t.drop_shadows[rest]; ok {
			push_shadow(b, .Drop_Shadow, set)
			return true
		}
		return color_rule(b, .Drop_Shadow_Color, rest)
	}
	if strings.has_prefix(u, "opacity-") {
		if n, ok := parse_num(u[8:]); ok {
			push(b, {prop = .Opacity, f = {n / 100, 0, 0, 0}})
			return true
		}
	}

	// transforms
	if strings.has_prefix(u, "translate-") {
		rest := u[10:]
		mask: u8 = 3
		if strings.has_prefix(rest, "x-") {
			mask = 1
			rest = rest[2:]
		} else if strings.has_prefix(rest, "y-") {
			mask = 2
			rest = rest[2:]
		}
		if sz, ok := size_value(t, rest, true, false); ok {
			sz.v *= sign
			push(b, {prop = .Translate, mask = mask, sz = sz})
			return true
		}
	}
	if strings.has_prefix(u, "scale-") {
		rest := u[6:]
		mask: u8 = 3
		if strings.has_prefix(rest, "x-") {
			mask = 1
			rest = rest[2:]
		} else if strings.has_prefix(rest, "y-") {
			mask = 2
			rest = rest[2:]
		}
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Scale, mask = mask, f = {n / 100 * sign, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "rotate-") {
		rest := u[7:]
		if a, ok := arbitrary(rest); ok {
			rest = strings.trim_suffix(a, "deg")
		}
		if n, ok := strconv.parse_f32(rest); ok {
			push(b, {prop = .Rotate, f = {n * sign, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "skew-") {
		rest := u[5:]
		mask: u8 = 3
		if strings.has_prefix(rest, "x-") {
			mask = 1
			rest = rest[2:]
		} else if strings.has_prefix(rest, "y-") {
			mask = 2
			rest = rest[2:]
		}
		if n, ok := parse_num(rest); ok {
			push(b, {prop = .Skew, mask = mask, f = {n * sign, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "origin-") {
		o: [2]f32
		switch u[7:] {
		case "center":
			o = {0.5, 0.5}
		case "top":
			o = {0.5, 0}
		case "top-right":
			o = {1, 0}
		case "right":
			o = {1, 0.5}
		case "bottom-right":
			o = {1, 1}
		case "bottom":
			o = {0.5, 1}
		case "bottom-left":
			o = {0, 1}
		case "left":
			o = {0, 0.5}
		case "top-left":
			o = {0, 0}
		case:
			return false
		}
		push(b, {prop = .Origin, f = {o.x, o.y, 0, 0}})
		return true
	}

	// filters
	if strings.has_prefix(u, "backdrop-") {
		rest := u[9:]
		if strings.has_prefix(rest, "blur-") {
			if v, ok := t.blur[rest[5:]]; ok {
				push(b, {prop = .Backdrop_Blur, f = {v, 0, 0, 0}})
				return true
			}
		}
		if rest == "blur" {
			push(b, {prop = .Backdrop_Blur, f = {8, 0, 0, 0}})
			return true
		}
		return true // other backdrop filters accepted, not rendered
	}
	if strings.has_prefix(u, "blur-") {
		rest := u[5:]
		if v, ok := t.blur[rest]; ok {
			push(b, {prop = .Blur, f = {v, 0, 0, 0}})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if v, vok := parse_length(a); vok {
				push(b, {prop = .Blur, f = {v, 0, 0, 0}})
				return true
			}
		}
	}
	filter_pct :: proc(b: ^Builder, prop: Prop, rest: string, scale: f32 = 100) -> bool {
		if n, ok := parse_num(rest); ok {
			push(b, {prop = prop, f = {n / scale, 0, 0, 0}})
			return true
		}
		return false
	}
	if strings.has_prefix(u, "brightness-") {
		return filter_pct(b, .Brightness, u[11:])
	}
	if strings.has_prefix(u, "contrast-") {
		return filter_pct(b, .Contrast, u[9:])
	}
	if strings.has_prefix(u, "grayscale-") {
		return filter_pct(b, .Grayscale, u[10:])
	}
	if strings.has_prefix(u, "invert-") {
		return filter_pct(b, .Invert, u[7:])
	}
	if strings.has_prefix(u, "saturate-") {
		return filter_pct(b, .Saturate, u[9:])
	}
	if strings.has_prefix(u, "sepia-") {
		return filter_pct(b, .Sepia, u[6:])
	}
	if strings.has_prefix(u, "hue-rotate-") {
		if n, ok := parse_num(u[11:]); ok {
			push(b, {prop = .Hue_Rotate, f = {n * sign, 0, 0, 0}})
			return true
		}
	}

	// motion
	if strings.has_prefix(u, "duration-") {
		if n, ok := parse_num(u[9:]); ok {
			push(b, {prop = .Duration, f = {n, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "delay-") {
		if n, ok := parse_num(u[6:]); ok {
			push(b, {prop = .Delay, f = {n, 0, 0, 0}})
			return true
		}
	}
	if strings.has_prefix(u, "ease-") {
		rest := u[5:]
		if e, ok := t.easings[rest]; ok {
			push(b, {prop = .Ease, f = e})
			return true
		}
		if a, ok := arbitrary(rest); ok {
			if e, eok := parse_ease(a); eok {
				push(b, {prop = .Ease, f = e})
				return true
			}
		}
	}

	// interactivity
	if strings.has_prefix(u, "cursor-") {
		c, ok := cursor_from_name(u[7:])
		if ok {
			push(b, {prop = .Cursor, i = i32(c)})
		}
		return ok
	}
	if strings.has_prefix(u, "accent-") {
		return color_rule(b, .Accent, u[7:])
	}
	if strings.has_prefix(u, "caret-") {
		return color_rule(b, .Caret, u[6:])
	}
	if strings.has_prefix(u, "fill-") {
		if u[5:] == "none" {
			push(b, {prop = .Fill, tok = {TRANSPARENT, TRANSPARENT}})
			return true
		}
		return color_rule(b, .Fill, u[5:])
	}
	if strings.has_prefix(u, "stripes-") {
		// color of the bg-stripes pattern
		return color_rule(b, .Fill, u[8:])
	}
	if strings.has_prefix(u, "stroke-") {
		return true
	}
	if strings.has_prefix(u, "object-") {
		o: [2]f32
		switch u[7:] {
		case "center":
			o = {0.5, 0.5}
		case "top":
			o = {0.5, 0}
		case "bottom":
			o = {0.5, 1}
		case "left":
			o = {0, 0.5}
		case "right":
			o = {1, 0.5}
		case "top-left", "left-top":
			o = {0, 0}
		case "top-right", "right-top":
			o = {1, 0}
		case "bottom-left", "left-bottom":
			o = {0, 1}
		case "bottom-right", "right-bottom":
			o = {1, 1}
		case:
			return false
		}
		push(b, {prop = .Object_Pos, f = {o.x, o.y, 0, 0}})
		return true
	}
	if strings.has_prefix(u, "scroll-") || strings.has_prefix(u, "snap-") || strings.has_prefix(u, "columns-") || strings.has_prefix(u, "will-change-") || strings.has_prefix(u, "break-") || strings.has_prefix(u, "mix-blend-") || strings.has_prefix(u, "bg-blend-") || strings.has_prefix(u, "perspective-") || strings.has_prefix(u, "rotate-x-") || strings.has_prefix(u, "rotate-y-") || strings.has_prefix(u, "border-spacing") || strings.has_prefix(u, "font-stretch-") || strings.has_prefix(u, "mask-") || strings.has_prefix(u, "content-[") {
		return true // parsed; not rendered
	}
	return false
}

@(private)
push_shadow :: proc(b: ^Builder, prop: Prop, set: Shadow_Set) {
	append(&b.shadows, set)
	push(b, {prop = prop, idx = i32(len(b.shadows) - 1)})
}

@(private)
line_style :: proc(s: string) -> Line_Style {
	switch s {
	case "dashed":
		return .Dashed
	case "dotted":
		return .Dotted
	case "double":
		return .Double
	case "wavy":
		return .Wavy
	case "none":
		return .None
	case "hidden":
		return .Hidden
	}
	return .Solid
}

@(private)
parse_justify :: proc(b: ^Builder, prop: Prop, s: string) -> bool {
	j: Justify
	switch s {
	case "start", "left":
		j = .Start
	case "end", "right", "end-safe":
		j = .End
	case "center", "center-safe":
		j = .Center
	case "between":
		j = .Between
	case "around":
		j = .Around
	case "evenly":
		j = .Evenly
	case "stretch":
		j = .Stretch
	case "normal", "baseline":
		j = .Normal
	case:
		return false
	}
	push(b, {prop = prop, i = i32(j)})
	return true
}

@(private)
parse_align :: proc(b: ^Builder, prop: Prop, s0: string, need_prefix: string) -> bool {
	s := s0
	if need_prefix != "" {
		if !strings.has_prefix(s, need_prefix) {
			return false
		}
		s = s[len(need_prefix):]
	}
	a: Align
	switch s {
	case "auto", "normal":
		a = .Auto
	case "start", "flex-start":
		a = .Start
	case "end", "flex-end", "end-safe":
		a = .End
	case "center", "center-safe":
		a = .Center
	case "stretch":
		a = .Stretch
	case "baseline", "baseline-last":
		a = .Baseline
	case:
		return false
	}
	push(b, {prop = prop, i = i32(a)})
	return true
}

cursor_from_name :: proc(s: string) -> (Cursor, bool) {
	switch s {
	case "auto":
		return .Auto, true
	case "default":
		return .Default, true
	case "pointer":
		return .Pointer, true
	case "text", "vertical-text":
		return .Text, true
	case "move", "all-scroll":
		return .Move, true
	case "wait":
		return .Wait, true
	case "progress":
		return .Progress, true
	case "not-allowed", "no-drop":
		return .Not_Allowed, true
	case "grab":
		return .Grab, true
	case "grabbing":
		return .Grabbing, true
	case "crosshair", "cell":
		return .Crosshair, true
	case "help", "context-menu":
		return .Help, true
	case "col-resize":
		return .Col_Resize, true
	case "row-resize":
		return .Row_Resize, true
	case "ew-resize", "e-resize", "w-resize":
		return .EW_Resize, true
	case "ns-resize", "n-resize", "s-resize":
		return .NS_Resize, true
	case "nesw-resize", "ne-resize", "sw-resize":
		return .NESW_Resize, true
	case "nwse-resize", "nw-resize", "se-resize":
		return .NWSE_Resize, true
	case "none":
		return .None, true
	case "zoom-in", "zoom-out", "copy", "alias":
		return .Pointer, true
	}
	return .Auto, false
}

// State used to match variants when resolving a class set for one element.
Match_State :: struct {
	flags:    Variants, // which variant conditions are currently true
	viewport: f32,
}

rule_matches :: proc "contextless" (r: ^Rule, m: ^Match_State) -> bool {
	need := r.variants - {.Children, .Placeholder, .Selection}
	if need & m.flags != need {
		return false
	}
	if r.bp_min > 0 && m.viewport < r.bp_min {
		return false
	}
	if r.bp_max > 0 && m.viewport >= r.bp_max {
		return false
	}
	return true
}

// Applies matching rules of cs onto s. `dark` picks the scheme of semantic color tokens.
// When `children_pass` is true only rules tagged with the `*:` variant apply (used on children).
apply_class_set :: proc(s: ^Style, cs: ^Class_Set, m: ^Match_State, dark: bool, children_pass := false) {
	for &r in cs.rules {
		if (.Children in r.variants) != children_pass {
			continue
		}
		if !rule_matches(&r, m) {
			continue
		}
		apply_rule(s, &r, cs, dark)
	}
}

@(private)
tok_color :: proc "contextless" (r: ^Rule, s: ^Style, dark: bool) -> Color {
	if r.i == 1 && r.tok.light.a == 0 && r.tok.dark.a == 0 {
		return s.color // currentColor
	}
	return dark ? r.tok.dark : r.tok.light
}

apply_rule :: proc(s: ^Style, r: ^Rule, cs: ^Class_Set, dark: bool) {
	switch r.prop {
	case .None, .Group:
	case .Display:
		s.display = Display(r.i)
	case .Position:
		s.position = Position(r.i)
	case .Flex_Dir:
		s.flex_dir = Flex_Dir(r.i)
	case .Flex_Wrap:
		s.flex_wrap = Flex_Wrap(r.i)
	case .Justify:
		s.justify = Justify(r.i)
	case .Align_Items:
		s.align_items = Align(r.i)
	case .Align_Self:
		s.align_self = Align(r.i)
	case .Align_Content:
		s.align_content = Justify(r.i)
	case .Justify_Items:
		s.justify_items = Align(r.i)
	case .Justify_Self:
		s.justify_self = Align(r.i)
	case .Place_Content:
		s.align_content = Justify(r.i)
		s.justify = Justify(r.i)
	case .Place_Items:
		s.align_items = Align(r.i)
		s.justify_items = Align(r.i)
	case .Place_Self:
		s.align_self = Align(r.i)
		s.justify_self = Align(r.i)
	case .Grow:
		s.grow = r.f[0]
	case .Shrink:
		s.shrink = r.f[0]
	case .Basis:
		s.basis = r.sz
	case .Flex:
		s.grow = r.f[0]
		s.shrink = r.f[1]
		s.basis = r.sz
	case .Order:
		s.order = r.i
	case .Gap:
		if r.mask & 1 != 0 {
			s.gap[0] = r.f[0]
		}
		if r.mask & 2 != 0 {
			s.gap[1] = r.f[0]
		}
	case .Grid_Cols:
		s.grid_cols = cs.grids[r.idx]
	case .Grid_Rows:
		s.grid_rows = cs.grids[r.idx]
	case .Auto_Cols:
		s.auto_cols = {Track_Kind(r.i), r.f[0]}
	case .Auto_Rows:
		s.auto_rows = {Track_Kind(r.i), r.f[0]}
	case .Grid_Flow:
		s.grid_flow = Grid_Flow(r.i)
	case .Col_Span:
		s.col_span = r.i
	case .Col_Start:
		s.col_start = r.i
	case .Col_End:
		s.col_end = r.i
	case .Row_Span:
		s.row_span = r.i
	case .Row_Start:
		s.row_start = r.i
	case .Row_End:
		s.row_end = r.i
	case .Width:
		s.width = r.sz
	case .Height:
		s.height = r.sz
	case .Min_W:
		s.min_w = r.sz
	case .Min_H:
		s.min_h = r.sz
	case .Max_W:
		s.max_w = r.sz
	case .Max_H:
		s.max_h = r.sz
	case .Aspect:
		s.aspect = r.f[0]
	case .Padding:
		for i in 0 ..< 4 {
			if r.mask & (1 << u8(i)) != 0 {
				s.padding[i] = r.f[0]
			}
		}
	case .Margin:
		for i in 0 ..< 4 {
			if r.mask & (1 << u8(i)) != 0 {
				s.margin[i] = r.f[0]
				s.margin_auto[i] = r.i == 1
			}
		}
	case .Inset:
		for i in 0 ..< 4 {
			if r.mask & (1 << u8(i)) != 0 {
				s.inset[i] = r.sz
			}
		}
	case .Z:
		s.z = r.i
		s.z_set = r.mask == 1
	case .Overflow_X:
		s.overflow_x = Overflow(r.i)
	case .Overflow_Y:
		s.overflow_y = Overflow(r.i)
	case .Box_Sizing:
		s.box_content = r.i == 1
	case .Space:
		if r.mask == 1 {
			s.space.x = r.f[0]
		} else {
			s.space.y = r.f[0]
		}
	case .Space_Reverse:
		s.space_reverse[r.mask - 1] = true
	case .Divide_W:
		s.divide_w[r.mask - 1] = r.f[0]
	case .Divide_Reverse:
		s.divide_reverse[r.mask - 1] = true
	case .Divide_Color:
		s.divide_color = tok_color(r, s, dark)
		s.divide_color_set = true
	case .Divide_Style:
		s.divide_style = Line_Style(r.i)
	case .Bg_Color:
		if .Selection in r.variants {
			s.selection_bg = tok_color(r, s, dark)
			s.selection_set = true
		} else {
			s.bg = tok_color(r, s, dark)
		}
	case .Bg_Gradient:
		s.gradient.kind = Gradient_Kind(r.i)
		s.gradient.angle = r.f[0]
		if s.gradient.to_pos == 0 {
			s.gradient.to_pos = 1
		}
	case .Grad_From:
		s.gradient.from = tok_color(r, s, dark)
		s.gradient.from_set = true
		if !s.gradient.to_set {
			s.gradient.to = with_alpha(s.gradient.from, 0)
		}
	case .Grad_Via:
		s.gradient.via = tok_color(r, s, dark)
		s.gradient.has_via = true
		if s.gradient.via_pos == 0 {
			s.gradient.via_pos = 0.5
		}
		if !s.gradient.to_set {
			s.gradient.to = with_alpha(s.gradient.via, 0)
		}
	case .Grad_To:
		s.gradient.to = tok_color(r, s, dark)
		s.gradient.to_set = true
		if !s.gradient.from_set {
			s.gradient.from = with_alpha(s.gradient.to, 0)
		}
	case .Grad_From_Pos:
		s.gradient.from_pos = r.f[0]
	case .Grad_Via_Pos:
		s.gradient.via_pos = r.f[0]
	case .Grad_To_Pos:
		s.gradient.to_pos = r.f[0]
	case .Bg_Stripes:
		s.gradient.kind = .Stripes
		s.gradient.period = r.f[0]
		s.gradient.line = r.f[1]
		s.gradient.angle = 315
	case .Bg_None:
		s.gradient = {}
		s.bg_image = 0
	case .Border_W:
		for i in 0 ..< 4 {
			if r.mask & (1 << u8(i)) != 0 {
				s.border_w[i] = r.f[0]
			}
		}
	case .Border_Color:
		c := tok_color(r, s, dark)
		if !s.border_color_set {
			// unset sides keep following currentColor
			s.border_color = {s.color, s.color, s.color, s.color}
		}
		for i in 0 ..< 4 {
			if r.mask & (1 << u8(i)) != 0 {
				s.border_color[i] = c
			}
		}
		s.border_color_set = true
	case .Border_Current:
		s.border_color = {}
		s.border_color_set = false
	case .Border_Style:
		s.border_style = Line_Style(r.i)
	case .Radius:
		for i in 0 ..< 4 {
			if r.mask & (1 << u8(i)) != 0 {
				s.radius[i] = r.f[0]
			}
		}
	case .Shadow:
		s.shadows = cs.shadows[r.idx]
	case .Shadow_Color:
		s.shadow_color = tok_color(r, s, dark)
		s.shadow_color_set = true
		s.shadow_alpha_set = r.tok.light.a < 1
	case .Inset_Shadow:
		s.inset_shadows = cs.shadows[r.idx]
	case .Inset_Shadow_Color:
		s.inset_shadow_color = tok_color(r, s, dark)
		s.inset_shadow_color_set = true
	case .Ring_W:
		s.ring_w = r.f[0]
	case .Ring_Color:
		s.ring_color = tok_color(r, s, dark)
		s.ring_color_set = true
	case .Ring_Inset:
		s.ring_inset = true
	case .Inset_Ring_W:
		s.inset_ring_w = r.f[0]
	case .Inset_Ring_Color:
		s.inset_ring_color = tok_color(r, s, dark)
		s.inset_ring_color_set = true
	case .Ring_Offset_W:
		s.ring_offset_w = r.f[0]
	case .Ring_Offset_Color:
		s.ring_offset_color = tok_color(r, s, dark)
	case .Outline_W:
		s.outline_w = r.f[0]
		if s.outline_style == .None || s.outline_style == .Hidden {
			s.outline_style = .Solid
		}
	case .Outline_Color:
		s.outline_color = tok_color(r, s, dark)
		s.outline_color_set = true
	case .Outline_Offset:
		s.outline_offset = r.f[0]
	case .Outline_Style:
		s.outline_style = Line_Style(r.i)
		if s.outline_style == .None || s.outline_style == .Hidden {
			s.outline_w = 0
		} else if s.outline_w == 0 {
			s.outline_w = 1
		}
	case .Opacity:
		s.opacity = r.f[0]
	case .Visibility:
		s.visibility = Visibility(r.i)
	case .Translate:
		if r.mask & 1 != 0 {
			s.translate[0] = r.sz
		}
		if r.mask & 2 != 0 {
			s.translate[1] = r.sz
		}
	case .Scale:
		if r.mask & 1 != 0 {
			s.scale[0] = r.f[0]
		}
		if r.mask & 2 != 0 {
			s.scale[1] = r.f[0]
		}
	case .Rotate:
		s.rotate = r.f[0]
	case .Skew:
		if r.mask & 1 != 0 {
			s.skew[0] = r.f[0]
		}
		if r.mask & 2 != 0 {
			s.skew[1] = r.f[0]
		}
	case .Origin:
		s.origin = {r.f[0], r.f[1]}
	case .Transform_None:
		s.translate = {}
		s.scale = {1, 1}
		s.rotate = 0
		s.skew = {}
	case .Blur:
		s.blur = r.f[0]
	case .Brightness:
		s.brightness = r.f[0]
	case .Contrast:
		s.contrast = r.f[0]
	case .Grayscale:
		s.grayscale = r.f[0]
	case .Hue_Rotate:
		s.hue_rotate = r.f[0]
	case .Invert:
		s.invert = r.f[0]
	case .Saturate:
		s.saturate = r.f[0]
	case .Sepia:
		s.sepia = r.f[0]
	case .Drop_Shadow:
		s.drop_shadows = cs.shadows[r.idx]
	case .Drop_Shadow_Color:
		s.drop_shadow_color = tok_color(r, s, dark)
		s.drop_shadow_color_set = true
	case .Filter_None:
		s.blur = 0
		s.brightness = 1
		s.contrast = 1
		s.grayscale = 0
		s.hue_rotate = 0
		s.invert = 0
		s.saturate = 1
		s.sepia = 0
		s.drop_shadows = {}
	case .Backdrop_Blur:
		s.backdrop_blur = r.f[0]
	case .Backdrop_Opacity:
		s.backdrop_opacity = r.f[0]
	case .Object_Fit:
		if r.mask == 1 {
			s.bg_size = Object_Fit(r.i)
		} else {
			s.object_fit = Object_Fit(r.i)
		}
	case .Object_Pos:
		s.object_pos = {r.f[0], r.f[1]}
	case .Cursor:
		s.cursor = Cursor(r.i)
	case .Pointer_Events:
		s.pointer_events = r.i == 1
	case .User_Select:
		s.user_select = r.i == 1
	case .Accent:
		s.accent = tok_color(r, s, dark)
		s.accent_set = true
	case .Caret:
		s.caret = tok_color(r, s, dark)
		s.caret_set = true
	case .Fill:
		s.fill = tok_color(r, s, dark)
		s.fill_set = true
	case .Transition:
		s.transition = transmute(Trans_Props)u8(r.i)
		if s.duration_ms <= 0 {
			s.duration_ms = 150
		}
	case .Duration:
		s.duration_ms = r.f[0]
	case .Delay:
		s.delay_ms = r.f[0]
	case .Ease:
		s.easing = r.f
	case .Animation:
		s.animation = Animation(r.i)
	case .Font_Family:
		s.font_family = r.s
	case .Font_Size:
		s.font_size = r.f[0]
		if r.f[1] >= 0 {
			s.line_height = r.f[1]
			s.line_height_px = r.i == 1
		}
	case .Line_Height:
		s.line_height = r.f[0]
		s.line_height_px = r.i == 1
	case .Font_Weight:
		s.font_weight = u16(r.i)
	case .Italic:
		s.italic = r.i == 1
	case .Tracking:
		if r.i == 1 {
			s.tracking_px = r.f[0]
			s.tracking_em = 0
		} else {
			s.tracking_em = r.f[0]
			s.tracking_px = 0
		}
	case .Text_Color:
		if .Placeholder in r.variants {
			s.placeholder = tok_color(r, s, dark)
			s.placeholder_set = true
		} else {
			s.color = tok_color(r, s, dark)
		}
	case .Text_Align:
		s.text_align = Text_Align(r.i)
	case .Text_Transform:
		s.text_transform = Text_Transform(r.i)
	case .Decoration:
		if r.i == 0 {
			s.decoration = {}
		} else {
			s.decoration += transmute(Decoration)r.mask
		}
	case .Decoration_Color:
		s.decoration_color = tok_color(r, s, dark)
		s.decoration_color_set = true
	case .Decoration_Style:
		s.decoration_style = Line_Style(r.i)
	case .Decoration_Thickness:
		s.decoration_thickness = r.f[0]
	case .Underline_Offset:
		s.underline_offset = r.f[0]
	case .White_Space:
		s.white_space = White_Space(r.i)
	case .Text_Wrap:
		s.text_wrap = Text_Wrap(r.i)
	case .Word_Break:
		s.word_break = Word_Break(r.i)
	case .Truncate:
		s.truncate = true
		s.white_space = .No_Wrap
		s.overflow_x = .Hidden
		s.overflow_y = .Hidden
	case .Text_Overflow:
		s.truncate = r.i == 1
	case .Line_Clamp:
		s.line_clamp = r.i
		if r.i > 0 {
			s.overflow_x = .Hidden
			s.overflow_y = .Hidden
		}
	case .Indent:
		s.indent = r.f[0]
	case .Font_Variant:
		if r.i == 0 {
			s.font_variants = {}
		} else {
			s.font_variants += transmute(Font_Variants)r.mask
		}
	case .Text_Shadow:
		s.text_shadows = cs.shadows[r.idx]
	case .Text_Shadow_Color:
		s.text_shadow_color = tok_color(r, s, dark)
		s.text_shadow_color_set = true
	case .List_Style:
		s.list_style = u8(r.i)
	case .List_Pos:
		s.list_inside = r.i == 1
	}
}

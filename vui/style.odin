package vui

Display :: enum u8 {
	Block,
	Flex,
	Grid,
	Inline,
	Inline_Block,
	Inline_Flex,
	Inline_Grid,
	None,
	Contents,
}

Position :: enum u8 {
	Static,
	Relative,
	Absolute,
	Fixed,
	Sticky,
}

Flex_Dir :: enum u8 {
	Row,
	Column,
	Row_Reverse,
	Column_Reverse,
}

Flex_Wrap :: enum u8 {
	No_Wrap,
	Wrap,
	Wrap_Reverse,
}

Justify :: enum u8 {
	Normal,
	Start,
	End,
	Center,
	Between,
	Around,
	Evenly,
	Stretch,
}

Align :: enum u8 {
	Auto,
	Start,
	End,
	Center,
	Stretch,
	Baseline,
}

Overflow :: enum u8 {
	Visible,
	Hidden,
	Clip,
	Auto,
	Scroll,
}

Size_Kind :: enum u8 {
	Auto,
	Px,
	Percent,
	Vw,
	Vh,
	Min_Content,
	Max_Content,
	Fit_Content,
}

Size :: struct {
	kind: Size_Kind,
	v:    f32,
}

px :: proc "contextless" (v: f32) -> Size {
	return {.Px, v}
}
pct :: proc "contextless" (v: f32) -> Size {
	return {.Percent, v}
}
AUTO :: Size{.Auto, 0}

Track_Kind :: enum u8 {
	Px,
	Fr,
	Auto,
	Percent,
	Min_Content,
	Max_Content,
}

Track :: struct {
	kind: Track_Kind,
	v:    f32,
}

MAX_TRACKS :: 16

Grid_Template :: struct {
	tracks: [MAX_TRACKS]Track,
	count:  u8,
	subgrid: bool,
}

Grid_Flow :: enum u8 {
	Row,
	Column,
	Row_Dense,
	Column_Dense,
}

Text_Align :: enum u8 {
	Start,
	Left,
	Center,
	Right,
	End,
	Justify,
}

Text_Transform :: enum u8 {
	None,
	Upper,
	Lower,
	Capitalize,
}

Decoration_Line :: enum u8 {
	Underline,
	Overline,
	Line_Through,
}
Decoration :: bit_set[Decoration_Line;u8]

Line_Style :: enum u8 {
	Solid,
	Dashed,
	Dotted,
	Double,
	Wavy,
	None,
	Hidden,
}

White_Space :: enum u8 {
	Normal,
	No_Wrap,
	Pre,
	Pre_Wrap,
	Pre_Line,
	Break_Spaces,
}

Text_Wrap :: enum u8 {
	Wrap,
	No_Wrap,
	Balance,
	Pretty,
}

Word_Break :: enum u8 {
	Normal,
	Break_All,
	Keep_All,
	Anywhere,
	Break_Word,
}

Cursor :: enum u8 {
	Auto,
	Default,
	Pointer,
	Text,
	Move,
	Wait,
	Progress,
	Not_Allowed,
	Grab,
	Grabbing,
	Crosshair,
	Help,
	Col_Resize,
	Row_Resize,
	EW_Resize,
	NS_Resize,
	NESW_Resize,
	NWSE_Resize,
	None,
}

Visibility :: enum u8 {
	Visible,
	Invisible,
	Collapse,
}

Object_Fit :: enum u8 {
	Fill,
	Contain,
	Cover,
	None,
	Scale_Down,
}

// Ornate corner geometry (vinland-ui extension, mirrors CSS `corner-shape`). `Arch` turns
// the two corners of an edge into a pointed (or, at height == half width, round) arch.
Corner_Shape :: enum u8 {
	Round,
	Bevel,
	Scoop,
	Notch,
	Arch,
}

Gradient_Kind :: enum u8 {
	None,
	Linear,
	Radial,
	Conic,
	Stripes,
}

Gradient :: struct {
	kind:     Gradient_Kind,
	angle:    f32, // degrees, CSS convention (0 = to top, 90 = to right)
	from:     Color,
	via:      Color,
	to:       Color,
	has_via:  bool,
	from_set: bool,
	to_set:   bool,
	from_pos: f32, // 0..1
	via_pos:  f32,
	to_pos:   f32,
	period:   f32, // stripes: px between lines
	line:     f32, // stripes: line width px
}

Trans_Prop :: enum u8 {
	Colors,
	Opacity,
	Shadow,
	Transform,
	Filter,
	Size,
}
Trans_Props :: bit_set[Trans_Prop;u8]

Animation :: enum u8 {
	None,
	Spin,
	Ping,
	Pulse,
	Bounce,
}

Font_Variant :: enum u8 {
	Tabular,
	Slashed_Zero,
	Oldstyle,
	Lining,
}
Font_Variants :: bit_set[Font_Variant;u8]

Edge :: enum u8 {
	Top,
	Right,
	Bottom,
	Left,
}

// Computed style for one element. Text properties are inherited from the parent; everything
// else starts at the defaults below (CSS initial values with Tailwind's preflight applied).
Style :: struct {
	// layout
	display:         Display,
	position:        Position,
	flex_dir:        Flex_Dir,
	flex_wrap:       Flex_Wrap,
	justify:         Justify,
	align_items:     Align,
	align_self:      Align,
	align_content:   Justify,
	justify_items:   Align,
	justify_self:    Align,
	grow:            f32,
	shrink:          f32,
	basis:           Size,
	order:           i32,
	gap:             [2]f32, // row (y), column (x)
	grid_cols:       Grid_Template,
	grid_rows:       Grid_Template,
	auto_cols:       Track,
	auto_rows:       Track,
	grid_flow:       Grid_Flow,
	col_start:       i32, // 1-based, 0 = auto, negative from end
	col_end:         i32,
	col_span:        i32, // 0 = auto (1), -1 = full
	row_start:       i32,
	row_end:         i32,
	row_span:        i32,
	width, height:   Size,
	min_w, min_h:    Size,
	max_w, max_h:    Size,
	aspect:          f32, // 0 = none
	padding:         [4]f32, // t r b l
	margin:          [4]f32,
	margin_auto:     [4]bool,
	inset:           [4]Size, // t r b l
	z:               i32,
	z_set:           bool,
	overflow_x:      Overflow,
	overflow_y:      Overflow,
	box_content:     bool, // box-sizing: content-box
	// spacing helpers applied to children (space-x/y, divide-x/y)
	space:           [2]f32, // x, y
	space_reverse:   [2]bool,
	divide_w:        [2]f32, // x, y
	divide_color:    Color,
	divide_style:    Line_Style,
	divide_reverse:  [2]bool,
	// paint
	bg:              Color,
	gradient:        Gradient,
	bg_image:        Image_Id,
	bg_size:         Object_Fit,
	bg_texture:      Image_Id, // textured fill, multiplied with the background colour/gradient
	bg_tile:         f32, // texture tile size in logical px; 0 = stretch over the box
	corner_shape:    [4]Corner_Shape, // tl tr br bl
	border_w:        [4]f32,
	border_color:    [4]Color,
	border_color_set: bool, // false = currentColor
	divide_color_set: bool,
	border_style:    Line_Style,
	radius:          [4]f32, // tl tr br bl
	shadows:         Shadow_Set,
	shadow_color:    Color,
	shadow_color_set: bool,
	shadow_alpha_set: bool,
	inset_shadows:   Shadow_Set,
	inset_shadow_color: Color,
	inset_shadow_color_set: bool,
	ring_w:          f32,
	ring_color:      Color,
	ring_color_set:  bool,
	ring_inset:      bool,
	inset_ring_w:    f32,
	inset_ring_color: Color,
	inset_ring_color_set: bool,
	ring_offset_w:   f32,
	ring_offset_color: Color,
	outline_w:       f32,
	outline_color:   Color,
	outline_color_set: bool,
	outline_offset:  f32,
	outline_style:   Line_Style,
	opacity:         f32,
	visibility:      Visibility,
	// transform
	translate:       [2]Size,
	scale:           [2]f32,
	rotate:          f32,
	skew:            [2]f32,
	origin:          [2]f32,
	// filters
	blur:            f32,
	brightness:      f32,
	contrast:        f32,
	grayscale:       f32,
	hue_rotate:      f32,
	invert:          f32,
	saturate:        f32,
	sepia:           f32,
	drop_shadows:    Shadow_Set,
	drop_shadow_color: Color,
	drop_shadow_color_set: bool,
	backdrop_blur:   f32,
	backdrop_opacity: f32,
	// images
	object_fit:      Object_Fit,
	object_pos:      [2]f32,
	// interactivity
	cursor:          Cursor,
	pointer_events:  bool,
	user_select:     bool,
	accent:          Color,
	accent_set:      bool,
	caret:           Color,
	caret_set:       bool,
	fill:            Color,
	fill_set:        bool,
	selection_bg:    Color,
	selection_set:   bool,
	placeholder:     Color,
	placeholder_set: bool,
	// motion
	transition:      Trans_Props,
	duration_ms:     f32,
	delay_ms:        f32,
	easing:          Easing,
	animation:       Animation,
	// text (inherited)
	font_family:     string,
	font_size:       f32,
	line_height:     f32,
	line_height_px:  bool,
	font_weight:     u16,
	italic:          bool,
	tracking_em:     f32,
	tracking_px:     f32,
	color:           Color,
	text_align:      Text_Align,
	text_transform:  Text_Transform,
	decoration:      Decoration,
	decoration_color: Color,
	decoration_color_set: bool,
	decoration_style: Line_Style,
	decoration_thickness: f32, // 0 = from-font
	underline_offset: f32,
	white_space:     White_Space,
	text_wrap:       Text_Wrap,
	word_break:      Word_Break,
	truncate:        bool, // text-overflow: ellipsis
	line_clamp:      i32,
	indent:          f32,
	font_variants:   Font_Variants,
	text_shadows:    Shadow_Set,
	text_shadow_color: Color,
	text_shadow_color_set: bool,
	list_style:      u8, // 0 none, 1 disc, 2 decimal
	list_inside:     bool,
}

style_default :: proc() -> Style {
	s: Style
	s.display = .Block
	s.align_items = .Stretch
	s.justify_items = .Stretch
	s.shrink = 1
	s.basis = AUTO
	s.width = AUTO
	s.height = AUTO
	s.min_w = AUTO
	s.min_h = AUTO
	s.max_w = {.Auto, 0}
	s.max_h = {.Auto, 0}
	s.inset = {AUTO, AUTO, AUTO, AUTO}
	s.opacity = 1
	s.scale = {1, 1}
	s.origin = {0.5, 0.5}
	s.brightness = 1
	s.contrast = 1
	s.saturate = 1
	s.backdrop_opacity = 1
	s.pointer_events = true
	s.user_select = true
	s.duration_ms = 150
	s.easing = EASE_IN_OUT
	s.auto_cols = {.Auto, 0}
	s.auto_rows = {.Auto, 0}
	s.object_pos = {0.5, 0.5}
	s.border_style = .Solid
	s.outline_style = .Solid
	s.divide_style = .Solid
	s.decoration_style = .Solid
	s.ring_color = rgb(0x000000, 1)
	// text defaults (root)
	s.font_size = 16
	s.line_height = 1.5
	s.font_weight = 400
	s.color = BLACK
	return s
}

// Copies inheritable properties from parent into s.
style_inherit :: proc(s: ^Style, p: ^Style) {
	s.font_family = p.font_family
	s.font_size = p.font_size
	s.line_height = p.line_height
	s.line_height_px = p.line_height_px
	s.font_weight = p.font_weight
	s.italic = p.italic
	s.tracking_em = p.tracking_em
	s.tracking_px = p.tracking_px
	s.color = p.color
	s.text_align = p.text_align
	s.text_transform = p.text_transform
	s.white_space = p.white_space
	s.text_wrap = p.text_wrap
	s.word_break = p.word_break
	s.indent = p.indent
	s.font_variants = p.font_variants
	s.cursor = p.cursor
	s.pointer_events = p.pointer_events
	s.user_select = p.user_select
	s.visibility = p.visibility
	s.text_shadows = p.text_shadows
	s.text_shadow_color = p.text_shadow_color
	s.text_shadow_color_set = p.text_shadow_color_set
	s.list_style = p.list_style
	s.list_inside = p.list_inside
	s.accent = p.accent
	s.accent_set = p.accent_set
	s.caret = p.caret
	s.caret_set = p.caret_set
	s.selection_bg = p.selection_bg
	s.selection_set = p.selection_set
	s.placeholder = p.placeholder
	s.placeholder_set = p.placeholder_set
	// text-decoration is not inherited in CSS but propagates to inline descendants.
	s.decoration = p.decoration
	s.decoration_color = p.decoration_color
	s.decoration_color_set = p.decoration_color_set
	s.decoration_style = p.decoration_style
	s.decoration_thickness = p.decoration_thickness
	s.underline_offset = p.underline_offset
}

line_height_px :: proc "contextless" (s: ^Style) -> f32 {
	return s.line_height_px ? s.line_height : s.line_height * s.font_size
}

letter_spacing_px :: proc "contextless" (s: ^Style) -> f32 {
	return s.tracking_em * s.font_size + s.tracking_px
}

is_inline_level :: proc "contextless" (d: Display) -> bool {
	return d == .Inline || d == .Inline_Block || d == .Inline_Flex || d == .Inline_Grid
}

is_flex :: proc "contextless" (d: Display) -> bool {
	return d == .Flex || d == .Inline_Flex
}

is_grid :: proc "contextless" (d: Display) -> bool {
	return d == .Grid || d == .Inline_Grid
}

is_scroll :: proc "contextless" (o: Overflow) -> bool {
	return o == .Auto || o == .Scroll
}

clips :: proc "contextless" (o: Overflow) -> bool {
	return o != .Visible
}

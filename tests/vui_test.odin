package vui_tests

import "core:testing"
import ui "../vui"
import "../vui/fonts"

// Builds one frame with `build` at the given viewport and returns the context for inspection.
@(private)
frame :: proc(ctx: ^ui.Context, build: proc(), vp := [2]f32{800, 600}, input := ui.Input{}) {
	ui.begin_frame(ctx, input, vp, 1, ctx.time + 1.0 / 60)
	build()
	ui.end_frame(ctx)
}

@(private)
setup :: proc(ctx: ^ui.Context) {
	ui.init(ctx)
	fonts.register(ctx)
}

@(private)
find :: proc(ctx: ^ui.Context, class: string) -> ^ui.Node {
	for &n in ctx.nodes {
		if n.class == class {
			return &n
		}
	}
	return nil
}

@(test)
parse_basic_utilities :: proc(t: ^testing.T) {
	th := ui.theme_default()
	defer ui.theme_destroy(&th)
	cs := ui.parse_classes(&th, "flex items-center gap-4 p-6 rounded-xl bg-sky-500/50 hover:bg-sky-600 md:grid-cols-3 -mt-2 w-1/2 text-sm/6 font-semibold")
	defer ui.class_set_destroy(cs)
	testing.expect_value(t, len(cs.unknown), 0)
	s := ui.style_default()
	m := ui.Match_State{viewport = 1000}
	ui.apply_class_set(&s, cs, &m, false)
	testing.expect_value(t, s.display, ui.Display.Flex)
	testing.expect_value(t, s.align_items, ui.Align.Center)
	testing.expect_value(t, s.gap, [2]f32{16, 16})
	testing.expect_value(t, s.padding, [4]f32{24, 24, 24, 24})
	testing.expect_value(t, s.radius[0], 12)
	testing.expect(t, abs(s.bg.a - 0.5) < 0.001, "opacity modifier")
	testing.expect_value(t, s.margin[0], -8)
	testing.expect_value(t, s.width, ui.Size{.Percent, 50})
	testing.expect_value(t, s.font_size, 14)
	testing.expect_value(t, s.line_height, 24)
	testing.expect_value(t, s.font_weight, 600)
	testing.expect_value(t, s.grid_cols.count, 3) // md: matches at 1000px
}

@(test)
parse_variants_gate_rules :: proc(t: ^testing.T) {
	th := ui.theme_default()
	defer ui.theme_destroy(&th)
	cs := ui.parse_classes(&th, "bg-white hover:bg-black dark:bg-gray-900 lg:p-8")
	defer ui.class_set_destroy(cs)
	s := ui.style_default()
	m := ui.Match_State{viewport = 800}
	ui.apply_class_set(&s, cs, &m, false)
	testing.expect_value(t, s.bg, ui.WHITE)
	testing.expect_value(t, s.padding[0], 0)
	s = ui.style_default()
	m = ui.Match_State{flags = {.Hover, .Dark}, viewport = 1200}
	ui.apply_class_set(&s, cs, &m, true)
	testing.expect_value(t, s.padding[0], 32)
	testing.expect(t, s.bg != ui.WHITE, "dark/hover applied")
}

@(test)
unknown_utilities_reported :: proc(t: ^testing.T) {
	th := ui.theme_default()
	defer ui.theme_destroy(&th)
	cs := ui.parse_classes(&th, "p-4 definitely-not-a-class bg-nope-500")
	defer ui.class_set_destroy(cs)
	testing.expect_value(t, len(cs.unknown), 2)
}

@(test)
flex_grow_distributes_space :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("flex w-[600px] gap-4") {
			ui.el("a w-[100px] flex-none")
			ui.el("b flex-1")
			ui.el("c flex-1")
		}
	})
	a := find(&ctx, "a w-[100px] flex-none")
	b := find(&ctx, "b flex-1")
	c := find(&ctx, "c flex-1")
	testing.expect_value(t, a.size.x, 100)
	// 600 - 100 - 2 gaps of 16 = 468, split evenly
	testing.expect_value(t, b.size.x, 234)
	testing.expect_value(t, c.size.x, 234)
	testing.expect_value(t, c.rect.x, 366)
}

@(test)
flex_justify_and_align :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("flex h-[200px] w-[400px] items-center justify-between") {
			ui.el("x size-10")
			ui.el("y size-20")
		}
	})
	x := find(&ctx, "x size-10")
	y := find(&ctx, "y size-20")
	testing.expect_value(t, x.rect.x, 0)
	testing.expect_value(t, x.rect.y, 80)
	testing.expect_value(t, y.rect.x, 320)
	testing.expect_value(t, y.rect.y, 60)
}

@(test)
grid_columns_and_spans :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("grid w-[320px] grid-cols-3 gap-4") {
			ui.el("g1 h-10")
			ui.el("g2 col-span-2 h-10")
			ui.el("g3 col-span-3 h-10")
		}
	})
	g1 := find(&ctx, "g1 h-10")
	g2 := find(&ctx, "g2 col-span-2 h-10")
	g3 := find(&ctx, "g3 col-span-3 h-10")
	testing.expect_value(t, g1.size.x, 96)
	testing.expect_value(t, g2.rect.x, 112)
	testing.expect_value(t, g2.size.x, 208)
	testing.expect_value(t, g3.rect.y, 56)
	testing.expect_value(t, g3.size.x, 320)
}

@(test)
block_stretch_and_auto_margins :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("w-[500px] p-5") {
			ui.el("s1 h-4")
			ui.el("s2 mx-auto h-4 w-[100px]")
		}
	})
	s1 := find(&ctx, "s1 h-4")
	s2 := find(&ctx, "s2 mx-auto h-4 w-[100px]")
	testing.expect_value(t, s1.size.x, 460)
	testing.expect_value(t, s2.rect.x, 200)
	testing.expect_value(t, s2.rect.y, 36)
}

@(test)
absolute_positioning :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("relative ml-[50px] h-[200px] w-[300px]") {
			ui.el("abs absolute right-4 bottom-2 size-8")
			ui.el("fill absolute inset-0")
		}
	})
	a := find(&ctx, "abs absolute right-4 bottom-2 size-8")
	f := find(&ctx, "fill absolute inset-0")
	testing.expect_value(t, a.rect.x, 50 + 300 - 16 - 32)
	testing.expect_value(t, a.rect.y, 200 - 8 - 32)
	testing.expect_value(t, f.size, [2]f32{300, 200})
}

@(test)
text_wraps_and_min_content :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("w-[120px]") {
			ui.text("The quick brown fox jumps over the lazy dog", "tx text-sm/5")
		}
	})
	n := find(&ctx, "tx text-sm/5")
	testing.expect(t, n.size.y >= 60, "text wraps onto several 20px lines")
	testing.expect(t, int(n.size.y) % 20 == 0, "height is a multiple of the line height")
	pr := &ctx.paras[n.para]
	testing.expect(t, pr.min_w > 30 && pr.min_w < 120, "min-content is the longest word")
	testing.expect(t, pr.max_w > 250, "max-content is the unbroken line")
}

@(test)
truncate_adds_ellipsis :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	frame(&ctx, proc() {
		if ui.div("w-[100px]") {
			ui.text("A long single line that cannot fit", "tr truncate")
		}
	})
	n := find(&ctx, "tr truncate")
	testing.expect_value(t, n.size.y, 24)
	testing.expect(t, ctx.paras[n.para].has_ellipsis, "ellipsis placed")
}

@(test)
click_detection_across_frames :: proc(t: ^testing.T) {
	ctx: ui.Context
	setup(&ctx)
	defer ui.destroy(&ctx)
	@(static) clicks := 0
	build :: proc() {
		if ui.button("Press", "btn absolute top-[10px] left-[10px] h-10 w-24") {
			clicks += 1
		}
	}
	frame(&ctx, build)
	frame(&ctx, build, input = {mouse = {40, 30}, mouse_inside = true})
	frame(&ctx, build, input = {mouse = {40, 30}, mouse_inside = true, buttons = {.Left}, pressed = {.Left}})
	frame(&ctx, build, input = {mouse = {40, 30}, mouse_inside = true, released = {.Left}})
	testing.expect_value(t, clicks, 1)
	// a press outside does not click
	frame(&ctx, build, input = {mouse = {400, 300}, mouse_inside = true, buttons = {.Left}, pressed = {.Left}})
	frame(&ctx, build, input = {mouse = {400, 300}, mouse_inside = true, released = {.Left}})
	testing.expect_value(t, clicks, 1)
}

@(test)
tokens_from_json :: proc(t: ^testing.T) {
	th := ui.theme_default()
	defer ui.theme_destroy(&th)
	err := ui.theme_apply_json(&th, transmute([]u8)string(`{"colors":{"brand":{"light":"#ff0000","dark":"sky-400"}},"radius":{"card":14}}`))
	testing.expect_value(t, err, "")
	testing.expect_value(t, th.colors["brand"].light, ui.Color{1, 0, 0, 1})
	testing.expect_value(t, th.radius["card"], 14)
	cs := ui.parse_classes(&th, "rounded-card bg-brand")
	defer ui.class_set_destroy(cs)
	testing.expect_value(t, len(cs.unknown), 0)
}

@(test)
variant_rules_win_over_base_regardless_of_order :: proc(t: ^testing.T) {
	th := ui.theme_default()
	defer ui.theme_destroy(&th)
	cs := ui.parse_classes(&th, "hover:bg-black md:p-8 bg-white p-2 lg:p-4")
	defer ui.class_set_destroy(cs)
	s := ui.style_default()
	m := ui.Match_State{flags = {.Hover}, viewport = 1100}
	ui.apply_class_set(&s, cs, &m, false)
	testing.expect_value(t, s.bg, ui.BLACK)
	testing.expect_value(t, s.padding[0], 16) // lg beats md and base
}

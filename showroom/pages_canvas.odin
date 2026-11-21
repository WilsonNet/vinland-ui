package showroom

import "core:math"
import ui "../vui"

page_canvas :: proc() {
	para("Utilities cover boxes and text. For charts, meters, dials and anything else that is drawn rather than laid out, use ui.canvas: the element takes part in layout like any other box, and a procedure you supply draws into its rect with vector primitives.")
	h2("Drawing primitives")
	ref_table({
		{"ui.canvas(class, draw, data)", "box whose content is drawn by draw(ctx, rect, data) every frame"},
		{"ui.draw_rect(ctx, rect, color, radius)", "filled (rounded) rectangle"},
		{"ui.draw_line(ctx, a, b, color, width)", "anti-aliased segment with round caps"},
		{"ui.draw_polyline(ctx, points, color, width)", "connected segments: curves, waveforms"},
		{"ui.draw_arc(ctx, center, r, start, sweep, color, width)", "stroked arc, radians clockwise from +x"},
		{"ui.draw_circle(ctx, center, r, color)", "filled disc"},
		{"ui.draw_area(ctx, points, base_y, top, bottom)", "fill under a curve with a vertical gradient"},
		{"ui.oklch(l, c, h)", "colors in OKLCH, the same space as Tailwind v4 and modern CSS"},
	})
	para("Coordinates are logical pixels in window space; the renderer scales them to the display. Every primitive is one GPU instance shaded with a signed distance function, so edges are anti-aliased at any scale and nothing is tessellated on the CPU. A 160-point curve costs 160 instances; a full mixing-desk screen stays around 600.")

	h2("Frequency response")
	para("draw_area fills under the curve with a gradient, draw_polyline strokes it, draw_circle marks the band nodes.")
	if example("p-6", false) {
		ui.canvas("h-40 w-full", eq_chart)
	}

	h2("Dials")
	para("A 270° dial is two arcs and a pointer line. The canvas sits in a normal flex layout with its label underneath.")
	if example("p-8") {
		if ui.div("flex gap-8") {
			values := [4]f32{0.15, 0.4, 0.65, 0.9}
			for v, i in values {
				ui.push_id(i)
				if ui.div("flex flex-col items-center gap-1") {
					d := new(f32, context.temp_allocator)
					d^ = v
					ui.canvas("size-12", dial, d)
					ui.text(DIAL_LABELS[i], "text-xs font-medium tracking-wide text-gray-500 dark:text-gray-400")
				}
				ui.pop_id()
			}
		}
	}

	h2("Live sparklines")
	para("Canvases redraw every frame, so they can follow live data. These lines are driven by the clock.")
	if example("p-6", false) {
		if ui.div("grid grid-cols-3 gap-4") {
			for i in 0 ..< 3 {
				ui.push_id(i)
				if ui.div("rounded-lg p-3 ring-1 ring-gray-950/10 dark:ring-white/10") {
					ui.text(SPARK_LABELS[i], "text-xs font-medium text-gray-500 dark:text-gray-400")
					d := new(int, context.temp_allocator)
					d^ = i
					ui.canvas("mt-2 h-12 w-full", sparkline, d)
				}
				ui.pop_id()
			}
		}
	}
	note("Draw procedures run during painting. Keep them allocation-free or use context.temp_allocator, which is reset after each frame.")
}

DIAL_LABELS := [4]string{"Gain", "Drive", "Tone", "Mix"}
SPARK_LABELS := [3]string{"CPU", "Network", "Latency"}

@(private = "file")
accent :: proc() -> ui.Color {
	return ui.oklch(0.70, 0.17, 285) if ui.is_dark() else ui.oklch(0.54, 0.24, 285)
}

@(private = "file")
grid_color :: proc() -> ui.Color {
	return ui.with_alpha(ui.WHITE, 0.08) if ui.is_dark() else ui.with_alpha(ui.BLACK, 0.06)
}

eq_chart :: proc(ctx: ^ui.Context, r: ui.Rect, data: rawptr) {
	for i in 1 ..< 8 {
		x := r.x + r.w * f32(i) / 8
		ui.draw_rect(ctx, {x, r.y, 1, r.h}, grid_color())
	}
	mid := r.y + r.h * 0.5
	ui.draw_rect(ctx, {r.x, mid, r.w, 1}, grid_color())
	pts := make([][2]f32, 200, context.temp_allocator)
	bands := [3][3]f32{{0.15, 6, 0.10}, {0.5, -4, 0.08}, {0.8, 5, 0.12}} // position, gain dB, width
	for &p, i in pts {
		u := f32(i) / f32(len(pts) - 1)
		db: f32 = 0
		for b in bands {
			db += b[1] * math.exp(-math.pow((u - b[0]) / b[2], 2))
		}
		p = {r.x + u * r.w, mid - db / 12 * r.h * 0.45}
	}
	c := accent()
	ui.draw_area(ctx, pts, r.y + r.h, ui.with_alpha(c, 0.30), ui.with_alpha(c, 0.0))
	ui.draw_polyline(ctx, pts, c, 1.5)
	for b in bands {
		ui.draw_circle(ctx, {r.x + b[0] * r.w, mid - b[1] / 12 * r.h * 0.45}, 3.5, c)
	}
}

dial :: proc(ctx: ^ui.Context, r: ui.Rect, data: rawptr) {
	v := (^f32)(data)^
	c := [2]f32{r.x + r.w * 0.5, r.y + r.h * 0.5}
	rad := r.w * 0.5 - 3
	start := f32(math.PI) * 0.75
	sweep := f32(math.PI) * 1.5
	ui.draw_arc(ctx, c, rad, start, sweep, grid_color() * {1, 1, 1, 2}, 3)
	ui.draw_arc(ctx, c, rad, start, sweep * v, accent(), 3)
	ang := start + sweep * v
	dir := [2]f32{math.cos(ang), math.sin(ang)}
	ink := ui.WHITE if ui.is_dark() else ui.oklch(0.21, 0.03, 265)
	ui.draw_line(ctx, c + dir * (rad - 9), c + dir * (rad - 2), ink, 2)
}

sparkline :: proc(ctx: ^ui.Context, r: ui.Rect, data: rawptr) {
	k := f32((^int)(data)^)
	t := f32(ui.ctx_get().time)
	pts := make([][2]f32, 64, context.temp_allocator)
	for &p, i in pts {
		u := f32(i) / f32(len(pts) - 1)
		y := 0.5 + 0.3 * math.sin(u * 9 + t * (1.2 + k * 0.4) + k) + 0.12 * math.sin(u * 23 - t * 2.1)
		p = {r.x + u * r.w, r.y + r.h * (1 - clamp(y, 0.05, 0.95))}
	}
	c := accent()
	ui.draw_area(ctx, pts, r.y + r.h, ui.with_alpha(c, 0.25), ui.with_alpha(c, 0))
	ui.draw_polyline(ctx, pts, c, 1.25)
	ui.ctx_get().animating = true
}

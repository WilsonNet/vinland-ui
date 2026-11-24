// Procedural, tileable material textures for skeuomorphic UI (game HUDs, tool chrome).
//
// Two families, both used through the `bg-tex-<name>` utility, which multiplies the texture
// with the element's background colour or gradient:
//
//   Relief (opaque, light grey luminance): hammered, brushed, grain, stone, parchment, weave.
//     `bg-amber-700 bg-tex-hammered bg-tile-96` reads as hammered brass;
//     `bg-linear-to-b from-amber-200 to-amber-800 bg-tex-brushed` as lit, brushed metal.
//   Masks (white, pattern in alpha): khatam, interlace, studs.
//     `bg-zinc-300 bg-tex-khatam bg-tile-48` on a dark panel reads as silver inlay.
//
// Everything is generated at startup in a few milliseconds: no image files, no licences.
package vui_materials

import "core:math"
import ui ".."

Material :: enum {
	Hammered,
	Brushed,
	Grain,
	Stone,
	Parchment,
	Weave,
	Khatam,
	Interlace,
	Studs,
}

MATERIAL_NAMES := [Material]string {
	.Hammered  = "hammered",
	.Brushed   = "brushed",
	.Grain     = "grain",
	.Stone     = "stone",
	.Parchment = "parchment",
	.Weave     = "weave",
	.Khatam    = "khatam",
	.Interlace = "interlace",
	.Studs     = "studs",
}

SIZE :: 256

// Generates every material, registers it as an image and names it for `bg-tex-<name>`.
register :: proc(ctx: ^ui.Context, seed: u32 = 1) -> (ids: [Material]ui.Image_Id) {
	pix := make([]u8, SIZE * SIZE * 4, context.temp_allocator)
	for m in Material {
		generate(m, pix, SIZE, seed)
		ids[m] = ui.image_register(ctx, pix, SIZE, SIZE)
		ui.image_name(ctx, MATERIAL_NAMES[m], ids[m])
	}
	return
}

generate :: proc(m: Material, pix: []u8, n: int, seed: u32) {
	for y in 0 ..< n {
		for x in 0 ..< n {
			u := (f32(x) + 0.5) / f32(n)
			v := (f32(y) + 0.5) / f32(n)
			lum, alpha: f32 = 1, 1
			switch m {
			case .Hammered:
				lum = hammered(u, v, seed)
			case .Brushed:
				lum = 0.86 + 0.1 * fbm(u * 2, v * 48, 4, 2, 48, seed + 7) + 0.05 * fbm(u * 8, v * 8, 2, 8, 8, seed + 3)
			case .Grain:
				lum = grain(u, v, seed)
			case .Stone:
				lum = stone(u, v, seed)
			case .Parchment:
				lum = 0.9 + 0.1 * fbm(u * 4, v * 4, 5, 4, 4, seed + 11) - 0.05 * fbm(u * 16, v * 16, 2, 16, 16, seed + 5)
			case .Weave:
				lum = weave(u, v, seed)
			case .Khatam:
				lum, alpha = 1, khatam(u, v)
			case .Interlace:
				lum, alpha = 1, interlace(u, v)
			case .Studs:
				lum, alpha = studs(u, v)
			}
			i := (y * n + x) * 4
			c := u8(clamp(lum, 0, 1) * 255 + 0.5)
			pix[i + 0] = c
			pix[i + 1] = c
			pix[i + 2] = c
			pix[i + 3] = u8(clamp(alpha, 0, 1) * 255 + 0.5)
		}
	}
}

// ---------------------------------------------------------------------------
// Tileable noise
// ---------------------------------------------------------------------------

@(private)
hash2 :: proc "contextless" (x, y: i32, seed: u32) -> f32 {
	h := u32(x) * 374761393 + u32(y) * 668265263 + seed * 2246822519
	h = (h ~ (h >> 13)) * 1274126177
	h ~= h >> 16
	return f32(h & 0xffffff) / f32(0xffffff)
}

@(private)
wrap :: proc "contextless" (i, p: i32) -> i32 {
	r := i % p
	return r < 0 ? r + p : r
}

// Value noise with period (px, py) lattice cells.
@(private)
vnoise :: proc "contextless" (x, y: f32, px, py: i32, seed: u32) -> f32 {
	x0 := i32(math.floor(x))
	y0 := i32(math.floor(y))
	fx := x - f32(x0)
	fy := y - f32(y0)
	sx := fx * fx * (3 - 2 * fx)
	sy := fy * fy * (3 - 2 * fy)
	a := hash2(wrap(x0, px), wrap(y0, py), seed)
	b := hash2(wrap(x0 + 1, px), wrap(y0, py), seed)
	c := hash2(wrap(x0, px), wrap(y0 + 1, py), seed)
	d := hash2(wrap(x0 + 1, px), wrap(y0 + 1, py), seed)
	return math.lerp(math.lerp(a, b, sx), math.lerp(c, d, sx), sy)
}

// Fractal noise in [0, 1]; x/y already scaled to (px, py) base cells.
@(private)
fbm :: proc "contextless" (x, y: f32, octaves: int, px, py: i32, seed: u32) -> f32 {
	sum, amp, norm: f32 = 0, 0.5, 0
	fx, fy := x, y
	cx, cy := px, py
	for o in 0 ..< octaves {
		sum += amp * vnoise(fx, fy, cx, cy, seed + u32(o) * 101)
		norm += amp
		amp *= 0.5
		fx *= 2
		fy *= 2
		cx *= 2
		cy *= 2
	}
	return sum / norm
}

// ---------------------------------------------------------------------------
// Reliefs
// ---------------------------------------------------------------------------

// Hammered metal: Worley cells shaded as shallow dimples lit from the top left.
@(private)
hammered :: proc(u, v: f32, seed: u32) -> f32 {
	CELLS :: 7
	x := u * CELLS
	y := v * CELLS
	ix := i32(math.floor(x))
	iy := i32(math.floor(y))
	best: f32 = 9
	bvec: [2]f32
	for dy in i32(-1) ..= 1 {
		for dx in i32(-1) ..= 1 {
			cx := ix + dx
			cy := iy + dy
			jx := hash2(wrap(cx, CELLS), wrap(cy, CELLS), seed + 17)
			jy := hash2(wrap(cx, CELLS), wrap(cy, CELLS), seed + 29)
			p := [2]f32{f32(cx) + 0.15 + 0.7 * jx, f32(cy) + 0.15 + 0.7 * jy}
			d := [2]f32{x, y} - p
			dd := d.x * d.x + d.y * d.y
			if dd < best {
				best = dd
				bvec = d
			}
		}
	}
	dist := math.sqrt(best)
	// dimple normal points away from the cell centre; light comes from (-1, -1)
	n := bvec / max(dist, 1e-4)
	slope := min(dist * 1.6, 1)
	light := -(n.x * -0.7071 + n.y * -0.7071) * slope
	grain := fbm(u * 32, v * 32, 2, 32, 32, seed + 3)
	return 0.84 + 0.11 * light + 0.05 * grain
}

// Wood grain running along x.
@(private)
grain :: proc(u, v: f32, seed: u32) -> f32 {
	warp := fbm(u * 2, v * 4, 4, 2, 4, seed + 13)
	rings := math.sin((v * 22 + warp * 3.2) * math.PI * 2) * 0.5 + 0.5
	fine := fbm(u * 4, v * 96, 3, 4, 96, seed + 5)
	return 0.72 + 0.16 * rings * rings + 0.1 * fine
}

// Dressed stone: low-frequency mottling plus pits.
@(private)
stone :: proc(u, v: f32, seed: u32) -> f32 {
	base := fbm(u * 4, v * 4, 5, 4, 4, seed + 23)
	pits := fbm(u * 24, v * 24, 2, 24, 24, seed + 31)
	pit: f32 = pits < 0.28 ? (0.28 - pits) * 1.4 : 0
	return 0.74 + 0.22 * base - pit
}

// Plain-weave cloth.
@(private)
weave :: proc(u, v: f32, seed: u32) -> f32 {
	T :: 32
	x := u * T
	y := v * T
	fx := x - math.floor(x)
	fy := y - math.floor(y)
	over := (i32(math.floor(x)) + i32(math.floor(y))) & 1 == 0
	t := over ? math.sin(fy * math.PI) : math.sin(fx * math.PI)
	jitter := fbm(u * 8, v * 8, 2, 8, 8, seed + 41)
	return 0.7 + 0.24 * t + 0.06 * jitter
}

// ---------------------------------------------------------------------------
// Masks (alpha = pattern)
// ---------------------------------------------------------------------------

@(private)
line_cov :: proc "contextless" (d, half_w, aa: f32) -> f32 {
	return clamp((half_w - d) / aa + 0.5, 0, 1)
}

// Distance from p to the outline of a square of half size h rotated by angle a.
@(private)
square_dist :: proc "contextless" (p: [2]f32, h, a: f32) -> f32 {
	c := math.cos(a)
	s := math.sin(a)
	q := [2]f32{abs(c * p.x + s * p.y), abs(-s * p.x + c * p.y)}
	return abs(max(q.x, q.y) - h)
}

// Khatam: the eight-pointed star made of two overlapping squares, on a square lattice, with
// the connecting strapwork that runs between neighbouring stars (Mamluk and Andalusian
// geometric inlay).
@(private)
khatam :: proc(u, v: f32) -> f32 {
	p := [2]f32{u - 0.5, v - 0.5}
	AA :: 1.0 / SIZE
	W :: 0.018
	star := min(square_dist(p, 0.2, 0), square_dist(p, 0.2, math.PI / 4))
	inner := min(square_dist(p, 0.09, 0), square_dist(p, 0.09, math.PI / 4))
	// strapwork: diagonal bands linking star tips across tile corners
	q := [2]f32{abs(p.x), abs(p.y)}
	diag := abs(q.x - q.y) * 0.70710678
	strap := (q.x + q.y) > 0.62 ? diag : 9
	// cross bars at tile edges between stars
	edge := min(abs(abs(p.x) - 0.5), abs(abs(p.y) - 0.5))
	bars := (abs(p.x) < 0.06 || abs(p.y) < 0.06) && edge < 0.2 ? min(abs(abs(p.x) - 0.06), abs(abs(p.y) - 0.06)) : 9
	d := min(min(star, inner), min(strap, bars))
	return line_cov(d, W, AA)
}

// Interlace: overlapping circles on a lattice, the shared vocabulary of Romanesque and
// Islamic borders.
@(private)
interlace :: proc(u, v: f32) -> f32 {
	AA :: 1.0 / SIZE
	W :: 0.02
	d: f32 = 9
	for cy in 0 ..= 2 {
		for cx in 0 ..= 2 {
			c := [2]f32{f32(cx) * 0.5, f32(cy) * 0.5}
			dist := abs(math.sqrt((u - c.x) * (u - c.x) + (v - c.y) * (v - c.y)) - 0.36)
			d = min(d, dist)
		}
	}
	return line_cov(d, W, AA)
}

// Studs: domed rivet heads, lit from the top left (luminance + alpha).
@(private)
studs :: proc(u, v: f32) -> (lum, alpha: f32) {
	p := [2]f32{u - 0.5, v - 0.5}
	r := math.sqrt(p.x * p.x + p.y * p.y)
	R :: 0.16
	alpha = clamp((R - r) * SIZE + 0.5, 0, 1)
	h := math.sqrt(max(0, R * R - r * r)) / R
	n := [3]f32{p.x / R, p.y / R, h}
	light := n.x * -0.5 + n.y * -0.5 + n.z * 0.7
	lum = clamp(0.45 + 0.6 * light, 0, 1)
	return
}

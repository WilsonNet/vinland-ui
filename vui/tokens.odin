package vui

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// A color token. Plain colors have light == dark; semantic tokens differ per scheme.
Color_Token :: struct {
	light, dark: Color,
}

Shadow :: struct {
	offset: [2]f32,
	blur:   f32,
	spread: f32,
	color:  Color,
	inset:  bool,
}

MAX_SHADOWS :: 4

Shadow_Set :: struct {
	items: [MAX_SHADOWS]Shadow,
	count: int,
}

Text_Size :: struct {
	size:        f32, // px
	line_height: f32, // multiplier
}

Easing :: [4]f32 // cubic-bezier control points

EASE_LINEAR :: Easing{0, 0, 1, 1}
EASE_IN :: Easing{0.4, 0, 1, 1}
EASE_OUT :: Easing{0, 0, 0.2, 1}
EASE_IN_OUT :: Easing{0.4, 0, 0.2, 1}

// Design tokens. Every utility resolves through this table, so swapping a Theme
// re-skins an app without touching code. Load overrides from JSON with theme_load_json.
Theme :: struct {
	name:          string,
	spacing:       f32, // px per spacing unit (Tailwind: 4)
	colors:        map[string]Color_Token,
	radius:        map[string]f32,
	shadows:       map[string]Shadow_Set,
	inset_shadows: map[string]Shadow_Set,
	drop_shadows:  map[string]Shadow_Set,
	text_shadows:  map[string]Shadow_Set,
	text_sizes:    map[string]Text_Size,
	font_weights:  map[string]int,
	tracking:      map[string]f32, // em
	leading:       map[string]f32, // multiplier
	breakpoints:   map[string]f32, // px, min-width
	containers:    map[string]f32, // px
	blur:          map[string]f32,
	easings:       map[string]Easing,
	fonts:         map[string]string, // family token ("sans") -> registered family name ("Inter")
	default_font:  string, // family token used by the root
	default_duration_ms: f32,
	default_easing:      Easing,
	version:       u64,
}

rem :: proc "contextless" (r: f32) -> f32 {
	return r * 16
}

@(private = "file")
shadow_set :: proc(shadows: ..Shadow) -> Shadow_Set {
	s: Shadow_Set
	for sh, i in shadows {
		if i >= MAX_SHADOWS {
			break
		}
		s.items[i] = sh
		s.count += 1
	}
	return s
}

@(private = "file")
sh :: proc(x, y, blur, spread: f32, hex: u32, a: f32, inset := false) -> Shadow {
	return Shadow{offset = {x, y}, blur = blur, spread = spread, color = rgb(hex, a), inset = inset}
}

// Builds the default token set: Tailwind CSS v4's theme, verbatim.
theme_default :: proc(allocator := context.allocator) -> Theme {
	context.allocator = allocator
	t: Theme
	t.name = "tailwind"
	t.spacing = 4
	t.default_duration_ms = 150
	t.default_easing = EASE_IN_OUT
	t.default_font = "sans"

	t.colors["transparent"] = {TRANSPARENT, TRANSPARENT}
	t.colors["black"] = {BLACK, BLACK}
	t.colors["white"] = {WHITE, WHITE}
	for fam in PALETTE {
		for shade, i in PALETTE_SHADES {
			name := fmt.aprintf("%s-%d", fam.name, shade)
			c := rgb(fam.shades[i])
			t.colors[name] = {c, c}
		}
	}

	t.radius["none"] = 0
	t.radius["xs"] = 2
	t.radius["sm"] = 4
	t.radius["md"] = 6
	t.radius["lg"] = 8
	t.radius["xl"] = 12
	t.radius["2xl"] = 16
	t.radius["3xl"] = 24
	t.radius["4xl"] = 32
	t.radius["full"] = 9999

	t.shadows["none"] = {}
	t.shadows["2xs"] = shadow_set(sh(0, 1, 0, 0, 0, 0.05))
	t.shadows["xs"] = shadow_set(sh(0, 1, 2, 0, 0, 0.05))
	t.shadows["sm"] = shadow_set(sh(0, 1, 3, 0, 0, 0.1), sh(0, 1, 2, -1, 0, 0.1))
	t.shadows["md"] = shadow_set(sh(0, 4, 6, -1, 0, 0.1), sh(0, 2, 4, -2, 0, 0.1))
	t.shadows["lg"] = shadow_set(sh(0, 10, 15, -3, 0, 0.1), sh(0, 4, 6, -4, 0, 0.1))
	t.shadows["xl"] = shadow_set(sh(0, 20, 25, -5, 0, 0.1), sh(0, 8, 10, -6, 0, 0.1))
	t.shadows["2xl"] = shadow_set(sh(0, 25, 50, -12, 0, 0.25))

	t.inset_shadows["none"] = {}
	t.inset_shadows["2xs"] = shadow_set(sh(0, 1, 0, 0, 0, 0.05, true))
	t.inset_shadows["xs"] = shadow_set(sh(0, 1, 1, 0, 0, 0.05, true))
	t.inset_shadows["sm"] = shadow_set(sh(0, 2, 4, 0, 0, 0.05, true))

	t.drop_shadows["none"] = {}
	t.drop_shadows["xs"] = shadow_set(sh(0, 1, 1, 0, 0, 0.05))
	t.drop_shadows["sm"] = shadow_set(sh(0, 1, 2, 0, 0, 0.15))
	t.drop_shadows["md"] = shadow_set(sh(0, 3, 3, 0, 0, 0.12))
	t.drop_shadows["lg"] = shadow_set(sh(0, 4, 4, 0, 0, 0.15))
	t.drop_shadows["xl"] = shadow_set(sh(0, 9, 7, 0, 0, 0.1))
	t.drop_shadows["2xl"] = shadow_set(sh(0, 25, 25, 0, 0, 0.15))

	t.text_shadows["none"] = {}
	t.text_shadows["2xs"] = shadow_set(sh(0, 1, 0, 0, 0, 0.15))
	t.text_shadows["xs"] = shadow_set(sh(0, 1, 1, 0, 0, 0.2))
	t.text_shadows["sm"] = shadow_set(sh(0, 1, 0, 0, 0, 0.075), sh(0, 1, 1, 0, 0, 0.075), sh(0, 2, 2, 0, 0, 0.075))
	t.text_shadows["md"] = shadow_set(sh(0, 1, 1, 0, 0, 0.1), sh(0, 1, 2, 0, 0, 0.1), sh(0, 2, 4, 0, 0, 0.1))
	t.text_shadows["lg"] = shadow_set(sh(0, 1, 2, 0, 0, 0.1), sh(0, 3, 2, 0, 0, 0.1), sh(0, 4, 8, 0, 0, 0.1))

	t.text_sizes["xs"] = {12, 1.0 / 0.75}
	t.text_sizes["sm"] = {14, 1.25 / 0.875}
	t.text_sizes["base"] = {16, 1.5}
	t.text_sizes["lg"] = {18, 1.75 / 1.125}
	t.text_sizes["xl"] = {20, 1.75 / 1.25}
	t.text_sizes["2xl"] = {24, 2 / 1.5}
	t.text_sizes["3xl"] = {30, 2.25 / 1.875}
	t.text_sizes["4xl"] = {36, 2.5 / 2.25}
	t.text_sizes["5xl"] = {48, 1}
	t.text_sizes["6xl"] = {60, 1}
	t.text_sizes["7xl"] = {72, 1}
	t.text_sizes["8xl"] = {96, 1}
	t.text_sizes["9xl"] = {128, 1}

	t.font_weights["thin"] = 100
	t.font_weights["extralight"] = 200
	t.font_weights["light"] = 300
	t.font_weights["normal"] = 400
	t.font_weights["medium"] = 500
	t.font_weights["semibold"] = 600
	t.font_weights["bold"] = 700
	t.font_weights["extrabold"] = 800
	t.font_weights["black"] = 900

	t.tracking["tighter"] = -0.05
	t.tracking["tight"] = -0.025
	t.tracking["normal"] = 0
	t.tracking["wide"] = 0.025
	t.tracking["wider"] = 0.05
	t.tracking["widest"] = 0.1

	t.leading["none"] = 1
	t.leading["tight"] = 1.25
	t.leading["snug"] = 1.375
	t.leading["normal"] = 1.5
	t.leading["relaxed"] = 1.625
	t.leading["loose"] = 2

	t.breakpoints["sm"] = 640
	t.breakpoints["md"] = 768
	t.breakpoints["lg"] = 1024
	t.breakpoints["xl"] = 1280
	t.breakpoints["2xl"] = 1536

	t.containers["3xs"] = 256
	t.containers["2xs"] = 288
	t.containers["xs"] = 320
	t.containers["sm"] = 384
	t.containers["md"] = 448
	t.containers["lg"] = 512
	t.containers["xl"] = 576
	t.containers["2xl"] = 672
	t.containers["3xl"] = 768
	t.containers["4xl"] = 896
	t.containers["5xl"] = 1024
	t.containers["6xl"] = 1152
	t.containers["7xl"] = 1280
	t.containers["prose"] = 65 * 8.5

	t.blur["none"] = 0
	t.blur["xs"] = 4
	t.blur["sm"] = 8
	t.blur["md"] = 12
	t.blur["lg"] = 16
	t.blur["xl"] = 24
	t.blur["2xl"] = 40
	t.blur["3xl"] = 64

	t.easings["linear"] = EASE_LINEAR
	t.easings["in"] = EASE_IN
	t.easings["out"] = EASE_OUT
	t.easings["in-out"] = EASE_IN_OUT

	t.fonts["sans"] = "Inter"
	t.fonts["serif"] = "Source Serif 4"
	t.fonts["mono"] = "IBM Plex Mono"
	return t
}

theme_destroy :: proc(t: ^Theme) {
	for k in t.colors {
		// keys for palette entries were allocated; literal keys are static. Leak-safe enough
		// for a process-lifetime object; explicit cleanup frees maps only.
		_ = k
	}
	delete(t.colors)
	delete(t.radius)
	delete(t.shadows)
	delete(t.inset_shadows)
	delete(t.drop_shadows)
	delete(t.text_shadows)
	delete(t.text_sizes)
	delete(t.font_weights)
	delete(t.tracking)
	delete(t.leading)
	delete(t.breakpoints)
	delete(t.containers)
	delete(t.blur)
	delete(t.easings)
	delete(t.fonts)
}

// Defines or replaces a color token. `dark` defaults to `light`.
theme_set_color :: proc(t: ^Theme, name: string, light: Color, dark: Maybe(Color) = nil) {
	d, has := dark.?
	key := name
	if name not_in t.colors {
		key = strings.clone(name)
	}
	t.colors[key] = {light, has ? d : light}
	t.version += 1
}

// Resolves "sky-500", "#0ea5e9", "rgb(..)" or any defined token name.
theme_lookup_color :: proc(t: ^Theme, s: string) -> (Color_Token, bool) {
	if tok, ok := t.colors[s]; ok {
		return tok, true
	}
	if c, ok := parse_css_color(s); ok {
		return {c, c}, true
	}
	return {}, false
}

// Applies overrides from a JSON theme file. Shape:
// {
//   "name": "dusk",
//   "spacing": 4,
//   "colors": { "accent": {"light": "sky-600", "dark": "#38bdf8"}, "brand": "#ff5500" },
//   "radius": { "lg": 10 },
//   "fonts":  { "sans": "Inter" },
//   "textSizes": { "sm": [14, 1.5] },
//   "breakpoints": { "md": 760 }
// }
// Color values may reference other tokens. Unknown keys are ignored.
theme_load_json :: proc(t: ^Theme, path: string) -> (err: string) {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return fmt.tprintf("cannot read %s", path)
	}
	return theme_apply_json(t, data)
}

theme_apply_json :: proc(t: ^Theme, data: []byte) -> (err: string) {
	root, jerr := json.parse(data, allocator = context.temp_allocator)
	if jerr != nil {
		return fmt.tprintf("theme json: %v", jerr)
	}
	obj, is_obj := root.(json.Object)
	if !is_obj {
		return "theme json: root must be an object"
	}
	num :: proc(v: json.Value) -> (f32, bool) {
		#partial switch x in v {
		case json.Float:
			return f32(x), true
		case json.Integer:
			return f32(x), true
		}
		return 0, false
	}
	color_of :: proc(t: ^Theme, v: json.Value) -> (Color_Token, bool) {
		#partial switch x in v {
		case json.String:
			return theme_lookup_color(t, x)
		case json.Object:
			l, lok := color_of(t, x["light"])
			d, dok := color_of(t, x["dark"])
			if lok && dok {
				return {l.light, d.dark}, true
			}
			if lok {
				return l, true
			}
		}
		return {}, false
	}
	if name, nok := obj["name"].(json.String); nok {
		t.name = strings.clone(name)
	}
	if s, sok := num(obj["spacing"]); sok {
		t.spacing = s
	}
	if colors, cok := obj["colors"].(json.Object); cok {
		for k, v in colors {
			if tok, vok := color_of(t, v); vok {
				key := k
				if k not_in t.colors {
					key = strings.clone(k)
				}
				t.colors[key] = tok
			}
		}
	}
	float_map :: proc(dst: ^map[string]f32, v: json.Value) {
		if o, ok := v.(json.Object); ok {
			for k, x in o {
				if f, fok := num(x); fok {
					key := k
					if k not_in dst^ {
						key = strings.clone(k)
					}
					dst[key] = f
				}
			}
		}
	}
	float_map(&t.radius, obj["radius"])
	float_map(&t.breakpoints, obj["breakpoints"])
	float_map(&t.containers, obj["containers"])
	float_map(&t.tracking, obj["tracking"])
	float_map(&t.leading, obj["leading"])
	if fonts, fok := obj["fonts"].(json.Object); fok {
		for k, v in fonts {
			if s, sok := v.(json.String); sok {
				key := k
				if k not_in t.fonts {
					key = strings.clone(k)
				}
				t.fonts[key] = strings.clone(s)
			}
		}
	}
	if sizes, sok := obj["textSizes"].(json.Object); sok {
		for k, v in sizes {
			if arr, aok := v.(json.Array); aok && len(arr) == 2 {
				s, _ := num(arr[0])
				l, _ := num(arr[1])
				key := k
				if k not_in t.text_sizes {
					key = strings.clone(k)
				}
				t.text_sizes[key] = {s, l}
			}
		}
	}
	if d, dok := num(obj["durationMs"]); dok {
		t.default_duration_ms = d
	}
	t.version += 1
	return ""
}

// Parses a CSS length in px/rem/em (em relative to 16).
parse_length :: proc(s: string) -> (f32, bool) {
	if strings.has_suffix(s, "px") {
		return strconv.parse_f32(s[:len(s) - 2])
	}
	if strings.has_suffix(s, "rem") {
		v, ok := strconv.parse_f32(s[:len(s) - 3])
		return v * 16, ok
	}
	if strings.has_suffix(s, "em") {
		v, ok := strconv.parse_f32(s[:len(s) - 2])
		return v * 16, ok
	}
	return strconv.parse_f32(s)
}

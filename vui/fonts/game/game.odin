// Optional display set for game and fantasy UI: Cinzel (inscriptional Roman capitals), Cinzel
// Decorative (swash capitals: single words only, its swashes garble multi-word lines) and
// Alegreya Sans (humanist sans with real tabular figures). SIL Open Font License 1.1
// (assets/fonts/Cinzel-OFL.txt, CinzelDecorative-OFL.txt, AlegreyaSans-OFL.txt).
//
// register() adds the families and the theme tokens `font-display` (Cinzel),
// `font-decorative` (Cinzel Decorative) and `font-game` (Alegreya Sans).
package vui_fonts_game

import "core:strings"
import vui "../.."

CINZEL :: #load("../../../assets/fonts/Cinzel-Variable.ttf") // default instance (400)
CINZEL_DECORATIVE_REGULAR :: #load("../../../assets/fonts/CinzelDecorative-Regular.ttf")
CINZEL_DECORATIVE_BOLD :: #load("../../../assets/fonts/CinzelDecorative-Bold.ttf")
ALEGREYA_SANS_MEDIUM :: #load("../../../assets/fonts/AlegreyaSans-Medium.ttf")
ALEGREYA_SANS_BOLD :: #load("../../../assets/fonts/AlegreyaSans-Bold.ttf")
ALEGREYA_SANS_EXTRABOLD :: #load("../../../assets/fonts/AlegreyaSans-ExtraBold.ttf")

register :: proc(ctx: ^vui.Context) {
	f := &ctx.fonts
	vui.font_register(f, "Cinzel", CINZEL, 400)
	vui.font_register(f, "Cinzel Decorative", CINZEL_DECORATIVE_REGULAR, 400)
	vui.font_register(f, "Cinzel Decorative", CINZEL_DECORATIVE_BOLD, 700)
	vui.font_register(f, "Alegreya Sans", ALEGREYA_SANS_MEDIUM, 500)
	vui.font_register(f, "Alegreya Sans", ALEGREYA_SANS_BOLD, 700)
	vui.font_register(f, "Alegreya Sans", ALEGREYA_SANS_EXTRABOLD, 800)
	set_token(&ctx.theme, "display", "Cinzel")
	set_token(&ctx.theme, "decorative", "Cinzel Decorative")
	set_token(&ctx.theme, "game", "Alegreya Sans")
	vui.theme_changed()
}

@(private)
set_token :: proc(t: ^vui.Theme, key, family: string) {
	if _, ok := t.fonts[key]; ok {
		t.fonts[key] = family
		return
	}
	k := strings.clone(key)
	append(&t.owned, k)
	t.fonts[k] = family
}

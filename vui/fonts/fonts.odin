// Optional embedded font set: Inter (sans), IBM Plex Mono (mono), Source Serif 4 (serif).
// All SIL Open Font License 1.1 (see assets/fonts/*-OFL*). Import this package and call
// fonts.register(&ctx) once; skip it to ship your own fonts via vui.font_register.
package vui_fonts

import vui ".."

INTER_THIN :: #load("../../assets/fonts/Inter-Thin.ttf")
INTER_EXTRALIGHT :: #load("../../assets/fonts/Inter-ExtraLight.ttf")
INTER_LIGHT :: #load("../../assets/fonts/Inter-Light.ttf")
INTER_REGULAR :: #load("../../assets/fonts/Inter-Regular.ttf")
INTER_MEDIUM :: #load("../../assets/fonts/Inter-Medium.ttf")
INTER_SEMIBOLD :: #load("../../assets/fonts/Inter-SemiBold.ttf")
INTER_BOLD :: #load("../../assets/fonts/Inter-Bold.ttf")
INTER_EXTRABOLD :: #load("../../assets/fonts/Inter-ExtraBold.ttf")
INTER_BLACK :: #load("../../assets/fonts/Inter-Black.ttf")
INTER_ITALIC :: #load("../../assets/fonts/Inter-Italic.ttf")
INTER_MEDIUM_ITALIC :: #load("../../assets/fonts/Inter-MediumItalic.ttf")
INTER_SEMIBOLD_ITALIC :: #load("../../assets/fonts/Inter-SemiBoldItalic.ttf")
INTER_BOLD_ITALIC :: #load("../../assets/fonts/Inter-BoldItalic.ttf")
PLEX_MONO_REGULAR :: #load("../../assets/fonts/IBMPlexMono-Regular.ttf")
PLEX_MONO_ITALIC :: #load("../../assets/fonts/IBMPlexMono-Italic.ttf")
PLEX_MONO_MEDIUM :: #load("../../assets/fonts/IBMPlexMono-Medium.ttf")
PLEX_MONO_SEMIBOLD :: #load("../../assets/fonts/IBMPlexMono-SemiBold.ttf")
PLEX_MONO_BOLD :: #load("../../assets/fonts/IBMPlexMono-Bold.ttf")
SERIF_REGULAR :: #load("../../assets/fonts/SourceSerif4-Regular.ttf")
SERIF_ITALIC :: #load("../../assets/fonts/SourceSerif4-It.ttf")
SERIF_SEMIBOLD :: #load("../../assets/fonts/SourceSerif4-Semibold.ttf")
SERIF_BOLD :: #load("../../assets/fonts/SourceSerif4-Bold.ttf")

register :: proc(ctx: ^vui.Context) {
	f := &ctx.fonts
	vui.font_register(f, "Inter", INTER_REGULAR, 400)
	vui.font_register(f, "Inter", INTER_THIN, 100)
	vui.font_register(f, "Inter", INTER_EXTRALIGHT, 200)
	vui.font_register(f, "Inter", INTER_LIGHT, 300)
	vui.font_register(f, "Inter", INTER_MEDIUM, 500)
	vui.font_register(f, "Inter", INTER_SEMIBOLD, 600)
	vui.font_register(f, "Inter", INTER_BOLD, 700)
	vui.font_register(f, "Inter", INTER_EXTRABOLD, 800)
	vui.font_register(f, "Inter", INTER_BLACK, 900)
	vui.font_register(f, "Inter", INTER_ITALIC, 400, true)
	vui.font_register(f, "Inter", INTER_MEDIUM_ITALIC, 500, true)
	vui.font_register(f, "Inter", INTER_SEMIBOLD_ITALIC, 600, true)
	vui.font_register(f, "Inter", INTER_BOLD_ITALIC, 700, true)
	vui.font_register(f, "IBM Plex Mono", PLEX_MONO_REGULAR, 400)
	vui.font_register(f, "IBM Plex Mono", PLEX_MONO_ITALIC, 400, true)
	vui.font_register(f, "IBM Plex Mono", PLEX_MONO_MEDIUM, 500)
	vui.font_register(f, "IBM Plex Mono", PLEX_MONO_SEMIBOLD, 600)
	vui.font_register(f, "IBM Plex Mono", PLEX_MONO_BOLD, 700)
	vui.font_register(f, "Source Serif 4", SERIF_REGULAR, 400)
	vui.font_register(f, "Source Serif 4", SERIF_ITALIC, 400, true)
	vui.font_register(f, "Source Serif 4", SERIF_SEMIBOLD, 600)
	vui.font_register(f, "Source Serif 4", SERIF_BOLD, 700)
}

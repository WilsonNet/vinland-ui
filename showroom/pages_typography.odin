package showroom

import "core:fmt"
import ui "../vui"

register_typography_examples :: proc() {
	EXAMPLES["font-family"] = ex_font_family
	EXAMPLES["font-size"] = ex_font_size
	EXAMPLES["font-style"] = ex_font_style
	EXAMPLES["font-weight"] = ex_font_weight
	EXAMPLES["font-variant-numeric"] = ex_font_variant
	EXAMPLES["letter-spacing"] = ex_tracking
	EXAMPLES["line-clamp"] = ex_line_clamp
	EXAMPLES["line-height"] = ex_leading
	EXAMPLES["list-style-type"] = ex_list_type
	EXAMPLES["list-style-position"] = ex_list_type
	EXAMPLES["text-align"] = ex_text_align
	EXAMPLES["color"] = ex_text_color
	EXAMPLES["text-decoration-line"] = ex_decoration_line
	EXAMPLES["text-decoration-color"] = ex_decoration_color
	EXAMPLES["text-decoration-style"] = ex_decoration_style
	EXAMPLES["text-decoration-thickness"] = ex_decoration_thickness
	EXAMPLES["text-underline-offset"] = ex_underline_offset
	EXAMPLES["text-transform"] = ex_text_transform
	EXAMPLES["text-overflow"] = ex_text_overflow
	EXAMPLES["text-wrap"] = ex_text_wrap
	EXAMPLES["text-indent"] = ex_text_indent
	EXAMPLES["white-space"] = ex_white_space
	EXAMPLES["word-break"] = ex_word_break
	EXAMPLES["overflow-wrap"] = ex_word_break
}

SAMPLE :: "The quick brown fox jumps over the lazy dog."
PROSE :: "So I started to walk into the water. I won't lie to you boys, I was terrified. But I pressed on, and as I made my way past the breakers a strange calm came over me."

specimen :: proc(label, class: string, text := SAMPLE, loc := #caller_location) {
	if ui.div("flex flex-col gap-1", loc = loc) {
		ui.text(label, "font-mono text-xs text-gray-500 dark:text-gray-400")
		ui.text(text, ui.cx("text-gray-950 dark:text-white", class))
	}
}

ex_font_family :: proc() {
	h3("Basic example")
	para("Use `font-sans`, `font-serif` and `font-mono`. Each is a token that maps to a registered family, so a theme can swap faces app-wide.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-6") {
			specimen("font-sans", "font-sans text-xl font-medium")
			specimen("font-serif", "font-serif text-xl font-medium")
			specimen("font-mono", "font-mono text-xl font-medium")
		}
	}
}

ex_font_size :: proc() {
	h3("Basic example")
	para("Use `text-sm`, `text-lg` and the rest of the scale. Each size carries a paired line height.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-6") {
			for c in ([]string{"text-sm", "text-base", "text-lg", "text-xl", "text-2xl", "text-4xl"}) {
				ui.key(c)
				specimen(c, ui.cx(c, "font-medium"))
			}
		}
	}
	h3("Setting the line height")
	para("Add a slash to set size and line height together: `text-sm/6`, `text-base/7`.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-6") {
			specimen("text-sm/6", "text-sm/6", PROSE)
			specimen("text-sm/7", "text-sm/7", PROSE)
			specimen("text-sm/8", "text-sm/8", PROSE)
		}
	}
}

ex_font_style :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-6") {
			specimen("italic", "italic text-lg font-medium")
			specimen("not-italic", "not-italic text-lg font-medium")
		}
	}
}

ex_font_weight :: proc() {
	h3("Basic example")
	para("Inter ships every weight from 100 to 900, so `font-thin` through `font-black` render with real faces, never synthesized bold.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"font-thin", "font-extralight", "font-light", "font-normal", "font-medium", "font-semibold", "font-bold", "font-extrabold", "font-black"}) {
				ui.key(c)
				specimen(c, ui.cx(c, "text-lg"))
			}
		}
	}
}

ex_font_variant :: proc() {
	h3("Tabular figures")
	para("Use `tabular-nums` so digits line up in columns. Inter's figures are already tabular, so the class is accepted for compatibility.")
	if example("p-8", false) {
		if ui.div("w-64 divide-y divide-gray-200 dark:divide-white/10") {
			for row in ([][2]string{{"Coffee", "$4.20"}, {"Croissant", "$11.95"}, {"Tea", "$3.05"}}) {
				ui.key(row[0])
				if ui.div("flex justify-between py-2 text-sm") {
					ui.text(row[0], "text-gray-600 dark:text-gray-400")
					ui.text(row[1], "font-medium tabular-nums text-gray-950 dark:text-white")
				}
			}
		}
	}
}

ex_tracking :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"tracking-tighter", "tracking-tight", "tracking-normal", "tracking-wide", "tracking-wider", "tracking-widest"}) {
				ui.key(c)
				specimen(c, ui.cx(c, "text-lg font-medium"))
			}
		}
	}
}

ex_line_clamp :: proc() {
	h3("Basic example")
	para("Use `line-clamp-<number>` to truncate text after a number of lines with an ellipsis.")
	if example("p-8", false) {
		if ui.div("max-w-sm") {
			ui.text("Boost your conversion rate", "text-lg font-semibold text-gray-950 dark:text-white")
			ui.text("Nulla dolor velit adipisicing duis excepteur esse in duis nostrud occaecat mollit incididunt deserunt sunt. Ut ut sunt laborum ex occaecat eu tempor labore enim adipisicing minim ad. Est in quis eu dolore occaecat excepteur fugiat dolore nisi aliqua fugiat enim ut cillum.", "mt-2 line-clamp-3 text-sm/6 text-gray-600 dark:text-gray-400")
		}
	}
}

ex_leading :: proc() {
	h3("Basic example")
	para("Use `leading-<number>` (spacing scale) or `leading-tight`/`leading-relaxed` to set line height.")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-6") {
			specimen("leading-6", "text-sm leading-6", PROSE)
			specimen("leading-7", "text-sm leading-7", PROSE)
			specimen("leading-loose", "text-sm leading-loose", PROSE)
		}
	}
}

ex_list_type :: proc() {
	h3("Basic example")
	para("Lists are plain elements; draw the markers yourself so they follow your design. Here a bullet and a number are separate leaves aligned with `items-baseline`.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-2 gap-8") {
			if ui.div("flex flex-col gap-2") {
				for item in ([]string{"Now this is a story", "All about how", "My life got flipped"}) {
					ui.key(item)
					if ui.div("flex items-baseline gap-3 text-sm text-gray-700 dark:text-gray-300") {
						ui.el("size-1.5 shrink-0 -translate-y-0.5 rounded-full bg-gray-400")
						ui.text(item)
					}
				}
			}
			if ui.div("flex flex-col gap-2") {
				for item, i in ([]string{"Now this is a story", "All about how", "My life got flipped"}) {
					ui.key(item)
					if ui.div("flex items-baseline gap-3 text-sm text-gray-700 dark:text-gray-300") {
						ui.text(fmt.tprintf("%d.", i + 1), "w-4 shrink-0 text-right font-medium text-gray-400 tabular-nums")
						ui.text(item)
					}
				}
			}
		}
	}
}

ex_text_align :: proc() {
	for c in ([]string{"text-left", "text-center", "text-right"}) {
		ui.key(c)
		h3(c)
		if example("p-8", false) {
			ui.text(PROSE, ui.cx("max-w-md text-sm/6 text-gray-700 dark:text-gray-300", c))
		}
	}
}

ex_text_color :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.p("max-w-md text-base/7 font-medium text-gray-950 dark:text-white") {
			ui.span("The quick brown fox ")
			ui.span("jumps over", "text-sky-500 dark:text-sky-400")
			ui.span(" the lazy dog.")
		}
	}
	h3("Changing the opacity")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-2") {
			for a in ([]string{"text-blue-600/100", "text-blue-600/75", "text-blue-600/50", "text-blue-600/25"}) {
				ui.key(a)
				ui.text(SAMPLE, ui.cx("text-base font-medium dark:text-blue-400", a))
			}
		}
	}
}

ex_decoration_line :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"underline", "overline", "line-through", "no-underline"}) {
				ui.key(c)
				specimen(c, ui.cx(c, "text-lg font-medium"))
			}
		}
	}
	h3("Applying on hover")
	if example("p-8", false) {
		if ui.p("text-base text-gray-700 dark:text-gray-300") {
			ui.span("The ")
			ui.span("quick brown fox", "font-semibold text-sky-600 underline decoration-sky-400/50 underline-offset-4")
			ui.span(" jumps over the lazy dog.")
		}
	}
}

ex_decoration_color :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.p("max-w-md text-base/8 text-gray-700 dark:text-gray-300") {
			ui.span("I'm Derek, an astro-engineer based in Tattooine. I like to build ")
			ui.span("X-Wings", "font-semibold text-gray-950 underline decoration-sky-500 dark:text-white")
			ui.span(" at ")
			ui.span("My Company, Inc", "font-semibold text-gray-950 underline decoration-pink-500 dark:text-white")
			ui.span(". Outside of work, I like to ")
			ui.span("watch pod-racing", "font-semibold text-gray-950 underline decoration-indigo-500 dark:text-white")
			ui.span(".")
		}
	}
}

ex_decoration_style :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"decoration-solid", "decoration-double", "decoration-dotted", "decoration-dashed", "decoration-wavy"}) {
				ui.key(c)
				specimen(c, ui.cx("text-lg font-medium underline decoration-sky-500 underline-offset-4", c))
			}
		}
	}
}

ex_decoration_thickness :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"decoration-1", "decoration-2", "decoration-4"}) {
				ui.key(c)
				specimen(c, ui.cx("text-lg font-medium underline decoration-sky-500 underline-offset-4", c))
			}
		}
	}
}

ex_underline_offset :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"underline-offset-1", "underline-offset-2", "underline-offset-4", "underline-offset-8"}) {
				ui.key(c)
				specimen(c, ui.cx("text-lg font-medium underline", c))
			}
		}
	}
}

ex_text_transform :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		if ui.div("flex flex-col gap-5") {
			for c in ([]string{"normal-case", "uppercase", "lowercase", "capitalize"}) {
				ui.key(c)
				specimen(c, ui.cx("text-lg font-medium", c))
			}
		}
	}
}

ex_text_overflow :: proc() {
	h3("Truncating text")
	para("Use `truncate` to keep text on one line and end it with an ellipsis.")
	if example("p-8", false) {
		if ui.div("w-64 rounded-lg bg-gray-50 p-4 dark:bg-white/5") {
			ui.text(PROSE, "truncate text-sm text-gray-700 dark:text-gray-300")
		}
	}
}

ex_text_wrap :: proc() {
	h3("Allowing text to wrap")
	if example("p-8", false) {
		if ui.div("w-72") {
			ui.text("Beloved Manhattan soup stand closes", "text-wrap text-2xl font-bold text-gray-950 dark:text-white")
		}
	}
	h3("Preventing text from wrapping")
	if example("p-8", false) {
		if ui.div("w-72 overflow-hidden") {
			ui.text("Beloved Manhattan soup stand closes", "text-nowrap text-2xl font-bold text-gray-950 dark:text-white")
		}
	}
}

ex_text_indent :: proc() {
	h3("Basic example")
	if example("p-8", false) {
		ui.text(PROSE, "max-w-md text-sm/6 text-gray-700 dark:text-gray-300")
	}
}

ex_white_space :: proc() {
	h3("Preserving whitespace")
	para("Use `whitespace-pre` to keep spaces and line breaks exactly as written; `whitespace-pre-line` keeps line breaks but collapses spaces.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-2 gap-6") {
			ui.text("Hey everyone!\n\nIt's almost 2022     and we still don't know if there is aliens living among us.", "whitespace-normal text-sm text-gray-700 dark:text-gray-300")
			ui.text("Hey everyone!\n\nIt's almost 2022     and we still don't know if there is aliens living among us.", "whitespace-pre-line text-sm text-gray-700 dark:text-gray-300")
		}
	}
}

ex_word_break :: proc() {
	h3("Breaking long words")
	para("Use `break-all` or `wrap-anywhere` to break words that would otherwise overflow.")
	if example("p-8", false) {
		if ui.div("grid grid-cols-2 gap-6") {
			if ui.div("w-40 rounded-lg bg-gray-50 p-3 dark:bg-white/5") {
				ui.text("Supercalifragilisticexpialidocious", "text-sm text-gray-700 dark:text-gray-300")
			}
			if ui.div("w-40 rounded-lg bg-gray-50 p-3 dark:bg-white/5") {
				ui.text("Supercalifragilisticexpialidocious", "break-all text-sm text-gray-700 dark:text-gray-300")
			}
		}
	}
}

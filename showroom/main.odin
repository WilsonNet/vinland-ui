// vinland-ui showroom: the framework's documentation, rendered by the framework itself.
// Native entry point (SDL3 window + control server). The website build is web_main.odin.
#+build !js
package showroom

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ui "../vui"
import "../vui/app"
import "../vui/fonts"
import icons "../vui/icons"
import "demos"

main :: proc() {
	ctx: ui.Context
	ui.init(&ctx)
	defer ui.destroy(&ctx)
	fonts.register(&ctx)
	IC = icons.register(&ctx)
	demos.IC = IC
	LOGO = ui.icon_register(&ctx, "vinland-logo", {32, 32}, LOGO_PATHS[:])
	GITHUB = ui.icon_register(&ctx, "github", {24, 24}, GITHUB_PATHS[:])
	theme_setup(&ctx.theme)

	register_pages()
	s.page = page_index("introduction")
	s.demo.slider = 40
	s.demo.radio = 1
	if len(os.args) > 1 {
		for a in os.args[1:] {
			if strings.has_prefix(a, "--page=") {
				if i := page_index(a[7:]); i >= 0 {
					s.page = i
				}
			}
			if a == "--dark" {
				s.theme_mode = 1
			}
		}
	}
	ui.set_dark(s.theme_mode == 1)

	a: app.App
	if !app.init(&a, {title = "vinland-ui", size = {1440, 900}, min_size = {360, 480}, control_port = 7420}, &ctx) {
		os.exit(1)
	}
	defer app.shutdown(&a)
	a.on_command = on_command

	for app.next_frame(&a) {
		frame()
		app.end_frame(&a)
	}
}

on_command :: proc(a: ^app.App, cmd: string, args: map[string]string) -> string {
	switch cmd {
	case "nav":
		slug := args["page"]
		i := page_index(slug)
		if i < 0 {
			return ""
		}
		navigate(i)
		return fmt.tprintf(`{{"ok":true,"page":"%s"}}`, PAGES[i].slug)
	case "pages":
		sb := strings.builder_make(context.temp_allocator)
		strings.write_string(&sb, `{"ok":true,"pages":[`)
		for p, i in PAGES {
			if i > 0 {
				strings.write_string(&sb, ",")
			}
			fmt.sbprintf(&sb, `{{"slug":"%s","title":"%s","group":"%s"}}`, p.slug, p.title, p.group)
		}
		strings.write_string(&sb, "]}")
		return strings.to_string(sb)
	case "search":
		s.search_open = args["open"] != "false"
		clear(&s.search_query)
		append(&s.search_query, args["q"])
		return `{"ok":true}`
	case "sidebar":
		s.sidebar_open = args["open"] != "false"
		return `{"ok":true}`
	case "export":
		return export_page()
	case "scroll_content":
		y, _ := strconv.parse_f32(args["y"])
		ui.scroll_to(s.scroll_id, y)
		if st, ok := ui.ctx_get().states[s.scroll_id]; ok {
			st.scroll.y = clamp(y, 0, st.scroll_max.y)
			st.scroll_target.y = st.scroll.y
		}
		return `{"ok":true}`
	case "anchor":
		s.pending_anchor = strings.clone(args["id"])
		return `{"ok":true}`
	}
	return ""
}

navigate :: proc(i: int) {
	if i < 0 || i >= len(PAGES) {
		return
	}
	s.page = i
	s.sidebar_open = false
	s.search_open = false
	s.nav_count += 1
	if s.scroll_id != 0 {
		ui.scroll_to(s.scroll_id, 0)
		if st, ok := ui.ctx_get().states[s.scroll_id]; ok {
			st.scroll = {}
			st.scroll_target = {}
		}
	}
}

// JSON description of the page rendered last frame (structure + example rects).
export_page :: proc() -> string {
	sb := strings.builder_make(context.temp_allocator)
	p := PAGES[s.page]
	strings.write_string(&sb, `{"ok":true,"slug":`)
	ui.json_str(&sb, p.slug)
	strings.write_string(&sb, `,"title":`)
	ui.json_str(&sb, p.title)
	strings.write_string(&sb, `,"group":`)
	ui.json_str(&sb, p.group)
	strings.write_string(&sb, `,"desc":`)
	ui.json_str(&sb, p.desc)
	cont := ui.rect_of(s.scroll_id)
	fmt.sbprintf(&sb, `,"content_bottom":%.1f,"blocks":[`, cont.y + ui.ctx_get().states[s.scroll_id].scroll_max.y + cont.h)
	for b, i in doc {
		if i > 0 {
			strings.write_string(&sb, ",")
		}
		fmt.sbprintf(&sb, `{{"kind":"%v"`, b.kind)
		if b.text != "" {
			strings.write_string(&sb, `,"text":`)
			ui.json_str(&sb, b.text)
		}
		if b.code != "" {
			strings.write_string(&sb, `,"code":`)
			ui.json_str(&sb, b.code)
		}
		if b.lang != "" && b.lang != "odin" {
			strings.write_string(&sb, `,"lang":`)
			ui.json_str(&sb, b.lang)
		}
		if b.kind == .Table {
			strings.write_string(&sb, `,"rows":[`)
			for r, j in b.rows {
				if j > 0 {
					strings.write_string(&sb, ",")
				}
				strings.write_string(&sb, "[")
				ui.json_str(&sb, r.class)
				strings.write_string(&sb, ",")
				ui.json_str(&sb, r.style)
				strings.write_string(&sb, "]")
			}
			strings.write_string(&sb, "]")
		}
		if b.kind == .Example {
			r := ui.rect_of(b.id)
			fmt.sbprintf(&sb, `,"rect":[%.2f,%.2f,%.2f,%.2f]`, r.x, r.y, r.w, r.h)
		}
		strings.write_string(&sb, "}")
	}
	strings.write_string(&sb, "]}")
	return strings.to_string(sb)
}

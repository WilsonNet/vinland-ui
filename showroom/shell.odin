package showroom

import "core:fmt"
import "core:strings"
import ui "../vui"

frame :: proc() {
	ctx := ui.ctx_get()
	in_ := ctx.input
	ctrl := .Ctrl in in_.mods || .Super in in_.mods
	if ctrl && .K in in_.keys_pressed {
		s.search_open = !s.search_open
		clear(&s.search_query)
		s.search_sel = 0
	}
	if .Escape in in_.keys_pressed {
		s.search_open = false
		s.sidebar_open = false
	}
	clear(&toc)

	if ui.div("flex h-full flex-col bg-canvas font-sans text-ink antialiased selection:bg-accent-soft") {
		topbar()
		if ui.div("flex min-h-0 flex-1") {
			if ui.div("hidden w-72 shrink-0 lg:flex lg:flex-col") {
				sidebar_nav()
			}
			ui.el("hidden w-10 shrink-0 border-x border-rule bg-stripes stripes-hatch lg:block")
			content()
			ui.el("hidden w-10 shrink-0 border-l border-rule bg-stripes stripes-hatch 2xl:block")
		}
	}
	if s.sidebar_open {
		mobile_drawer()
	}
	if s.search_open {
		search_palette()
	}
}

// ---------------------------------------------------------------------------

topbar :: proc() {
	if ui.div("relative z-10 flex h-14 shrink-0 items-center gap-4 border-b border-rule bg-canvas px-4 sm:px-6") {
		if ui.button_box("-ml-1 rounded-md p-1.5 text-ink-muted hover:bg-gray-950/5 lg:hidden dark:hover:bg-white/10") {
			ui.icon(IC.bars_3, "size-5")
			if ui.clicked() {
				s.sidebar_open = true
			}
		}
		if ui.button_box("flex items-center gap-2.5 rounded-md") {
			if ui.div("flex size-7 items-center justify-center rounded-lg bg-accent shadow-sm") {
				ui.icon(LOGO, "size-5 text-white dark:text-gray-950")
			}
			ui.text("vinland-ui", "text-[17px] font-semibold tracking-tight text-ink")
			if ui.clicked() {
				navigate(page_index("introduction"))
			}
		}
		ui.text("v" + VERSION, "rounded-full bg-gray-950/5 px-2 py-0.5 font-mono text-xs font-medium text-ink-muted dark:bg-white/10")
		ui.el("flex-1")
		if ui.button_box("hidden items-center gap-2 rounded-full py-1 pr-2 pl-2.5 text-ink-soft inset-ring inset-ring-gray-950/10 transition-colors hover:inset-ring-gray-950/20 sm:flex dark:inset-ring-white/10 dark:hover:inset-ring-white/20") {
			ui.icon(IC.magnifying_glass, "size-3.5")
			ui.text("Search docs", "text-[13px] text-ink-soft")
			ui.text("Ctrl K", "ml-6 rounded-sm bg-gray-950/5 px-1.5 font-mono text-[11px] font-medium text-ink-soft dark:bg-white/10")
			if ui.clicked() {
				s.search_open = true
				clear(&s.search_query)
			}
		}
		if ui.div("hidden items-center gap-6 md:flex") {
			nav_link("Docs", "introduction")
			nav_link("Tokens", "theme-tokens")
			nav_link("Components", "showcase")
		}
		if ui.button_box("rounded-md p-1.5 text-ink-muted transition-colors hover:bg-gray-950/5 hover:text-ink dark:hover:bg-white/10") {
			ui.icon(ui.is_dark() ? IC.sun : IC.moon, "size-5")
			if ui.clicked() {
				ui.set_dark(!ui.is_dark())
			}
		}
		ui.icon(GITHUB, "hidden size-5 text-ink-muted sm:block")
	}
}

nav_link :: proc(label, slug: string, loc := #caller_location) {
	active := PAGES[s.page].slug == slug
	if ui.button(label, active ? "text-sm font-medium text-ink" : "text-sm text-ink-muted transition-colors hover:text-ink", loc = loc) {
		navigate(page_index(slug))
	}
}

sidebar_nav :: proc() {
	if ui.div("min-h-0 flex-1 overflow-y-auto px-6 pt-8 pb-16") {
		for g, gi in GROUPS {
			ui.push_id(g)
			ui.text(g, gi == 0 ? "font-mono text-xs/6 font-medium tracking-widest text-ink-soft uppercase" : "mt-8 font-mono text-xs/6 font-medium tracking-widest text-ink-soft uppercase")
			if ui.div("mt-3 flex flex-col border-l border-rule-strong") {
				for p, i in PAGES {
					if p.group != g {
						continue
					}
					ui.key(p.slug)
					active := i == s.page
					cls := active ? "-ml-px border-l border-accent pl-4 py-1 text-sm/6 font-semibold text-accent" : "-ml-px border-l border-transparent pl-4 py-1 text-sm/6 text-ink-muted transition-colors hover:border-gray-950/25 hover:text-ink dark:hover:border-white/25"
					if ui.button(p.title, cls) {
						navigate(i)
					}
				}
			}
			ui.pop_id()
		}
	}
}

content :: proc() {
	if ui.div("relative flex min-w-0 flex-1") {
		if ui.div("min-w-0 flex-1 overflow-y-auto") {
			s.scroll_id = ui.current_id()
			if ui.div("mx-auto w-full max-w-2xl px-4 pt-10 pb-24 sm:px-6 lg:pt-14") {
				p := &PAGES[s.page]
				ui.key(p.slug)
				ui.text(p.title, "text-3xl font-medium tracking-tight text-ink")
				if p.desc != "" {
					para(p.desc, "mt-4 text-base/7")
				}
				ui.push_id(p.slug)
				if p.render != nil {
					p.render()
				} else if p.ref >= 0 {
					ref_page_render()
				}
				ui.pop_id()
				page_footer()
			}
		}
		if ui.div("hidden w-72 shrink-0 overflow-y-auto px-8 pt-14 pb-10 xl:block") {
			toc_panel()
		}
	}
	// anchor scroll requests (from TOC clicks or the CLI)
	if s.pending_anchor != "" {
		for e in toc {
			if e.title == s.pending_anchor || strings.to_lower(e.title, context.temp_allocator) == strings.to_lower(s.pending_anchor, context.temp_allocator) {
				scroll_to_entry(e)
			}
		}
		delete(s.pending_anchor)
		s.pending_anchor = ""
	}
}

scroll_to_entry :: proc(e: Toc_Entry) {
	cont := ui.rect_of(s.scroll_id)
	hr := ui.rect_of(e.id)
	cur := ui.scroll_of(s.scroll_id)
	ui.scroll_to(s.scroll_id, hr.y - cont.y + cur.y - 32)
}

toc_panel :: proc() {
	if len(toc) == 0 {
		return
	}
	ui.text("On this page", "font-mono text-xs/6 font-medium tracking-widest text-ink-soft uppercase")
	cont := ui.rect_of(s.scroll_id)
	active := 0
	for e, i in toc {
		r := ui.rect_of(e.id)
		if r.h > 0 && r.y - cont.y < 120 {
			active = i
		}
	}
	if ui.div("mt-3 flex flex-col border-l border-rule-strong") {
		for e, i in toc {
			ui.key(fmt.tprintf("%s-%d", e.title, i))
			pad := e.level == 2 ? "pl-4" : "pl-7"
			cls := i == active ? ui.cx("-ml-px border-l border-ink py-1 text-sm/6 font-medium text-ink", pad) : ui.cx("-ml-px border-l border-transparent py-1 text-sm/6 text-ink-muted transition-colors hover:text-ink", pad)
			if ui.button(e.title, cls) {
				scroll_to_entry(e)
			}
		}
	}
}

page_footer :: proc() {
	if ui.div("mt-20 flex items-center justify-between gap-4 border-t border-rule pt-8") {
		if s.page > 0 {
			prev := PAGES[s.page - 1]
			if ui.button_box("group flex items-center gap-2 text-sm text-ink-muted hover:text-ink") {
				ui.icon(IC.arrow_left, "size-4 text-ink-soft transition-transform group-hover:-translate-x-0.5")
				ui.text(prev.title, "font-medium")
				if ui.clicked() {
					navigate(s.page - 1)
				}
			}
		} else {
			ui.el()
		}
		if s.page < len(PAGES) - 1 {
			next := PAGES[s.page + 1]
			if ui.button_box("group flex items-center gap-2 text-sm text-ink-muted hover:text-ink") {
				ui.text(next.title, "font-medium")
				ui.icon(IC.arrow_right, "size-4 text-ink-soft transition-transform group-hover:translate-x-0.5")
				if ui.clicked() {
					navigate(s.page + 1)
				}
			}
		}
	}
}

mobile_drawer :: proc() {
	if ui.div("fixed inset-0 z-40 flex") {
		if ui.pressable("absolute inset-0 bg-gray-950/30 dark:bg-black/60") {
			if ui.clicked() {
				s.sidebar_open = false
			}
		}
		if ui.div("relative flex w-80 max-w-[85%] flex-col bg-canvas shadow-2xl ring-1 ring-rule") {
			if ui.div("flex h-14 shrink-0 items-center justify-between border-b border-rule px-6") {
				ui.text("Navigation", "text-sm font-semibold text-ink")
				if ui.button_box("rounded-md p-1.5 text-ink-muted hover:bg-gray-950/5 dark:hover:bg-white/10") {
					ui.icon(IC.x_mark, "size-5")
					if ui.clicked() {
						s.sidebar_open = false
					}
				}
			}
			sidebar_nav()
		}
	}
}

search_palette :: proc() {
	ctx := ui.ctx_get()
	q := strings.to_lower(string(s.search_query[:]), context.temp_allocator)
	results := make([dynamic]int, context.temp_allocator)
	for p, i in PAGES {
		if q == "" || strings.contains(strings.to_lower(p.title, context.temp_allocator), q) || strings.contains(strings.to_lower(p.group, context.temp_allocator), q) || strings.contains(p.slug, q) {
			append(&results, i)
		}
	}
	if len(results) > 0 {
		s.search_sel = clamp(s.search_sel, 0, len(results) - 1)
	}
	if .Down in ctx.input.keys_pressed {
		s.search_sel = min(s.search_sel + 1, max(len(results) - 1, 0))
	}
	if .Up in ctx.input.keys_pressed {
		s.search_sel = max(s.search_sel - 1, 0)
	}
	if ui.div("fixed inset-0 z-50 flex flex-col items-center px-4 pt-24") {
		if ui.pressable("absolute inset-0 bg-gray-950/25 dark:bg-black/60") {
			if ui.clicked() {
				s.search_open = false
			}
		}
		if ui.div("relative flex max-h-[70vh] w-full max-w-xl flex-col overflow-hidden rounded-xl bg-white shadow-2xl ring-1 ring-gray-950/10 dark:bg-gray-900 dark:ring-white/10") {
			if ui.div("flex items-center gap-3 border-b border-rule px-4") {
				ui.icon(IC.magnifying_glass, "size-5 text-ink-soft")
				res := ui.text_input(&s.search_query, "h-12 flex-1 text-base text-ink caret-accent placeholder:text-gray-400 selection:bg-accent-soft", "Search utilities and guides…")
				input_id := ui.last().id
				if !ui.ctx_get().states[input_id].focused {
					ui.focus(input_id)
				}
				if res.changed {
					s.search_sel = 0
				}
				if res.submitted && len(results) > 0 {
					navigate(results[s.search_sel])
				}
				ui.text("Esc", "rounded-sm bg-gray-950/5 px-1.5 font-mono text-[11px] font-medium text-ink-soft dark:bg-white/10")
			}
			if ui.div("min-h-0 flex-1 overflow-y-auto p-2") {
				if len(results) == 0 {
					ui.text("No pages match. Try a utility name like padding or shadow.", "px-3 py-8 text-center text-sm text-ink-muted")
				}
				for i, k in results {
					if k >= 60 {
						break
					}
					p := PAGES[i]
					ui.key(p.slug)
					sel := k == s.search_sel
					if ui.button_box(sel ? "flex items-center justify-between rounded-lg bg-accent-soft px-3 py-2" : "flex items-center justify-between rounded-lg px-3 py-2 hover:bg-gray-950/5 dark:hover:bg-white/5") {
						ui.text(p.title, sel ? "text-sm font-medium text-accent" : "text-sm text-ink")
						ui.text(p.group, "font-mono text-[11px] tracking-wider text-ink-soft uppercase")
						if ui.clicked() {
							navigate(i)
						}
					}
				}
			}
		}
	}
}

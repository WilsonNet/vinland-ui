package showroom

import "core:fmt"
import "core:strings"
import "base:runtime"
import ui "../vui"

LOGO_PATHS := [?]ui.Icon_Path {
	{d = "M7 7h5.2l3.8 9.6L19.8 7H25l-7 17h-4L7 7Z"},
	{d = "M5 26.5c2 0 2.5-1.5 5.5-1.5s3.5 1.5 5.5 1.5 2.5-1.5 5.5-1.5 3.5 1.5 5.5 1.5V28c-2 0-2.5-1.5-5.5-1.5S18 28 16 28s-2.5-1.5-5.5-1.5S7 28 5 28v-1.5Z"},
}

GITHUB_PATHS := [?]ui.Icon_Path {
	{d = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"},
}

// ---------------------------------------------------------------------------
// Page registry
// ---------------------------------------------------------------------------

Page :: struct {
	group:  string,
	slug:   string,
	title:  string,
	desc:   string,
	render: proc(),
	ref:    int, // index into REF_PAGES (-1 = hand-written page)
}

// Live examples for reference pages, keyed by slug.
EXAMPLES: map[string]proc()

PAGES: [dynamic]Page
GROUPS: [dynamic]string

page :: proc(group, slug, title, desc: string, render: proc(), ref := -1) {
	append(&PAGES, Page{group, slug, title, desc, render, ref})
	found := false
	for g in GROUPS {
		if g == group {
			found = true
		}
	}
	if !found {
		append(&GROUPS, group)
	}
}

page_index :: proc(slug: string) -> int {
	for p, i in PAGES {
		if p.slug == slug {
			return i
		}
	}
	return -1
}

// ---------------------------------------------------------------------------
// Table of contents (collected while a page renders)
// ---------------------------------------------------------------------------

Toc_Entry :: struct {
	title: string,
	level: int,
	id:    ui.Id,
}

toc: [dynamic]Toc_Entry

// Document structure of the current page, recorded while it renders (used by the static
// website exporter through the `export` control command).
Doc_Kind :: enum u8 {
	H2,
	H3,
	Para,
	Code,
	Example,
	Table,
	Note,
}

Doc_Block :: struct {
	kind:  Doc_Kind,
	text:  string, // heading / paragraph / note text (with `inline code` backticks)
	code:  string,
	lang:  string, // code block language for the website (default odin)
	rows:  []Row,
	id:    ui.Id, // example preview element
}

doc: [dynamic]Doc_Block

// Section heading (h2): large gap above, entry in "On this page".
h2 :: proc(title: string, loc := #caller_location) {
	ui.key(title)
	ui.text(title, "mt-16 text-xl font-semibold tracking-tight text-ink", loc = loc)
	append(&toc, Toc_Entry{title, 2, ui.last().id})
	append(&doc, Doc_Block{kind = .H2, text = title})
}

// Example heading (h3).
h3 :: proc(title: string, loc := #caller_location) {
	ui.key(title)
	ui.text(title, "mt-10 text-base font-semibold text-ink", loc = loc)
	append(&toc, Toc_Entry{title, 3, ui.last().id})
	append(&doc, Doc_Block{kind = .H3, text = title})
}

// Paragraph with `inline code` support.
para :: proc(text: string, class := "mt-4", loc := #caller_location) {
	append(&doc, Doc_Block{kind = .Para, text = text})
	if ui.p(ui.cx("text-base/7 text-ink-muted", class), loc = loc) {
		rich(text)
	}
}

rich :: proc(text: string) {
	rest := text
	in_code := false
	for len(rest) > 0 {
		i := strings.index_byte(rest, '`')
		seg := rest
		if i >= 0 {
			seg = rest[:i]
		}
		if len(seg) > 0 {
			if in_code {
				ui.span(seg, "font-mono text-[0.875em] font-medium text-ink")
			} else {
				ui.span(seg)
			}
		}
		if i < 0 {
			break
		}
		rest = rest[i + 1:]
		in_code = !in_code
	}
}

// ---------------------------------------------------------------------------
// Quick reference table
// ---------------------------------------------------------------------------

Row :: struct {
	class: string,
	style: string,
}

ref_table :: proc(rows: []Row, loc := #caller_location) {
	{
		cp := make([]Row, len(rows), ui.ctx_get().frame_alloc)
		copy(cp, rows)
		append(&doc, Doc_Block{kind = .Table, rows = cp})
	}
	if ui.div("mt-10", loc = loc) {
		if ui.div("grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] border-b border-rule") {
			ui.text("Class", "py-2.5 pr-4 pl-2 text-sm font-semibold text-ink")
			ui.text("Effect", "py-2.5 px-2 text-sm font-semibold text-ink")
		}
		limit := len(rows)
		collapsed := len(rows) > 12 && !expanded_table()
		if collapsed {
			limit = 10
		}
		if ui.div("relative") {
			for r in rows[:limit] {
				ui.key(r.class)
				if ui.div("grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] border-b border-rule") {
					ui.text(r.class, "py-2.5 pr-4 pl-2 font-mono text-xs/6 text-violet-600 dark:text-violet-400")
					ui.text(r.style, "py-2.5 px-2 font-mono text-xs/6 text-sky-700 dark:text-sky-300")
				}
			}
			if collapsed {
				ui.el("pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-linear-to-t from-canvas to-transparent")
				if ui.div("absolute inset-x-0 bottom-0 flex justify-center") {
					if ui.button(fmt.tprintf("Show all %d", len(rows)), "translate-y-1/2 rounded-full bg-gray-950 px-4 py-2 font-mono text-xs font-medium tracking-widest text-white uppercase shadow-lg transition hover:bg-gray-800 dark:bg-gray-700 dark:hover:bg-gray-600") {
						expand_table()
					}
				}
			}
		}
	}
}

@(private = "file")
expanded: map[string]bool

@(private = "file")
expanded_table :: proc() -> bool {
	return expanded[PAGES[s.page].slug]
}

@(private = "file")
expand_table :: proc() {
	expanded[PAGES[s.page].slug] = true
}

// Generates rows like `p-4 → padding: 16px` over the spacing scale.
spacing_rows :: proc(prefix: string, effect: string, extra: []Row = nil) -> []Row {
	rows := make([dynamic]Row, context.temp_allocator)
	steps := [?]f32{0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64, 96}
	append(&rows, Row{fmt.tprintf("%s-<number>", prefix), fmt.tprintf("%s: <number> × 4px", effect)})
	append(&rows, Row{fmt.tprintf("%s-px", prefix), fmt.tprintf("%s: 1px", effect)})
	for st in steps {
		append(&rows, Row{fmt.tprintf("%s-%v", prefix, st), fmt.tprintf("%s: %vpx", effect, st * 4)})
	}
	append(&rows, Row{fmt.tprintf("%s-[<value>]", prefix), fmt.tprintf("%s: <value>", effect)})
	for r in extra {
		append(&rows, r)
	}
	return rows[:]
}

// ---------------------------------------------------------------------------
// Live examples
// ---------------------------------------------------------------------------

Example_Frame :: struct {
	loc:     runtime.Source_Code_Location,
	center:  bool,
}

@(private = "file")
ex_stack: [dynamic]Example_Frame

// Live example: renders its body in a preview well, followed by the body's own source.
//     if example() { ...ui code... }
@(deferred_none = example_end)
example :: proc(class := "p-8", center := true, loc := #caller_location) -> bool {
	append(&ex_stack, Example_Frame{loc = loc, center = center})
	ui.push_id(int(loc.line))
	ui.open("mt-6 flex flex-col gap-1 rounded-xl bg-gray-950/5 p-1 inset-ring inset-ring-gray-950/5 dark:bg-white/10 dark:inset-ring-white/10")
	ui.open("relative overflow-hidden rounded-lg bg-white dark:bg-gray-950/80")
	append(&doc, Doc_Block{kind = .Example, id = ui.current_id(), code = snippet_for(loc)})
	ui.open(ui.cx(center ? "flex flex-col items-center" : "", class))
	return true
}

example_end :: proc() {
	f := pop(&ex_stack)
	ui.close() // content
	ui.close() // preview
	code_panel(snippet_for(f.loc))
	ui.close() // figure
	ui.pop_id()
}

// Static code block (no preview).
code :: proc(src: string, lang := "odin") {
	append(&doc, Doc_Block{kind = .Code, code = src, lang = lang})
	if ui.div("mt-6 rounded-xl bg-gray-950/5 p-1 inset-ring inset-ring-gray-950/5 dark:bg-white/10 dark:inset-ring-white/10") {
		code_panel(src)
	}
}

code_panel :: proc(src: string) {
	if ui.div("group relative overflow-x-auto rounded-lg bg-gray-950 py-4 dark:bg-white/5 dark:inset-ring dark:inset-ring-white/5") {
		if ui.div("min-w-max px-5") {
			lines := strings.split_lines(src, context.temp_allocator)
			for line, i in lines {
				if i == len(lines) - 1 && line == "" {
					break
				}
				ui.push_id(i)
				highlight_line(line)
				ui.pop_id()
			}
		}
		if ui.button_box("absolute top-2 right-2 rounded-md p-1.5 text-gray-500 opacity-0 transition group-hover:opacity-100 hover:bg-white/10 hover:text-gray-300") {
			ui.icon(IC.document_duplicate, "size-4")
			if ui.clicked() {
				ctx := ui.ctx_get()
				if ctx.clipboard_set != nil {
					ctx.clipboard_set(src)
				}
			}
		}
	}
}

// Swatch-like helpers used by many examples ------------------------------

// A labelled box in the Tailwind docs style (violet, mono label).
tile :: proc(label: string, class := "", loc := #caller_location) {
	ui.text(label, ui.cx("flex items-center justify-center rounded-lg bg-violet-500 p-4 font-mono text-sm font-bold text-white shadow-lg", class), loc = loc)
}

note :: proc(text: string, loc := #caller_location) {
	append(&doc, Doc_Block{kind = .Note, text = text})
	if ui.div("mt-6 flex gap-3 rounded-lg bg-accent-soft px-4 py-3", loc = loc) {
		ui.icon(IC.information_circle, "mt-0.5 size-5 shrink-0 text-accent")
		if ui.p("text-sm/6 text-ink-muted") {
			rich(text)
		}
	}
}

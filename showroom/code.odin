package showroom

import "base:runtime"
import "core:strings"
import ui "../vui"

// The showroom shows the real source of every example: page files are embedded at
// compile time and the body of each `if example() { ... }` block is cut out by line.

Src :: struct {
	name: string,
	text: string,
}

SOURCES := [?]Src {
	{"pages_intro.odin", #load("pages_intro.odin", string)},
	{"pages_layout.odin", #load("pages_layout.odin", string)},
	{"pages_flex.odin", #load("pages_flex.odin", string)},
	{"pages_spacing.odin", #load("pages_spacing.odin", string)},
	{"pages_typography.odin", #load("pages_typography.odin", string)},
	{"pages_visual.odin", #load("pages_visual.odin", string)},
	{"pages_motion.odin", #load("pages_motion.odin", string)},
	{"pages_interactivity.odin", #load("pages_interactivity.odin", string)},
	{"pages_canvas.odin", #load("pages_canvas.odin", string)},
	{"demos.odin", #load("demos/demos.odin", string)},
}

@(private = "file")
snippet_cache: map[string]string

snippet_for :: proc(loc: runtime.Source_Code_Location) -> string {
	path := loc.file_path
	base := path
	if i := strings.last_index_byte(path, '/'); i >= 0 {
		base = path[i + 1:]
	}
	key := strings.concatenate({base, ":", int_str(int(loc.line))}, context.temp_allocator)
	if v, ok := snippet_cache[key]; ok {
		return v
	}
	text := ""
	for src in SOURCES {
		if src.name == base {
			text = src.text
		}
	}
	lines := strings.split_lines(text, context.temp_allocator)
	start := int(loc.line) - 1
	out := strings.builder_make()
	if start >= 0 && start < len(lines) {
		head := lines[start]
		indent := 0
		for indent < len(head) && head[indent] == '\t' {
			indent += 1
		}
		closing := strings.concatenate({head[:indent], "}"}, context.temp_allocator)
		first := true
		for li in start + 1 ..< len(lines) {
			l := lines[li]
			if l == closing {
				break
			}
			// dedent one level deeper than the `if example()` line
			k := 0
			for k < indent + 1 && k < len(l) && l[k] == '\t' {
				k += 1
			}
			body := l[k:]
			if !first {
				strings.write_byte(&out, '\n')
			}
			first = false
			for c in body {
				if c == '\t' {
					strings.write_string(&out, "    ")
				} else {
					strings.write_rune(&out, c)
				}
			}
		}
	}
	res := strings.to_string(out)
	// `demos.name()` bodies point at a shared component: show the component's source instead
	if strings.has_prefix(res, "demos.") && strings.has_suffix(res, "()") && !strings.contains(res, "\n") {
		if body, ok := proc_body("demos.odin", res[6:len(res) - 2]); ok {
			res = body
		}
	}
	snippet_cache[strings.clone(key)] = res
	return res
}

@(private = "file")
int_str :: proc(n: int) -> string {
	buf: [32]u8
	i := len(buf)
	v := n
	if v == 0 {
		return "0"
	}
	for v > 0 {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
	}
	return strings.clone(string(buf[i:]), context.temp_allocator)
}

KEYWORDS := [?]string{"if", "else", "for", "in", "proc", "return", "switch", "case", "defer", "when", "struct", "enum", "union", "import", "package", "true", "false", "nil", "do", "not_in", "break", "continue", "using", "map", "dynamic"}

@(private = "file")
is_ident :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

// Renders one line of Odin source as colored spans.
highlight_line :: proc(line: string) {
	if ui.p("font-mono text-[13px]/6 whitespace-pre text-gray-300") {
		if len(line) == 0 {
			ui.span(" ")
		}
		i := 0
		for i < len(line) {
			c := line[i]
			switch {
			case c == '/' && i + 1 < len(line) && line[i + 1] == '/':
				ui.span(line[i:], "text-gray-500 italic")
				i = len(line)
			case c == '"' || c == '`':
				j := i + 1
				for j < len(line) && line[j] != c {
					if line[j] == '\\' && c == '"' {
						j += 1
					}
					j += 1
				}
				j = min(j + 1, len(line))
				ui.span(line[i:j], "text-sky-300")
				i = j
			case c >= '0' && c <= '9':
				j := i
				for j < len(line) && (is_ident(line[j]) || line[j] == '.') {
					j += 1
				}
				ui.span(line[i:j], "text-violet-300")
				i = j
			case is_ident(c):
				j := i
				for j < len(line) && is_ident(line[j]) {
					j += 1
				}
				word := line[i:j]
				kw := false
				for k in KEYWORDS {
					if k == word {
						kw = true
					}
				}
				if kw {
					ui.span(word, "text-pink-400")
				} else if j < len(line) && line[j] == '.' {
					ui.span(word, "text-gray-400")
				} else if j < len(line) && line[j] == '(' {
					ui.span(word, "text-white")
				} else if word[0] >= 'A' && word[0] <= 'Z' {
					ui.span(word, "text-amber-200")
				} else {
					ui.span(word, "text-gray-300")
				}
				i = j
			case:
				j := i
				for j < len(line) && !is_ident(line[j]) && line[j] != '"' && line[j] != '`' && !(line[j] == '/' && j + 1 < len(line) && line[j + 1] == '/') {
					j += 1
				}
				if j == i {
					j = i + 1
				}
				ui.span(line[i:j], "text-gray-500")
				i = j
			}
		}
	}
}

// Body of a top-level `name :: proc() {` in an embedded source file, dedented once.
proc_body :: proc(file, name: string) -> (string, bool) {
	text := ""
	for src in SOURCES {
		if src.name == file {
			text = src.text
		}
	}
	head := strings.concatenate({name, " :: proc() {"}, context.temp_allocator)
	lines := strings.split_lines(text, context.temp_allocator)
	out := strings.builder_make()
	for l, i in lines {
		if l != head {
			continue
		}
		first := true
		for j in i + 1 ..< len(lines) {
			b := lines[j]
			if b == "}" {
				return strings.to_string(out), true
			}
			if !first {
				strings.write_byte(&out, '\n')
			}
			first = false
			body := strings.trim_prefix(b, "\t")
			for c in body {
				if c == '\t' {
					strings.write_string(&out, "    ")
				} else {
					strings.write_rune(&out, c)
				}
			}
		}
	}
	return "", false
}

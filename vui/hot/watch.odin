package vui_hot

import "base:runtime"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

// ---------------------------------------------------------------------------
// Source watcher
// ---------------------------------------------------------------------------
//
// Polling, not inotify/FSEvents/ReadDirectoryChanges: one code path on every OS, no watch
// limits, and it naturally coalesces the several events an editor's atomic save (write temp,
// rename over, chmod) produces. A scan is one directory listing per watched package; stat
// changes are confirmed with a content hash, so `touch`, a save without edits or a branch switch
// that restores the same bytes never trigger a rebuild. See tools/vui-hot/BENCHMARKS.md.

File_Stamp :: struct {
	size:  i64,
	mtime: i64,
	hash:  u64,
}

Watcher :: struct {
	allocator:   runtime.Allocator,
	roots:       [dynamic]string, // package dirs the app is built from (scanned for imports)
	extra:       [dynamic]string, // explicit --watch dirs/files
	dirs:        [dynamic]string, // every watched package dir (roots + local imports)
	assets:      [dynamic]string, // files pulled in with #load / #load_directory
	collections: map[string]string, // name -> absolute dir (user + vinland)
	files:       map[string]File_Stamp,
	imports:     map[string][]string, // source file -> local package dirs / assets it references
	dir_mtimes:  map[string]i64, // last seen mtime of each watched directory
	scans:       int,
}

SKIP_COLLECTIONS :: [?]string{"core", "base", "vendor", "shared"}

watcher_init :: proc(w: ^Watcher, roots: []string, collections: map[string]string, extra: []string = nil, allocator := context.allocator) {
	w^ = {}
	w.allocator = allocator
	w.roots.allocator = allocator
	w.extra.allocator = allocator
	w.dirs.allocator = allocator
	w.assets.allocator = allocator
	w.collections = make(map[string]string, allocator)
	w.files = make(map[string]File_Stamp, allocator)
	w.imports = make(map[string][]string, allocator)
	w.dir_mtimes = make(map[string]i64, allocator)
	for r in roots {
		append(&w.roots, clean_abs(r, allocator))
	}
	for e in extra {
		append(&w.extra, clean_abs(e, allocator))
	}
	for k, v in collections {
		w.collections[strings.clone(k, allocator)] = clean_abs(v, allocator)
	}
	watcher_resolve(w)
	_ = watcher_scan(w, context.temp_allocator) // baseline
}

watcher_destroy :: proc(w: ^Watcher) {
	a := w.allocator
	for s in w.roots {delete(s, a)}
	for s in w.extra {delete(s, a)}
	for s in w.dirs {delete(s, a)}
	for s in w.assets {delete(s, a)}
	for k, v in w.collections {
		delete(k, a)
		delete(v, a)
	}
	for k in w.files {delete(k, a)}
	for k, v in w.imports {
		delete(k, a)
		for s in v {delete(s, a)}
		delete(v, a)
	}
	delete(w.roots)
	delete(w.extra)
	delete(w.dirs)
	delete(w.assets)
	delete(w.collections)
	delete(w.files)
	delete(w.imports)
	for k in w.dir_mtimes {delete(k, a)}
	delete(w.dir_mtimes)
}

clean_abs :: proc(p: string, allocator := context.allocator) -> string {
	abs, err := os.get_absolute_path(p, context.temp_allocator)
	if err != nil {
		abs = p
	}
	c, _ := filepath.clean(abs, allocator)
	return c
}

// Recomputes the watched package set from the roots by following local imports. Cheap: each
// source file is parsed only when its content changed (cached in `imports`).
watcher_resolve :: proc(w: ^Watcher) {
	a := w.allocator
	for s in w.dirs {delete(s, a)}
	clear(&w.dirs)
	for s in w.assets {delete(s, a)}
	clear(&w.assets)
	queue := make([dynamic]string, context.temp_allocator)
	for r in w.roots {
		append(&queue, r)
	}
	for len(queue) > 0 {
		d := pop(&queue)
		if slice.contains(w.dirs[:], d) {
			continue
		}
		append(&w.dirs, strings.clone(d, a))
		entries, err := os.read_all_directory_by_path(d, context.temp_allocator)
		if err != nil {
			continue
		}
		for e in entries {
			if e.type != .Regular || !strings.has_suffix(e.name, ".odin") {
				continue
			}
			refs := file_refs(w, e.fullpath)
			for r in refs {
				if strings.has_prefix(r, "asset:") {
					p := r[6:]
					if !slice.contains(w.assets[:], p) {
						append(&w.assets, strings.clone(p, a))
					}
				} else if !slice.contains(w.dirs[:], r) {
					append(&queue, r)
				}
			}
		}
	}
	slice.sort(w.dirs[:])
}

@(private)
file_refs :: proc(w: ^Watcher, path: string) -> []string {
	if refs, ok := w.imports[path]; ok {
		return refs
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return nil
	}
	found := scan_source_refs(string(data), filepath.dir(path), w.collections, w.allocator)
	w.imports[strings.clone(path, w.allocator)] = found
	return found
}

// Local package dirs (absolute) imported by `src`, plus "asset:<path>" for every literal
// `#load("...")` / `#load_directory("...")`. Core, base, vendor and shared collections are
// skipped (they do not change while you work). Unknown collections are ignored.
scan_source_refs :: proc(src: string, file_dir: string, collections: map[string]string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	add :: proc(out: ^[dynamic]string, s: string, allocator: runtime.Allocator) {
		for o in out {
			if o == s {
				return
			}
		}
		append(out, strings.clone(s, allocator))
	}
	i := 0
	n := len(src)
	for i < n {
		c := src[i]
		// comments
		if c == '/' && i + 1 < n && src[i + 1] == '/' {
			for i < n && src[i] != '\n' {i += 1}
			continue
		}
		if c == '/' && i + 1 < n && src[i + 1] == '*' {
			depth := 1
			i += 2
			for i < n && depth > 0 {
				if src[i] == '/' && i + 1 < n && src[i + 1] == '*' {
					depth += 1
					i += 2
				} else if src[i] == '*' && i + 1 < n && src[i + 1] == '/' {
					depth -= 1
					i += 2
				} else {
					i += 1
				}
			}
			continue
		}
		// raw strings never contain directives we care about
		if c == '`' {
			i += 1
			for i < n && src[i] != '`' {i += 1}
			i += 1
			continue
		}
		if c == '"' {
			i += 1
			for i < n && src[i] != '"' && src[i] != '\n' {
				if src[i] == '\\' {i += 1}
				i += 1
			}
			i += 1
			continue
		}
		at_word := i == 0 || !is_ident(src[i - 1])
		if at_word && c == 'i' && strings.has_prefix(src[i:], "import") && i + 6 < n && !is_ident(src[i + 6]) {
			// `import [name] "path"` (also `foreign import`, which we skip: no quotes to a dir we watch)
			j := i + 6
			for j < n && src[j] != '"' && src[j] != '\n' && src[j] != ';' {j += 1}
			if j < n && src[j] == '"' {
				k := j + 1
				for k < n && src[k] != '"' && src[k] != '\n' {k += 1}
				if k < n && src[k] == '"' {
					if dir, ok := resolve_import(src[j + 1:k], file_dir, collections); ok {
						add(&out, dir, allocator)
					}
				}
				i = k + 1
				continue
			}
			i = j
			continue
		}
		if c == '#' && strings.has_prefix(src[i:], "#load") {
			j := i + 5
			is_dir := strings.has_prefix(src[j:], "_directory")
			if is_dir {
				j += 10
			}
			if strings.has_prefix(src[j:], "_hash") {
				j += 5
			}
			for j < n && (src[j] == ' ' || src[j] == '\t') {j += 1}
			if j < n && src[j] == '(' {
				j += 1
				for j < n && (src[j] == ' ' || src[j] == '\t') {j += 1}
				if j < n && src[j] == '"' {
					k := j + 1
					for k < n && src[k] != '"' && src[k] != '\n' {k += 1}
					if k < n {
						rel := src[j + 1:k]
						p, _ := filepath.join({file_dir, rel}, context.temp_allocator)
						p2, _ := filepath.clean(p, context.temp_allocator)
						if is_dir {
							entries, err := os.read_all_directory_by_path(p2, context.temp_allocator)
							if err == nil {
								for e in entries {
									if e.type == .Regular {
										add(&out, strings.concatenate({"asset:", e.fullpath}, context.temp_allocator), allocator)
									}
								}
							}
						} else {
							add(&out, strings.concatenate({"asset:", p2}, context.temp_allocator), allocator)
						}
					}
					i = k + 1
					continue
				}
			}
			i = j
			continue
		}
		i += 1
	}
	return out[:]
}

@(private)
is_ident :: proc "contextless" (c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// "../vui" relative to the importing file, or "name:sub/dir" through a collection.
resolve_import :: proc(path: string, file_dir: string, collections: map[string]string) -> (dir: string, ok: bool) {
	if colon := strings.index_byte(path, ':'); colon >= 0 {
		name := path[:colon]
		for s in SKIP_COLLECTIONS {
			if name == s {
				return "", false
			}
		}
		root, found := collections[name]
		if !found {
			return "", false
		}
		p, _ := filepath.join({root, path[colon + 1:]}, context.temp_allocator)
		c, _ := filepath.clean(p, context.temp_allocator)
		return c, true
	}
	p, _ := filepath.join({file_dir, path}, context.temp_allocator)
	c, _ := filepath.clean(p, context.temp_allocator)
	return c, true
}

watched_file :: proc(name: string) -> bool {
	return strings.has_suffix(name, ".odin")
}

// Returns the watched files whose content really changed (or that appeared / disappeared)
// since the last scan. Per poll: one stat per watched directory and per watched file, with no
// allocation; a directory is listed again only when its own mtime moved (a file was created,
// deleted or renamed into it, which is how editors save atomically). Stat changes are
// confirmed with a content hash. Import edits re-resolve the package set.
watcher_scan :: proc(w: ^Watcher, allocator := context.allocator) -> []string {
	w.scans += 1
	changed := make([dynamic]string, allocator)
	report := w.scans > 1

	// 1. known files: stat each
	to_check := make([dynamic]string, context.temp_allocator)
	gone := make([dynamic]string, context.temp_allocator)
	for path, st in w.files {
		size, mtime, _, ok := path_stamp(path)
		if !ok {
			append(&gone, path)
		} else if size != st.size || mtime != st.mtime {
			append(&to_check, path)
		}
	}
	for path in to_check {
		size, mtime, _, ok := path_stamp(path)
		if ok {
			watcher_check(w, path, size, mtime, report, &changed, allocator)
		}
	}
	for k in gone {
		if report {
			append(&changed, strings.clone(k, allocator))
		}
		drop_imports(w, k)
		delete_key(&w.files, k)
		delete(k, w.allocator)
	}

	// 2. directories whose entries changed: list them for new files
	for d in w.dirs {
		if dir_moved(w, d) {
			list_dir(w, d, false, report, &changed, allocator)
		}
	}
	for p in w.extra {
		_, mtime, is_dir, ok := path_stamp(p)
		if !ok {
			continue
		}
		if is_dir {
			if dir_moved(w, p) {
				list_dir(w, p, true, report, &changed, allocator)
			}
		} else if p not_in w.files {
			size, _, _, _ := path_stamp(p)
			watcher_check(w, p, size, mtime, report, &changed, allocator)
		}
	}
	for p in w.assets {
		if p in w.files {
			continue
		}
		size, mtime, is_dir, ok := path_stamp(p)
		if ok && !is_dir {
			watcher_check(w, p, size, mtime, report, &changed, allocator)
		}
	}

	if len(changed) > 0 {
		watcher_resolve(w)
		// newly imported packages: baseline them without reporting their files as edits
		for d in w.dirs {
			if dir_moved(w, d) {
				list_dir(w, d, false, false, &changed, allocator)
			}
		}
	}
	return changed[:]
}

// True (and remembers the new time) when a directory's mtime differs from the last scan.
@(private)
dir_moved :: proc(w: ^Watcher, d: string) -> bool {
	_, mtime, _, ok := path_stamp(d)
	if !ok {
		return false
	}
	old, had := w.dir_mtimes[d]
	if had && old == mtime {
		return false
	}
	if had {
		w.dir_mtimes[d] = mtime
	} else {
		w.dir_mtimes[strings.clone(d, w.allocator)] = mtime
	}
	return true
}

@(private)
list_dir :: proc(w: ^Watcher, d: string, any_file: bool, report: bool, changed: ^[dynamic]string, allocator: runtime.Allocator) {
	entries, err := os.read_all_directory_by_path(d, context.temp_allocator)
	if err != nil {
		return
	}
	for e in entries {
		if e.type != .Regular {
			continue
		}
		if any_file ? is_editor_temp(e.name) : !watched_file(e.name) {
			continue
		}
		if e.fullpath in w.files {
			continue
		}
		watcher_check(w, e.fullpath, e.size, time.to_unix_nanoseconds(e.modification_time), report, changed, allocator)
	}
}

@(private)
drop_imports :: proc(w: ^Watcher, path: string) {
	if _, ok := w.imports[path]; ok {
		key, refs := delete_key(&w.imports, path)
		for s in refs {delete(s, w.allocator)}
		delete(refs, w.allocator)
		delete(key, w.allocator)
	}
}

@(private)
watcher_check :: proc(w: ^Watcher, path: string, size: i64, mtime: i64, report: bool, changed: ^[dynamic]string, allocator: runtime.Allocator) {
	old, had := w.files[path]
	if had && old.size == size && old.mtime == mtime {
		return
	}
	h := hash_file(path)
	if had && old.hash == h && old.size == size {
		// same bytes, new timestamp (touch, no-op save): remember the stamp, no rebuild
		w.files[path] = File_Stamp{size, mtime, h}
		return
	}
	if had {
		w.files[path] = File_Stamp{size, mtime, h}
	} else {
		w.files[strings.clone(path, w.allocator)] = File_Stamp{size, mtime, h}
	}
	if report {
		append(changed, strings.clone(path, allocator))
	}
	drop_imports(w, path) // a changed source may add or drop imports
}

path_stamp_os :: proc(path: string) -> (size: i64, mtime: i64, is_dir: bool, ok: bool) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return
	}
	return fi.size, time.to_unix_nanoseconds(fi.modification_time), fi.type == .Directory, true
}

// Vim's write probe ("4913"), swap/backup files, emacs lock files.
is_editor_temp :: proc(name: string) -> bool {
	return name == "4913" || strings.has_suffix(name, "~") || strings.has_suffix(name, ".swp") || strings.has_suffix(name, ".swx") || strings.has_prefix(name, ".#") || strings.has_suffix(name, ".tmp")
}

hash_file :: proc(path: string) -> u64 {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return 0
	}
	return hash.fnv64a(data)
}

// ---------------------------------------------------------------------------
// Compiler output
// ---------------------------------------------------------------------------

Build_Error :: struct {
	file:    string,
	line:    int,
	column:  int,
	message: string,
	count:   int, // number of errors reported
}

// Finds the first `path(line:col) Error: message` (also "Syntax Error") in Odin's output.
parse_build_output :: proc(out: string) -> (e: Build_Error, ok: bool) {
	rest := out
	for line in strings.split_lines_iterator(&rest) {
		l := strings.trim_space(line)
		idx := strings.index(l, ") ")
		if idx < 0 {
			continue
		}
		tail := l[idx + 2:]
		kind_end := strings.index(tail, "Error:")
		if kind_end < 0 || kind_end > 16 {
			continue
		}
		e.count += 1
		if e.count > 1 {
			continue
		}
		open := strings.last_index_byte(l[:idx], '(')
		if open < 0 {
			continue
		}
		loc := l[open + 1:idx]
		colon := strings.index_byte(loc, ':')
		if colon < 0 {
			continue
		}
		e.file = l[:open]
		e.line, _ = strconv.parse_int(loc[:colon])
		e.column, _ = strconv.parse_int(loc[colon + 1:])
		e.message = strings.trim_space(tail[kind_end + 6:])
		ok = true
	}
	return
}

// Keeps the head of a long compiler log (the first errors are the useful ones).
trim_output :: proc(out: string, max_lines := 40, max_bytes := 8192) -> string {
	s := strings.trim_space(out)
	if len(s) > max_bytes {
		s = s[:max_bytes]
	}
	lines := 0
	for i in 0 ..< len(s) {
		if s[i] == '\n' {
			lines += 1
			if lines >= max_lines {
				return s[:i]
			}
		}
	}
	return s
}

// ---------------------------------------------------------------------------
// Supervisor -> runner protocol (the runner's stdin, one message per line)
// ---------------------------------------------------------------------------
//
//   reload <gen> <build_ms> <path>        a new library is ready
//   building <gen>                        a rebuild started
//   error <gen> <bytes>\n<bytes of text>  the rebuild failed; keep running
//   changed <bytes>\n<text>               files that triggered the next build
//   quit                                  exit now

Msg_Kind :: enum u8 {
	Unknown,
	Reload,
	Building,
	Error,
	Changed,
	Quit,
}

Msg :: struct {
	kind:     Msg_Kind,
	gen:      int,
	build_ms: f32,
	path:     string,
	payload:  int, // bytes of text that follow (Error, Changed)
}

parse_msg :: proc(line: string) -> Msg {
	m: Msg
	parts := strings.fields(line, context.temp_allocator)
	if len(parts) == 0 {
		return m
	}
	switch parts[0] {
	case "reload":
		if len(parts) < 4 {
			return m
		}
		m.kind = .Reload
		m.gen, _ = strconv.parse_int(parts[1])
		m.build_ms, _ = strconv.parse_f32(parts[2])
		// the path is everything after the third space (it may contain spaces)
		idx := 0
		for _ in 0 ..< 3 {
			idx += strings.index_byte(line[idx:], ' ') + 1
		}
		m.path = strings.trim_space(line[idx:])
	case "building":
		m.kind = .Building
		if len(parts) > 1 {
			m.gen, _ = strconv.parse_int(parts[1])
		}
	case "error":
		if len(parts) < 3 {
			return m
		}
		m.kind = .Error
		m.gen, _ = strconv.parse_int(parts[1])
		m.payload, _ = strconv.parse_int(parts[2])
	case "changed":
		if len(parts) < 2 {
			return m
		}
		m.kind = .Changed
		m.payload, _ = strconv.parse_int(parts[1])
	case "quit":
		m.kind = .Quit
	}
	if m.payload < 0 || m.payload > 1 << 20 {
		m.kind = .Unknown
		m.payload = 0
	}
	return m
}

// ---------------------------------------------------------------------------
// Generated entry package
// ---------------------------------------------------------------------------

// Source of the tiny package vui-hot builds as the shared library: it imports the app's own
// package and exports the entry the runner calls. The app keeps a normal `main`.
entry_source :: proc(user_import: string, allocator := context.allocator) -> string {
	return strings.concatenate({
		"// Generated by vui-hot. Do not edit: rewritten on every start.\n",
		"package vui_hot_entry\n\n",
		"import \"base:runtime\"\n",
		"import vapp \"vinland:vui/app\"\n",
		"import vhot \"vinland:vui/hot\"\n",
		"import user \"", user_import, "\"\n\n",
		"@(export)\n",
		"vui_hot_entry :: proc \"c\" (host: ^vhot.Host, op: vhot.Op) -> vhot.Result {\n",
		"\tcontext = runtime.default_context()\n",
		"\treturn vapp.hot_entry(host, op, user.main)\n",
		"}\n",
	}, allocator)
}

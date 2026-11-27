// vui-hot: optional hot reload for vinland-ui apps.
//
//   vui-hot [options] <package-dir> [-- app args...]
//
// Watches the app's packages (its directory and every local package it imports, plus #load-ed
// assets), rebuilds it as a shared library on each real change and swaps the new code into the
// running process. The window, GPU device, ui.Context and `app.keep` globals survive; a failed
// build leaves the previous one running with the compiler output drawn over it; a crash restarts
// the app (rolling back to the previous build when the new one crashed right after loading).
//
// The same package still builds and runs with a plain `odin build`: hot reload is a
// development alternative, never a requirement.
package vui_hot_tool

import "base:runtime"
import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import hot "../../vui/hot"

USAGE :: `vui-hot: hot reload for vinland-ui apps (an alternative to rebuilding by hand)

usage: vui-hot [options] <package-dir> [-- app args...]

  -collection:<name>=<dir>  passed to odin and used to follow imports (repeatable)
  -<any odin flag>          passed to odin build (default -debug), e.g. -o:none -define:X=1
  --watch <path>            also watch this file or directory (repeatable)
  --out <dir>               build directory (default build/hot/<package>)
  --poll <ms>               scan interval (default 100)
  --debounce <ms>           quiet period after a change before building (default 30)
  --no-restart              exit when the app crashes instead of restarting it
  --quiet                   only print errors

The app needs app.run(Program{...}) for state-keeping reloads (see vui/app/program.odin);
a classic 'for app.next_frame' loop also reloads, but reopens its window each time.
VUI_HOT_OVERLAY=0 hides the in-window build status.
`

Options :: struct {
	pkg_dir:     string,
	pkg_name:    string,
	out_dir:     string,
	root:        string, // vinland-ui checkout (the `vinland` collection)
	odin_flags:  [dynamic]string,
	collections: map[string]string,
	watch:       [dynamic]string,
	app_args:    [dynamic]string,
	poll_ms:     int,
	debounce_ms: int,
	no_restart:  bool,
	quiet:       bool,
}

main :: proc() {
	platform_init()
	args := os.args[1:]
	if len(args) > 0 && args[0] == "--child" {
		os.exit(child_main(args[1:]))
	}
	os.exit(supervisor_main(args))
}

// ---------------------------------------------------------------------------
// Supervisor
// ---------------------------------------------------------------------------

Build :: struct {
	gen:       int,
	path:      string,
	process:   os.Process,
	reader:    ^os.File,
	thread:    ^thread.Thread,
	output:    [dynamic]u8,
	done:      bool, // atomic, set by the drain thread
	state:     os.Process_State,
	started:   time.Tick,
	cancelled: bool,
	changed:   string,
}

Sup :: struct {
	opt:            Options,
	self_exe:       string,
	entry_dir:      string,
	watcher:        hot.Watcher,
	gen:            int,
	build:          ^Build,
	good_gen:       int, // newest successful build
	good_ms:        f32,
	prev_gen:       int, // the good build before it (rollback target)
	restart_gen:    int, // build to restart on after a crash (0 = good_gen)
	bad_gen:        int, // crashed right after loading; not used for restarts
	child:          os.Process,
	child_alive:    bool,
	child_in:       ^os.File,
	child_gen:      int,
	child_started:  time.Tick,
	reload_sent:    time.Tick,
	reload_sent_gen: int,
	crashes:        [dynamic]time.Tick,
	waiting:        bool, // stopped respawning after a crash loop; wait for the next good build
	pending:        [dynamic]string, // changed files not built yet
	last_change:    time.Tick,
}

g_interrupted: bool

on_interrupt :: proc "c" (sig: i32) {
	_ = sig
	sync.atomic_store(&g_interrupted, true)
}

say :: proc(s: ^Sup, format: string, args: ..any) {
	if s.opt.quiet {
		return
	}
	fmt.eprint("vui-hot: ")
	fmt.eprintfln(format, ..args)
}

supervisor_main :: proc(args: []string) -> int {
	s: Sup
	if !parse_options(&s.opt, args) {
		return 2
	}
	opt := &s.opt
	exe, eerr := os.get_executable_path(context.allocator)
	if eerr != nil {
		exe = os.args[0]
	}
	s.self_exe = exe

	// generated entry package + output dir
	_ = os.make_directory_all(opt.out_dir)
	if !opt.quiet {
		platform_check_out_dir(opt.out_dir)
	}
	clean_builds(opt.out_dir, opt.pkg_name, -1, -1)
	s.entry_dir, _ = filepath.join({opt.out_dir, "entry"})
	_ = os.make_directory_all(s.entry_dir)
	parent := filepath.dir(opt.pkg_dir)
	user_import := strings.concatenate({"vui_hot_app:", filepath.base(opt.pkg_dir)})
	opt.collections["vui_hot_app"] = parent
	entry_file, _ := filepath.join({s.entry_dir, "entry.odin"})
	if err := os.write_entire_file(entry_file, hot.entry_source(user_import)); err != nil {
		fmt.eprintfln("vui-hot: cannot write %s: %v", entry_file, err)
		return 1
	}

	watch_collections := make(map[string]string)
	for k, v in opt.collections {
		if k != "vui_hot_app" {
			watch_collections[k] = v
		}
	}
	hot.watcher_init(&s.watcher, {opt.pkg_dir}, watch_collections, opt.watch[:])
	// The generated entry reaches vui/app through the `vinland` collection. If the app imports a
	// different vui checkout (relative paths into another copy), the two would be separate
	// packages and the app would never hand control back for a reload.
	want_app, _ := filepath.join({opt.root, "vui", "app"}, context.temp_allocator)
	for d in s.watcher.dirs {
		if filepath.base(d) == "app" && filepath.base(filepath.dir(d)) == "vui" && d != want_app {
			fmt.eprintfln("vui-hot: the app imports %s but the vinland collection is %s;\n  pass -collection:vinland=%s (or VUI_ROOT) so both use the same vui", d, opt.root, filepath.dir(filepath.dir(d)))
			return 2
		}
	}
	nfiles := len(s.watcher.files)
	say(&s, "watching %d packages (%d files) for %s", len(s.watcher.dirs), nfiles, opt.pkg_name)

	libc.signal(libc.SIGINT, transmute(proc "c" (i32))on_interrupt)
	libc.signal(libc.SIGTERM, transmute(proc "c" (i32))on_interrupt)

	start_build(&s, "")
	exit_code := 0
	for {
		free_all(context.temp_allocator)
		if sync.atomic_load(&g_interrupted) {
			exit_code = 130
			break
		}
		if b := s.build; b != nil && sync.atomic_load(&b.done) {
			finish_build(&s)
		}
		if s.child_alive {
			if code, done := check_child(&s); done {
				exit_code = code
				break
			}
		}
		changed := hot.watcher_scan(&s.watcher, context.temp_allocator)
		if len(changed) > 0 {
			for c in changed {
				if !contains(s.pending[:], c) {
					append(&s.pending, strings.clone(c))
				}
			}
			s.last_change = time.tick_now()
		}
		if len(s.pending) > 0 && time.tick_since(s.last_change) >= time.Duration(opt.debounce_ms) * time.Millisecond {
			files := strings.builder_make(context.temp_allocator)
			for p, i in s.pending {
				if i > 0 {
					strings.write_string(&files, " ")
				}
				strings.write_string(&files, rel_path(p))
				delete(p)
			}
			clear(&s.pending)
			start_build(&s, strings.to_string(files))
		}
		time.sleep(time.Duration(opt.poll_ms) * time.Millisecond)
	}
	shutdown_all(&s)
	return exit_code
}

contains :: proc(list: []string, s: string) -> bool {
	for l in list {
		if l == s {
			return true
		}
	}
	return false
}

rel_path :: proc(p: string) -> string {
	cwd, err := os.get_working_directory(context.temp_allocator)
	if err == nil {
		if r, rerr := filepath.rel(cwd, p, context.temp_allocator); rerr == nil && !strings.has_prefix(r, "..") {
			return r
		}
	}
	return p
}

parse_options :: proc(o: ^Options, args: []string) -> bool {
	o.poll_ms = 100
	o.debounce_ms = 30
	o.collections = make(map[string]string)
	has_opt := false
	i := 0
	for i < len(args) {
		a := args[i]
		switch {
		case a == "-h" || a == "--help" || a == "help":
			fmt.print(USAGE)
			os.exit(0)
		case a == "--":
			for rest in args[i + 1:] {
				append(&o.app_args, rest)
			}
			i = len(args)
			continue
		case a == "--watch" || a == "--out" || a == "--poll" || a == "--debounce":
			if i + 1 >= len(args) {
				fmt.eprintfln("vui-hot: %s needs a value", a)
				return false
			}
			v := args[i + 1]
			i += 1
			switch a {
			case "--watch":
				append(&o.watch, v)
			case "--out":
				o.out_dir = hot.clean_abs(v)
			case "--poll":
				n, ok := strconv.parse_int(v)
				if !ok || n < 10 || n > 5000 {
					fmt.eprintln("vui-hot: --poll must be 10..5000 ms")
					return false
				}
				o.poll_ms = n
			case "--debounce":
				n, ok := strconv.parse_int(v)
				if !ok || n < 0 || n > 5000 {
					fmt.eprintln("vui-hot: --debounce must be 0..5000 ms")
					return false
				}
				o.debounce_ms = n
			}
		case a == "--no-restart":
			o.no_restart = true
		case a == "--quiet":
			o.quiet = true
		case strings.has_prefix(a, "--"):
			fmt.eprintfln("vui-hot: unknown option %s (see --help)", a)
			return false
		case strings.has_prefix(a, "-collection:"):
			kv := a[len("-collection:"):]
			eq := strings.index_byte(kv, '=')
			if eq <= 0 {
				fmt.eprintfln("vui-hot: bad %s (want -collection:name=dir)", a)
				return false
			}
			o.collections[kv[:eq]] = hot.clean_abs(kv[eq + 1:])
		case strings.has_prefix(a, "-build-mode") || strings.has_prefix(a, "-out:"):
			fmt.eprintfln("vui-hot: %s is set by vui-hot", a)
			return false
		case strings.has_prefix(a, "-"):
			if a == "-debug" || strings.has_prefix(a, "-o:") {
				has_opt = true
			}
			append(&o.odin_flags, a)
		case:
			if o.pkg_dir != "" {
				fmt.eprintfln("vui-hot: one package only (got %s and %s); app args go after --", o.pkg_dir, a)
				return false
			}
			o.pkg_dir = hot.clean_abs(a)
		}
		i += 1
	}
	if o.pkg_dir == "" {
		fmt.eprint(USAGE)
		return false
	}
	if !os.is_dir(o.pkg_dir) {
		fmt.eprintfln("vui-hot: %s is not a directory", o.pkg_dir)
		return false
	}
	has_source := false
	if entries, err := os.read_all_directory_by_path(o.pkg_dir, context.temp_allocator); err == nil {
		for e in entries {
			if strings.has_suffix(e.name, ".odin") {
				has_source = true
			}
		}
	}
	if !has_source {
		fmt.eprintfln("vui-hot: no .odin files in %s", o.pkg_dir)
		return false
	}
	o.pkg_name = filepath.base(o.pkg_dir)
	if !has_opt {
		append(&o.odin_flags, "-debug")
	}
	if root, ok := o.collections["vinland"]; ok {
		o.root = root
	} else {
		o.root = find_root(o.pkg_dir)
		if o.root == "" {
			fmt.eprintln("vui-hot: cannot find the vinland-ui checkout; pass -collection:vinland=<dir> or set VUI_ROOT")
			return false
		}
		o.collections["vinland"] = o.root
	}
	if o.out_dir == "" {
		cwd, _ := os.get_working_directory(context.allocator)
		o.out_dir, _ = filepath.join({cwd, "build", "hot", o.pkg_name})
	}
	return true
}

is_root :: proc(dir: string) -> bool {
	p, _ := filepath.join({dir, "vui", "hot", "hot.odin"}, context.temp_allocator)
	return os.exists(p)
}

// VUI_ROOT, then upwards from the package (an app inside a checkout imports that checkout),
// then upwards from this executable (build/vui-hot).
find_root :: proc(pkg_dir: string) -> string {
	if v := os.get_env("VUI_ROOT", context.temp_allocator); v != "" && is_root(v) {
		return hot.clean_abs(v)
	}
	starts: [2]string
	starts[0] = pkg_dir
	if exe_dir, err := os.get_executable_directory(context.temp_allocator); err == nil {
		starts[1] = exe_dir
	}
	for st in starts {
		d := st
		for _ in 0 ..< 12 {
			if d == "" {
				break
			}
			if is_root(d) {
				return hot.clean_abs(d)
			}
			parent := filepath.dir(d)
			if parent == d {
				break
			}
			d = parent
		}
	}
	return ""
}

dll_path :: proc(out_dir, name: string, gen: int, allocator := context.allocator) -> string {
	p, _ := filepath.join({out_dir, fmt.tprintf("%s_%d%s", name, gen, DLL_EXT)}, allocator)
	return p
}

// Removes old builds, keeping the generations in `keep_a` / `keep_b` (-1 = none).
clean_builds :: proc(out_dir, name: string, keep_a, keep_b: int) {
	entries, err := os.read_all_directory_by_path(out_dir, context.temp_allocator)
	if err != nil {
		return
	}
	prefix := strings.concatenate({name, "_"}, context.temp_allocator)
	for e in entries {
		if !strings.has_prefix(e.name, prefix) {
			continue
		}
		rest := e.name[len(prefix):]
		dot := strings.index_byte(rest, '.')
		if dot <= 0 {
			continue
		}
		g, ok := strconv.parse_int(rest[:dot])
		if !ok || g == keep_a || g == keep_b {
			continue
		}
		if e.type == .Directory {
			_ = os.remove_all(e.fullpath) // .dSYM bundles
		} else {
			_ = os.remove(e.fullpath)
		}
	}
}

start_build :: proc(s: ^Sup, changed: string) {
	if b := s.build; b != nil {
		// a newer edit arrived mid-build: the running compile is already stale
		b.cancelled = true
		_ = os.process_kill(b.process)
		thread.join(b.thread)
		thread.destroy(b.thread)
		_, _ = os.process_wait(b.process)
		_ = os.remove(b.path)
		say(s, "#%d cancelled (newer change)", b.gen)
		build_free(b)
		s.build = nil
		if changed == "" {
			return
		}
	}
	s.gen += 1
	b := new(Build)
	b.gen = s.gen
	b.path = dll_path(s.opt.out_dir, s.opt.pkg_name, b.gen)
	b.changed = strings.clone(changed)
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, "odin", "build", s.entry_dir, "-build-mode:dll", strings.concatenate({"-out:", b.path}, context.temp_allocator))
	for k, v in s.opt.collections {
		append(&cmd, fmt.tprintf("-collection:%s=%s", k, v))
	}
	for f in s.opt.odin_flags {
		append(&cmd, f)
	}
	r, w, perr := os.pipe()
	if perr != nil {
		fmt.eprintfln("vui-hot: pipe failed: %v", perr)
		free(b)
		return
	}
	b.reader = r
	b.started = time.tick_now()
	proc_, err := os.process_start({command = cmd[:], stdout = w, stderr = w})
	os.close(w)
	if err != nil {
		os.close(r)
		fmt.eprintfln("vui-hot: cannot run odin: %v (is it on PATH?)", err)
		free(b)
		return
	}
	b.process = proc_
	b.thread = thread.create_and_start_with_poly_data(b, drain_build)
	s.build = b
	if changed != "" {
		send_text(s, "changed", changed)
		send(s, fmt.tprintf("building %d\n", b.gen))
	}
}

drain_build :: proc(b: ^Build) {
	buf: [8192]u8
	for {
		n, err := os.read(b.reader, buf[:])
		if n > 0 {
			append(&b.output, ..buf[:n])
		}
		if err != nil || n <= 0 {
			break
		}
	}
	os.close(b.reader)
	b.state, _ = os.process_wait(b.process)
	sync.atomic_store(&b.done, true)
}

build_free :: proc(b: ^Build) {
	delete(b.output)
	delete(b.path)
	delete(b.changed)
	free(b)
}

finish_build :: proc(s: ^Sup) {
	b := s.build
	s.build = nil
	thread.join(b.thread)
	thread.destroy(b.thread)
	defer build_free(b)
	ms := f32(time.duration_milliseconds(time.tick_since(b.started)))
	out := string(b.output[:])
	ok := b.state.exited && b.state.exit_code == 0 && os.exists(b.path)
	if !ok {
		summary, has := hot.parse_build_output(out)
		text := hot.trim_output(out)
		if text == "" {
			text = fmt.tprintf("odin exited with %d", b.state.exit_code)
		}
		fmt.eprintfln("vui-hot: ✗ #%d failed (%.2f s)%s", b.gen, ms / 1000, has ? fmt.tprintf(": %s:%d:%d %s", rel_path(summary.file), summary.line, summary.column, summary.message) : "")
		fmt.eprintln(text)
		_ = os.remove(b.path)
		send_text(s, fmt.tprintf("error %d", b.gen), text)
		return
	}
	if b.changed != "" {
		say(s, "✓ #%d built in %.2f s (%s)", b.gen, ms / 1000, b.changed)
	} else {
		say(s, "✓ #%d built in %.2f s", b.gen, ms / 1000)
	}
	if s.good_gen > 0 && s.good_gen != s.bad_gen {
		s.prev_gen = s.good_gen // last build that did not crash on load
	}
	s.good_gen = b.gen
	s.good_ms = ms
	clean_builds(s.opt.out_dir, s.opt.pkg_name, s.good_gen, s.prev_gen)
	if s.child_alive {
		s.restart_gen = 0
		send(s, fmt.tprintf("reload %d %.1f %s\n", b.gen, ms, b.path))
		s.reload_sent = time.tick_now()
		s.reload_sent_gen = b.gen
	} else {
		s.waiting = false
		clear(&s.crashes)
		s.restart_gen = 0
		spawn_child(s, s.good_gen, s.good_ms)
	}
}

spawn_child :: proc(s: ^Sup, gen: int, build_ms: f32) {
	path := dll_path(s.opt.out_dir, s.opt.pkg_name, gen, context.temp_allocator)
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, s.self_exe, "--child", s.opt.pkg_name, fmt.tprint(gen), fmt.tprintf("%.1f", build_ms), path, "--")
	for a in s.opt.app_args {
		append(&cmd, a)
	}
	r, w, perr := os.pipe()
	if perr != nil {
		fmt.eprintfln("vui-hot: pipe failed: %v", perr)
		return
	}
	p, err := os.process_start({command = cmd[:], stdin = r, stdout = os.stdout, stderr = os.stderr})
	os.close(r)
	if err != nil {
		os.close(w)
		fmt.eprintfln("vui-hot: cannot start the runner: %v", err)
		return
	}
	s.child = p
	s.child_in = w
	s.child_alive = true
	s.child_gen = gen
	s.child_started = time.tick_now()
	s.reload_sent_gen = 0
}

// Writes one protocol line to the runner. A dead runner (EPIPE) is noticed by check_child.
send :: proc(s: ^Sup, line: string) {
	if !s.child_alive || s.child_in == nil {
		return
	}
	_, _ = os.write(s.child_in, transmute([]u8)line)
}

send_text :: proc(s: ^Sup, head: string, text: string) {
	send(s, fmt.tprintf("%s %d\n%s", head, len(text), text))
}

// Returns (exit code, true) when the supervisor should stop.
check_child :: proc(s: ^Sup) -> (int, bool) {
	state, err := os.process_wait(s.child, 0)
	if err != nil || !state.exited {
		return 0, false
	}
	s.child_alive = false
	os.close(s.child_in)
	s.child_in = nil
	if sync.atomic_load(&g_interrupted) {
		return 130, true
	}
	if state.success && state.exit_code == 0 {
		say(s, "app exited")
		return 0, true
	}
	if state.exit_code == 3 {
		fmt.eprintln("vui-hot: the app was built against a different vui/hot; rebuild vui-hot (./build.sh) and start it again")
		return 3, true
	}
	reason := describe_exit(state)
	if s.opt.no_restart {
		fmt.eprintfln("vui-hot: app %s (--no-restart)", reason)
		return state.exit_code != 0 ? state.exit_code : 1, true
	}
	now := time.tick_now()
	// a build that dies within 3 s of being swapped in is the likely culprit: roll back
	if s.reload_sent_gen != 0 && s.reload_sent_gen == s.good_gen && time.tick_diff(s.reload_sent, now) < 3 * time.Second && s.prev_gen > 0 {
		s.bad_gen = s.good_gen
		s.restart_gen = s.prev_gen
		fmt.eprintfln("vui-hot: ✗ app %s right after loading #%d; restarting on #%d (state was lost)", reason, s.good_gen, s.prev_gen)
		spawn_child(s, s.prev_gen, 0)
		send_text(s, fmt.tprintf("error %d", s.bad_gen), fmt.tprintf("build #%d crashed right after it was loaded (%s).\nThe app restarted on build #%d; fix the code and save to retry.", s.bad_gen, reason, s.prev_gen))
		return 0, false
	}
	append(&s.crashes, now)
	recent := 0
	for c in s.crashes {
		if time.tick_diff(c, now) < 10 * time.Second {
			recent += 1
		}
	}
	if recent >= 3 {
		fmt.eprintfln("vui-hot: ✗ app %s (%d times in 10 s); waiting for the next change", reason, recent)
		s.waiting = true
		return 0, false
	}
	gen := s.restart_gen > 0 ? s.restart_gen : s.good_gen
	fmt.eprintfln("vui-hot: ✗ app %s; restarting #%d (state was lost)", reason, gen)
	spawn_child(s, gen, 0)
	return 0, false
}

describe_exit :: proc(st: os.Process_State) -> string {
	if name := platform_signal_name(st); name != "" {
		return fmt.tprintf("stopped with status %d (%s)", st.exit_code, name)
	}
	return fmt.tprintf("exited with code %d", st.exit_code)
}

shutdown_all :: proc(s: ^Sup) {
	if b := s.build; b != nil {
		_ = os.process_kill(b.process)
		thread.join(b.thread)
		_, _ = os.process_wait(b.process)
	}
	if s.child_alive {
		send(s, "quit\n")
		os.close(s.child_in)
		s.child_in = nil
		state, err := os.process_wait(s.child, 3 * time.Second)
		if err != nil || !state.exited {
			_ = os.process_kill(s.child)
			_, _ = os.process_wait(s.child)
		}
		s.child_alive = false
	}
	clean_builds(s.opt.out_dir, s.opt.pkg_name, -1, -1)
}

// ---------------------------------------------------------------------------
// Runner (child process): owns the window across library swaps
// ---------------------------------------------------------------------------

Pending :: struct {
	path:     string,
	gen:      int,
	build_ms: f32,
}

Child :: struct {
	host:    hot.Host,
	pending: Pending, // guarded by host.mutex
}

Loaded :: struct {
	path:  string,
	lib:   dynlib.Library,
	entry: hot.Entry_Proc,
	gen:   int,
}

load_build :: proc(path: string, gen: int) -> (l: Loaded, msg: string) {
	lib, ok := dynlib.load_library(path)
	if !ok {
		return {}, fmt.tprintf("cannot load %s: %s", path, dynlib.last_error())
	}
	sym, found := dynlib.symbol_address(lib, hot.ENTRY_SYMBOL)
	if !found || sym == nil {
		_ = dynlib.unload_library(lib)
		return {}, fmt.tprintf("%s has no %s (was it built by vui-hot?)", path, hot.ENTRY_SYMBOL)
	}
	return Loaded{path = strings.clone(path), lib = lib, entry = hot.Entry_Proc(sym), gen = gen}, ""
}

child_main :: proc(args: []string) -> int {
	// --child <name> <gen> <build_ms> <path> -- app args
	if len(args) < 5 || args[4] != "--" {
		fmt.eprintln("vui-hot: --child is internal")
		return 2
	}
	c := new(Child)
	h := &c.host
	hot.host_init(h, context.allocator)
	// every build runs on this (main) thread with the runner's temp arena: one arena for the whole
	// session instead of a fresh 4 MB one per build
	h.temp_allocator = context.temp_allocator
	if v := os.get_env("VUI_HOT_TRACE_ALLOC", context.temp_allocator); v != "" {
		if n, ok := strconv.parse_int(v); ok && n > 1 {
			g_trace_min = n
		}
		h.allocator = runtime.Allocator{procedure = trace_alloc_proc, data = nil}
	}
	h.app_name = args[0]
	gen, _ := strconv.parse_int(args[1])
	build_ms, _ := strconv.parse_f32(args[2])
	path := args[3]
	app_args := make([dynamic]string)
	append(&app_args, args[0])
	for a in args[5:] {
		append(&app_args, a)
	}
	h.args = app_args[:]
	h.generation = gen
	h.build_ms = build_ms

	io := thread.create_and_start_with_poly_data(c, child_io)
	_ = io

	libs := make([dynamic]Loaded)
	cur, msg := load_build(path, gen)
	if msg != "" {
		fmt.eprintln("vui-hot:", msg)
		return 1
	}
	append(&libs, cur)
	result := cur.entry(h, .Run)
	for {
		switch result {
		case .Quit:
			return 0
		case .Failed:
			return h.persist == nil && h.reloads == 0 ? 1 : 3
		case .Incompatible:
			fmt.eprintln("vui-hot: unexpected incompatible state")
			return 1
		case .Reload:
		}
		// take the newest pending build and clear the flag before running it
		sync.mutex_lock(&h.mutex)
		p := c.pending
		c.pending = {}
		sync.atomic_store(&h.reload, false)
		sync.mutex_unlock(&h.mutex)
		if hot.quit_requested(h) {
			result = cur.entry(h, .Shutdown)
			return 0
		}
		if p.path == "" {
			result = cur.entry(h, .Run) // spurious: resume the same build
			continue
		}
		t0 := time.tick_now()
		next, lmsg := load_build(p.path, p.gen)
		delete(p.path)
		if lmsg != "" {
			fmt.eprintln("vui-hot:", lmsg)
			sync.mutex_lock(&h.mutex)
			h.status = .Error
			h.error_gen = p.gen
			hot.host_set_string(h, &h.error_text, lmsg)
			h.status_version += 1
			sync.mutex_unlock(&h.mutex)
			result = cur.entry(h, .Run)
			continue
		}
		append(&libs, next) // never unloaded: live state may point into older builds
		platform_release_library(cur.path) // but let the OS reclaim its pages first
		sync.mutex_lock(&h.mutex)
		h.generation = p.gen
		h.build_ms = p.build_ms
		h.swap_ms = f32(time.duration_milliseconds(time.tick_since(t0)))
		h.status = .Idle // a successful build clears the error / building pill
		hot.host_set_string(h, &h.error_text, "")
		h.reloads += 1
		h.status_version += 1
		sync.mutex_unlock(&h.mutex)
		result = next.entry(h, .Run)
		if result == .Failed && h.persist != nil {
			// refused before touching anything (e.g. built against another vui/hot): keep the old build
			sync.mutex_lock(&h.mutex)
			h.status = .Error
			h.error_gen = p.gen
			hot.host_set_string(h, &h.error_text, "this build was made against a different vui/hot than the running vui-hot.\nRebuild vui-hot (./build.sh) and restart it to load it.")
			h.status_version += 1
			sync.mutex_unlock(&h.mutex)
			result = cur.entry(h, .Run)
			continue
		}
		if result == .Incompatible {
			// the framework's own layout changed: close the window with the old code, start cold
			_ = cur.entry(h, .Shutdown)
			result = next.entry(h, .Run)
		}
		cur = next
	}
}

child_io :: proc(c: ^Child) {
	h := &c.host
	r := os.stdin
	buf: [dynamic]u8
	chunk: [4096]u8
	for {
		n, err := os.read(r, chunk[:])
		if n > 0 {
			append(&buf, ..chunk[:n])
		}
		for {
			consumed := child_handle(c, buf[:])
			if consumed == 0 {
				break
			}
			remove_range(&buf, 0, consumed)
		}
		if err != nil || n <= 0 {
			break
		}
	}
	// supervisor gone (EOF): never leave an orphan window behind
	hot.request_quit(h)
}

// Handles one complete message at the start of `data`; returns the bytes consumed (0 = need more).
child_handle :: proc(c: ^Child, data: []u8) -> int {
	nl := -1
	for b, i in data {
		if b == '\n' {
			nl = i
			break
		}
	}
	if nl < 0 {
		return 0
	}
	line := string(data[:nl])
	m := hot.parse_msg(line)
	total := nl + 1
	text := ""
	if m.kind == .Error || m.kind == .Changed {
		if len(data) < total + m.payload {
			return 0
		}
		text = string(data[total:total + m.payload])
		total += m.payload
	}
	h := &c.host
	switch m.kind {
	case .Reload:
		sync.mutex_lock(&h.mutex)
		delete(c.pending.path)
		c.pending = Pending{path = strings.clone(m.path), gen = m.gen, build_ms = m.build_ms}
		sync.mutex_unlock(&h.mutex)
		hot.request_reload(h)
	case .Building:
		sync.mutex_lock(&h.mutex)
		if h.status != .Error {
			h.status = .Building
		}
		h.status_version += 1
		sync.mutex_unlock(&h.mutex)
		hot.host_wake(h)
	case .Error:
		sync.mutex_lock(&h.mutex)
		h.status = .Error
		h.error_gen = m.gen
		hot.host_set_string(h, &h.error_text, text)
		h.status_version += 1
		sync.mutex_unlock(&h.mutex)
		hot.host_wake(h)
	case .Changed:
		sync.mutex_lock(&h.mutex)
		hot.host_set_string(h, &h.changed, text)
		sync.mutex_unlock(&h.mutex)
	case .Quit:
		hot.request_quit(h)
	case .Unknown:
	}
	free_all(context.temp_allocator)
	return total
}

// VUI_HOT_TRACE_ALLOC=1 (or =<bytes>): log every app allocation of at least 16 KB (or <bytes>)
// with its source location (all app allocations go through the runner's allocator under vui-hot).
g_trace_min := 16384

trace_alloc_proc :: proc(data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
	if (mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed) && size >= g_trace_min {
		fmt.eprintfln("[alloc] %d %v %s:%d %s", size, mode, loc.file_path, loc.line, loc.procedure)
	}
	return runtime.heap_allocator_proc(data, mode, size, alignment, old_memory, old_size, loc)
}

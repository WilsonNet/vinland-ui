package vui_tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import ui "../vui"
import vapp "../vui/app"
import hot "../vui/hot"

// ---------------------------------------------------------------------------
// Fingerprints
// ---------------------------------------------------------------------------

Fp_A :: struct {
	x: int,
	y: f32,
}
Fp_A_Same :: struct {
	x: int,
	y: f32,
}
Fp_B :: struct {
	x: int,
	y: f64,
}
Fp_C :: struct {
	y: f32,
	x: int,
}
Fp_Node :: struct {
	value: int,
	next:  ^Fp_Node, // recursive through a pointer
	kids:  [dynamic]Fp_Node,
}
Fp_Enum_1 :: enum {
	A,
	B,
}
Fp_Enum_2 :: enum {
	A,
	B,
	C,
}

@(test)
hot_fingerprint_is_structural :: proc(t: ^testing.T) {
	a := hot.fingerprint(type_info_of(Fp_A))
	testing.expect_value(t, a, hot.fingerprint(type_info_of(Fp_A)))
	testing.expect(t, a != hot.fingerprint(type_info_of(Fp_B)), "field type change")
	testing.expect(t, a != hot.fingerprint(type_info_of(Fp_C)), "field order change")
	testing.expect(t, a != hot.fingerprint(type_info_of(Fp_A_Same)), "the type name is part of the fingerprint")
	testing.expect(t, hot.fingerprint(type_info_of(Fp_Enum_1)) != hot.fingerprint(type_info_of(Fp_Enum_2)), "enum values")
	testing.expect(t, hot.fingerprint(type_info_of([4]int)) != hot.fingerprint(type_info_of([5]int)), "array length")
	testing.expect(t, hot.fingerprint(type_info_of(map[string]int)) != hot.fingerprint(type_info_of(map[string]i32)), "map value")
	testing.expect(t, hot.fingerprint(type_info_of(union {
			int,
			f32,
		})) != hot.fingerprint(type_info_of(union {
			f32,
			int,
		})), "union variant order changes tags")
}

@(test)
hot_fingerprint_handles_cycles_and_big_types :: proc(t: ^testing.T) {
	n := hot.fingerprint(type_info_of(Fp_Node))
	testing.expect(t, n != 0)
	testing.expect_value(t, n, hot.fingerprint(type_info_of(Fp_Node)))
	// the framework's own parked state: App -> Context -> ... must hash quickly
	start := time.tick_now()
	f1 := hot.fingerprint(type_info_of(vapp.Hot_Persist))
	ms := time.duration_milliseconds(time.tick_since(start))
	testing.expect(t, f1 != 0)
	testing.expectf(t, ms < 50, "fingerprint(Hot_Persist) took %.2f ms", ms)
	testing.expect_value(t, f1, hot.fingerprint(type_info_of(vapp.Hot_Persist)))
}

// ---------------------------------------------------------------------------
// Migration
// ---------------------------------------------------------------------------

Old_State :: struct {
	count:   int,
	name:    string,
	gone:    bool,
	nested:  struct {
		a: i32,
		b: f32,
	},
	grid:    [3]i32,
	changed: [2]int,
	small:   i64,
	big:     i64,
	ratio:   f32,
}

New_State :: struct {
	name:    string, // moved
	count:   int,
	added:   int,
	nested:  struct {
		b: f32,
		c: u8,
		a: i64, // widened
	},
	grid:    [2]i32, // shorter
	changed: string, // incompatible
	small:   u8, // value fits
	big:     u8, // value does not fit
	ratio:   f64,
}

@(test)
hot_migrate_by_field_name :: proc(t: ^testing.T) {
	old := Old_State {
		count = 7,
		name = "kept",
		gone = true,
		nested = {a = -5, b = 2.5},
		grid = {1, 2, 3},
		changed = {9, 9},
		small = 200,
		big = 1000,
		ratio = 0.25,
	}
	nw := New_State {
		added = 42,
		changed = "default",
		big = 3,
	}
	m: hot.Migration
	hot.migrate(&nw, type_info_of(New_State), &old, type_info_of(Old_State), &m)
	defer hot.migration_destroy(&m)
	testing.expect(t, !m.exact)
	testing.expect_value(t, nw.count, 7)
	testing.expect_value(t, nw.name, "kept")
	testing.expect_value(t, nw.added, 42) // new field keeps its default
	testing.expect_value(t, nw.nested.a, -5) // i32 -> i64
	testing.expect_value(t, nw.nested.b, 2.5)
	testing.expect_value(t, nw.nested.c, 0)
	testing.expect_value(t, nw.grid, [2]i32{1, 2})
	testing.expect_value(t, nw.changed, "default")
	testing.expect_value(t, nw.small, 200)
	testing.expect_value(t, nw.big, 3) // 1000 does not fit a u8: never wrapped
	testing.expect_value(t, nw.ratio, 0.25)
	summary := hot.migration_summary(&m)
	testing.expectf(t, strings.contains(summary, "added: added"), "%s", summary)
	testing.expectf(t, strings.contains(summary, "nested.c"), "%s", summary)
	testing.expectf(t, strings.contains(summary, "removed: gone"), "%s", summary)
	testing.expectf(t, strings.contains(summary, "changed") && strings.contains(summary, "big"), "%s", summary)
}

@(test)
hot_migrate_identical_is_bytewise :: proc(t: ^testing.T) {
	arr := make([dynamic]int)
	defer delete(arr)
	append(&arr, 1, 2, 3)
	Holder :: struct {
		items: [dynamic]int,
		m:     map[string]int,
		p:     proc() -> int,
	}
	src := Holder{items = arr, p = proc() -> int {return 5}}
	dst: Holder
	m: hot.Migration
	hot.migrate(&dst, type_info_of(Holder), &src, type_info_of(Holder), &m)
	defer hot.migration_destroy(&m)
	testing.expect(t, m.exact)
	testing.expect_value(t, len(dst.items), 3)
	testing.expect(t, raw_data(dst.items) == raw_data(arr), "heap data is shared, not copied")
	testing.expect_value(t, dst.p(), 5)
	testing.expect_value(t, hot.migration_summary(&m), "kept")
}

@(test)
hot_migrate_unrelated_types_resets :: proc(t: ^testing.T) {
	src: f64 = 3.5
	dst: string = "default"
	m: hot.Migration
	hot.migrate(&dst, type_info_of(string), &src, type_info_of(f64), &m)
	defer hot.migration_destroy(&m)
	testing.expect_value(t, dst, "default")
	testing.expect_value(t, len(m.reset), 1)
	// enum with different values is not reinterpreted
	e1 := Fp_Enum_1.B
	e2 := Fp_Enum_2.C
	m2: hot.Migration
	hot.migrate(&e2, type_info_of(Fp_Enum_2), &e1, type_info_of(Fp_Enum_1), &m2)
	defer hot.migration_destroy(&m2)
	testing.expect_value(t, e2, Fp_Enum_2.C)
}

// ---------------------------------------------------------------------------
// Snapshots (what app.keep stores between loads)
// ---------------------------------------------------------------------------

@(test)
hot_snapshots_roundtrip :: proc(t: ^testing.T) {
	h := new(hot.Host)
	defer free(h)
	hot.host_init(h)
	testing.expect(t, hot.host_compatible(h))
	value := Fp_A{x = 3, y = 1.5}
	key := hot.keep_key("&value", type_info_of(Fp_A))
	testing.expectf(t, strings.contains(key, "Fp_A"), "%s", key)
	hot.snapshot_put(h, key, type_info_of(Fp_A), &value)
	value.x = 9
	hot.snapshot_put(h, key, type_info_of(Fp_A), &value) // replaces
	testing.expect_value(t, len(h.snapshots), 1)
	snap := hot.snapshot_find(h, key)
	testing.expect(t, snap != nil)
	got := (^Fp_A)(raw_data(snap.data))^
	testing.expect_value(t, got.x, 9)
	testing.expect(t, hot.snapshot_find(h, "&other|Fp_A") == nil)
	hot.snapshots_clear(h)
	delete(h.snapshots)
	delete(h.notes)
	testing.expect(t, !hot.host_compatible(nil))
	bad := h^
	bad.abi += 1
	testing.expect(t, !hot.host_compatible(&bad))
}

@(test)
hot_keep_is_a_noop_in_normal_builds :: proc(t: ^testing.T) {
	x := 5
	testing.expect(t, !vapp.keep(&x))
	testing.expect(t, !vapp.is_hot())
	testing.expect(t, vapp.hot_host() == nil)
	testing.expect_value(t, x, 5)
}

// ---------------------------------------------------------------------------
// Source scanning and watching
// ---------------------------------------------------------------------------

@(test)
hot_scan_imports_and_loads :: proc(t: ^testing.T) {
	cols := make(map[string]string)
	defer delete(cols)
	cols["vinland"] = "/repo"
	src := `package x
import "core:fmt"
import ui "vinland:vui"
import "../sibling"
import   game "vendor:raylib"
foreign import libc "system:c"
// import "commented/out"
/* import "also/out" /* nested */ */
s := "import \"in/a/string\""
r := ` + "`" + `import "raw"` + "`" + `
DATA :: #load("assets/logo.png")
TEXT :: #load("notes.txt", string)
myimport := 1
`
	refs := hot.scan_source_refs(src, "/repo/app", cols)
	defer {
		for r in refs {delete(r)}
		delete(refs)
	}
	want := []string{"/repo/vui", "/repo/sibling", "asset:/repo/app/assets/logo.png", "asset:/repo/app/notes.txt"}
	testing.expectf(t, len(refs) == len(want), "refs = %v", refs)
	for w in want {
		found := false
		for r in refs {
			if r == w {
				found = true
			}
		}
		testing.expectf(t, found, "missing %s in %v", w, refs)
	}
}

@(test)
hot_watcher_detects_real_changes_only :: proc(t: ^testing.T) {
	base := filepath.join({os.get_working_directory(context.temp_allocator) or_else ".", "build", "hot-unit-watch"}, context.temp_allocator) or_else "build/hot-unit-watch"
	_ = os.remove_all(base)
	pkg := filepath.join({base, "app"}, context.temp_allocator) or_else ""
	lib := filepath.join({base, "lib"}, context.temp_allocator) or_else ""
	_ = os.make_directory_all(pkg)
	_ = os.make_directory_all(lib)
	defer os.remove_all(base)
	main_file := filepath.join({pkg, "main.odin"}, context.temp_allocator) or_else ""
	lib_file := filepath.join({lib, "lib.odin"}, context.temp_allocator) or_else ""
	_ = os.write_entire_file(main_file, "package app\nimport \"../lib\"\nmain :: proc() {}\n")
	_ = os.write_entire_file(lib_file, "package lib\nX :: 1\n")
	_ = os.write_entire_file(filepath.join({pkg, "notes.md"}, context.temp_allocator) or_else "", "not source")

	cols := make(map[string]string)
	defer delete(cols)
	w: hot.Watcher
	hot.watcher_init(&w, {pkg}, cols)
	defer hot.watcher_destroy(&w)
	testing.expect_value(t, len(w.dirs), 2) // app + imported lib
	testing.expect_value(t, len(w.files), 2) // .odin only

	testing.expect_value(t, len(hot.watcher_scan(&w, context.temp_allocator)), 0)
	// same bytes, newer mtime: no change
	time.sleep(10 * time.Millisecond)
	_ = os.write_entire_file(lib_file, "package lib\nX :: 1\n")
	testing.expect_value(t, len(hot.watcher_scan(&w, context.temp_allocator)), 0)
	// real edit in the imported package
	_ = os.write_entire_file(lib_file, "package lib\nX :: 2\n")
	ch := hot.watcher_scan(&w, context.temp_allocator)
	testing.expect_value(t, len(ch), 1)
	// non-source files in a package dir are ignored
	_ = os.write_entire_file(filepath.join({pkg, "notes.md"}, context.temp_allocator) or_else "", "edited")
	testing.expect_value(t, len(hot.watcher_scan(&w, context.temp_allocator)), 0)
	// new file + deleted file are changes
	extra := filepath.join({pkg, "extra.odin"}, context.temp_allocator) or_else ""
	_ = os.write_entire_file(extra, "package app\n")
	testing.expect_value(t, len(hot.watcher_scan(&w, context.temp_allocator)), 1)
	_ = os.remove(extra)
	testing.expect_value(t, len(hot.watcher_scan(&w, context.temp_allocator)), 1)
	// dropping the import stops watching lib
	_ = os.write_entire_file(main_file, "package app\nmain :: proc() {}\n")
	testing.expect_value(t, len(hot.watcher_scan(&w, context.temp_allocator)), 1)
	testing.expect_value(t, len(w.dirs), 1)
}

@(test)
hot_editor_temp_names :: proc(t: ^testing.T) {
	for n in ([]string{"4913", "main.odin~", ".main.odin.swp", ".#main.odin", "x.tmp"}) {
		testing.expectf(t, hot.is_editor_temp(n), "%s", n)
	}
	testing.expect(t, !hot.is_editor_temp("main.odin"))
}

// ---------------------------------------------------------------------------
// Compiler output and protocol
// ---------------------------------------------------------------------------

@(test)
hot_parse_odin_errors :: proc(t: ^testing.T) {
	out := `/home/u/app/main.odin(12:5) Error: Undeclared name: foo
	foo()
	^~^
/home/u/app/other.odin(3:1) Syntax Error: Expected '}'
`
	e, ok := hot.parse_build_output(out)
	testing.expect(t, ok)
	testing.expect_value(t, e.file, "/home/u/app/main.odin")
	testing.expect_value(t, e.line, 12)
	testing.expect_value(t, e.column, 5)
	testing.expect_value(t, e.message, "Undeclared name: foo")
	testing.expect_value(t, e.count, 2)
	_, ok2 := hot.parse_build_output("ld: cannot find -lfoo\n")
	testing.expect(t, !ok2)
	long := strings.repeat("x\n", 100, context.temp_allocator)
	testing.expect(t, strings.count(hot.trim_output(long), "\n") < 40)
}

@(test)
hot_protocol_messages :: proc(t: ^testing.T) {
	m := hot.parse_msg("reload 4 1012.5 /tmp/my app/build/app_4.so")
	testing.expect_value(t, m.kind, hot.Msg_Kind.Reload)
	testing.expect_value(t, m.gen, 4)
	testing.expect_value(t, m.build_ms, 1012.5)
	testing.expect_value(t, m.path, "/tmp/my app/build/app_4.so")
	e := hot.parse_msg("error 5 120")
	testing.expect_value(t, e.kind, hot.Msg_Kind.Error)
	testing.expect_value(t, e.payload, 120)
	testing.expect_value(t, hot.parse_msg("building 6").kind, hot.Msg_Kind.Building)
	testing.expect_value(t, hot.parse_msg("quit").kind, hot.Msg_Kind.Quit)
	testing.expect_value(t, hot.parse_msg("").kind, hot.Msg_Kind.Unknown)
	testing.expect_value(t, hot.parse_msg("reload 1").kind, hot.Msg_Kind.Unknown)
	testing.expect_value(t, hot.parse_msg("error 1 99999999999").kind, hot.Msg_Kind.Unknown) // oversized payload
	testing.expect_value(t, hot.parse_msg("bogus 1 2").kind, hot.Msg_Kind.Unknown)
	src := hot.entry_source("vui_hot_app:demo", context.temp_allocator)
	testing.expect(t, strings.contains(src, "import user \"vui_hot_app:demo\""))
	testing.expect(t, strings.contains(src, hot.ENTRY_SYMBOL))
}

// ---------------------------------------------------------------------------
// Ids and registration survive a reload
// ---------------------------------------------------------------------------

@(test)
hot_ids_do_not_depend_on_string_addresses :: proc(t: ^testing.T) {
	ctx := setup()
	defer teardown(ctx)
	ids: [2]ui.Id
	for pass in 0 ..< 2 {
		// the same source location, but the path string lives at a different address (as it
		// does in a newly loaded build)
		path := strings.clone("/src/app/main.odin", context.temp_allocator)
		ui.begin_frame(ctx, {}, {400, 300}, 1, ctx.time + 1.0 / 60)
		ui.open("p-2", loc = {file_path = path, line = 10, column = 3})
		ids[pass] = ui.current_id()
		ui.close()
		ui.end_frame(ctx)
	}
	testing.expect_value(t, ids[0], ids[1])
}

@(test)
hot_registration_is_idempotent :: proc(t: ^testing.T) {
	ctx := setup()
	defer teardown(ctx)
	faces := len(ctx.fonts.faces)
	icon_paths := []ui.Icon_Path{{d = "M0 0L10 0L10 10Z"}}
	a := ui.icon_register(ctx, "tri", {10, 10}, icon_paths)
	b := ui.icon_register(ctx, "tri", {10, 10}, icon_paths)
	testing.expect_value(t, a, b)
	testing.expect_value(t, len(ctx.icons), 1)
	data := ctx.fonts.faces[0].data
	id, ok := ui.font_register(&ctx.fonts, ctx.fonts.faces[0].family, data, ctx.fonts.faces[0].weight, ctx.fonts.faces[0].italic)
	testing.expect(t, ok)
	testing.expect_value(t, int(id), 0)
	testing.expect_value(t, len(ctx.fonts.faces), faces)
	pix := make([]u8, 4 * 4 * 4, context.temp_allocator)
	img := ui.image_register(ctx, pix, 4, 4)
	ui.image_name(ctx, "demo", img)
	testing.expect_value(t, ui.image_by_name(ctx, "demo"), img)
	testing.expect_value(t, ui.image_by_name(ctx, "missing"), ui.Image_Id(0))
}

package vui_app

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import vui ".."
import hot "../hot"

// An app described as callbacks. `run` drives it the traditional way (a normal `odin build`
// gives a normal executable) and, when the same package is started by `vui-hot`, keeps the
// window, GPU device, ui.Context and kept globals alive while the code is swapped underneath.
//
//     State :: struct { count: int }
//     s: State
//
//     main :: proc() {
//         app.run({
//             config = {title = "Counter", size = {480, 320}},
//             setup  = proc(a: ^app.App) { fonts.register(a.ctx); app.keep(&s) },
//             frame  = proc(a: ^app.App) {
//                 if ui.button(fmt.tprintf("Clicked %d times", s.count), "rounded-lg bg-sky-600 px-4 py-2 text-white") {
//                     s.count += 1
//                 }
//             },
//         })
//     }
//
//     odin build my_app                 # normal executable, no hot reload code runs
//     vui-hot my_app                    # edit, save: the window updates, `s.count` survives
Program :: struct {
	config:   Config,
	// Every load: the first start and after each hot reload. Register fonts, icons, images and
	// lookup tables here (vui's register procs are idempotent by name), call `keep` on the
	// globals that must survive a reload, and set `a.on_command` / `a.on_event`.
	setup:    proc(a: ^App),
	// Once per window: initial state. Skipped after a hot reload (the kept state is restored).
	init:     proc(a: ^App),
	// One frame of UI. Called between `next_frame` and `end_frame`.
	frame:    proc(a: ^App),
	// The app is exiting (not called on a hot reload).
	shutdown: proc(a: ^App),
}

// Runs a Program to completion. Returns false when the window could not be created.
run :: proc(p: Program) -> bool {
	if g_hot != nil {
		return hot_run(p)
	}
	ctx := new(vui.Context)
	vui.init(ctx)
	a := new(App)
	ok := init(a, p.config, ctx)
	if ok {
		if p.setup != nil {
			p.setup(a)
		}
		if p.init != nil {
			p.init(a)
		}
		for next_frame(a) {
			if p.frame != nil {
				p.frame(a)
			}
			end_frame(a)
		}
		if p.shutdown != nil {
			p.shutdown(a)
		}
		shutdown(a)
	}
	vui.destroy(ctx)
	free(ctx)
	free(a)
	return ok
}

// Keeps a global across hot reloads. Call it from `Program.setup` (every load) with the
// address of a package-level variable. The first load registers it; later loads copy the value
// the previous build had into it, then carry it forward again on the next reload.
//
// When the type changed between builds the value is migrated rather than dropped: struct
// fields are matched by name (recursively), fixed arrays element by element, integers and floats
// converted when only their size changed; new fields keep their default, removed fields are
// dropped and fields whose type changed are reset. Returns true when a previous value was
// restored (fully or partly). In a normal build it does nothing and returns false.
//
// Kept values are copied bytewise: heap pointers inside them (dynamic arrays, maps, strings)
// stay valid, but a procedure value stored in kept state keeps calling the old build's code
// until you assign it again. Keep a pointer (`s: ^State`) instead of a value when another thread
// holds the address of the state.
keep :: proc(ptr: ^$T, key := #caller_expression(ptr)) -> (restored: bool) {
	h := g_hot
	if h == nil || ptr == nil {
		return false
	}
	info := type_info_of(T)
	k := hot.keep_key(key, info, context.allocator)
	for &slot in g_keeps {
		if slot.key == k {
			slot.ptr = ptr
			delete(k)
			return false
		}
	}
	append(&g_keeps, Keep_Slot{key = k, ptr = ptr, info = info})
	snap := hot.snapshot_find(h, k)
	if snap == nil {
		return false
	}
	m: hot.Migration
	hot.migrate(ptr, info, raw_data(snap.data), snap.info, &m)
	if !m.exact {
		note := fmt.aprintf("%s %s", key, hot.migration_summary(&m))
		append(&g_notes, note)
		fmt.eprintfln("vui-hot: %s", note)
	}
	hot.migration_destroy(&m)
	return true
}

// True when the process runs under vui-hot.
is_hot :: proc() -> bool {
	return g_hot != nil
}

// The runner's shared state (nil in a normal build).
hot_host :: proc() -> ^hot.Host {
	return g_hot
}

// ---------------------------------------------------------------------------
// Hot runtime (only reached through vui-hot)
// ---------------------------------------------------------------------------

Keep_Slot :: struct {
	key:  string,
	ptr:  rawptr,
	info: ^runtime.Type_Info,
}

// Framework state parked in Host.persist between two builds. The fingerprint must stay the
// first field: a newer build reads it before trusting anything else.
Hot_Persist :: struct {
	fingerprint: u64,
	app:         ^App,
	ctx:         ^vui.Context,
	shutdown:    proc(a: ^App), // user shutdown of the build that owns the state
	wake_event:  u32,
}

// Package globals are per library instance: every hot build starts with fresh ones.
@(private)
g_hot: ^hot.Host
@(private)
g_hot_result: hot.Result
@(private)
g_in_run: bool
@(private)
g_keeps: [dynamic]Keep_Slot
@(private)
g_notes: [dynamic]string
@(private)
g_overlay := true
@(private)
g_persist_fp: u64

// Called by the entry vui-hot generates (`vui_hot_entry`); `main` is the app's own main.
hot_entry :: proc(host: ^hot.Host, op: hot.Op, main: proc()) -> hot.Result {
	if !hot.host_compatible(host) {
		fmt.eprintln("vui-hot: this build of vui/hot does not match the running vui-hot (rebuild and restart vui-hot)")
		return .Failed
	}
	g_hot = host
	context.allocator = host.allocator
	if host.temp_allocator.procedure != nil {
		context.temp_allocator = host.temp_allocator
	}
	switch op {
	case .Shutdown:
		if pr := (^Hot_Persist)(host.persist); pr != nil {
			hot_teardown(pr, host)
		}
		hot_release_thread_locals()
		return .Quit
	case .Run:
		os.args = host.args
		v := os.get_env("VUI_HOT_OVERLAY", context.temp_allocator)
		g_overlay = v != "0" && v != "false"
		g_hot_result = .Quit
		g_in_run = false
		clear(&g_keeps)
		clear(&g_notes)
		main()
		reload := hot.reload_requested(host) && !hot.quit_requested(host)
		if !g_in_run && g_hot_result != .Incompatible {
			// A classic `for app.next_frame` loop: next_frame returned false for the reload and the
			// app's own defers closed the window. Kept globals still carry over; the next build
			// starts cold.
			g_hot_result = reload ? .Reload : .Quit
		}
		if g_hot_result == .Reload {
			for slot in g_keeps {
				hot.snapshot_put(host, slot.key, slot.info, slot.ptr)
			}
			hot_release_thread_locals()
		}
		return g_hot_result
	}
	return .Failed
}

// app.init under vui-hot without app.run (a classic `for app.next_frame` loop). Returns false
// when a window parked by an app.run build cannot be closed by this build.
@(private)
hot_plain_init :: proc(a: ^App) -> bool {
	h := g_hot
	if g_in_run {
		return true
	}
	if pr := (^Hot_Persist)(h.persist); pr != nil {
		// the previous build used app.run and parked its window; this build switched to a classic
		// loop. Close the parked window first (needs the same layout to do it from here).
		if pr.fingerprint != persist_fingerprint() {
			g_hot_result = .Incompatible
			return false
		}
		hot_teardown(pr, h)
	}
	if a.cfg.app_id == "" {
		a.cfg.app_id = h.app_name
	}
	sync.mutex_lock(&h.mutex)
	h.cold_starts += 1
	if h.generation > 1 {
		h.reloaded_ns = 0
	}
	sync.mutex_unlock(&h.mutex)
	return true
}

// This build's own thread-local arenas on the main thread (the runtime temp allocator and
// core:os's private 4 MB scratch arenas) would otherwise stay allocated for the rest of the
// session, one set per build: measured +4.2 MB per reload before this. They re-create
// themselves lazily if this build ever runs again (a failed load resumes it).
@(private)
hot_release_thread_locals :: proc() {
	runtime.run_thread_local_cleaners()
	runtime.default_temp_allocator_destroy(&runtime.global_default_temp_allocator_data)
}

@(private)
persist_fingerprint :: proc() -> u64 {
	if g_persist_fp == 0 {
		g_persist_fp = hot.fingerprint(type_info_of(Hot_Persist)) ~ u64(hot.HOST_ABI)
	}
	return g_persist_fp
}

@(private)
hot_wake_proc :: proc "c" (data: rawptr) {
	e: sdl.Event
	e.type = sdl.EventType(u32(uintptr(data)))
	_ = sdl.PushEvent(&e)
}

@(private)
hot_run :: proc(p: Program) -> bool {
	h := g_hot
	g_in_run = true
	fp := persist_fingerprint()
	pr := (^Hot_Persist)(h.persist)
	if pr != nil && pr.fingerprint != fp {
		// App / Context / renderer layout changed (an edit inside vui itself): the old build must
		// close its window before this one opens a new one.
		g_hot_result = .Incompatible
		return false
	}
	cold := pr == nil
	if cold {
		ctx := new(vui.Context)
		vui.init(ctx)
		a := new(App)
		cfg := p.config
		if cfg.app_id == "" {
			cfg.app_id = h.app_name
		}
		if !init(a, cfg, ctx) {
			vui.destroy(ctx)
			free(ctx)
			free(a)
			g_hot_result = .Failed
			return false
		}
		pr = new(Hot_Persist)
		pr^ = Hot_Persist{fingerprint = fp, app = a, ctx = ctx, wake_event = a.user_event}
		h.persist = pr
		sync.mutex_lock(&h.mutex)
		h.cold_starts += 1
		sync.mutex_unlock(&h.mutex)
	} else {
		vui.make_current(pr.ctx)
		// Package globals of the previous build are not shared: vendor:OpenGL keeps its function
		// pointers in globals, so a GL window must load them again in this build. The context
		// itself is still current on this thread; making it current again would make some
		// drivers (Mesa llvmpipe) allocate fresh back buffers on every reload.
		if pr.app.backend == .GL {
			gl.load_up_to(3, 3, sdl.gl_set_proc_address)
		}
		// Hooks pointing into the previous build: rebind framework ones, let setup set the app's.
		pr.ctx.clipboard_get = clipboard_get
		pr.ctx.clipboard_set = clipboard_set
		pr.app.on_command = nil
		pr.app.on_event = nil
	}
	a := pr.app
	pr.shutdown = p.shutdown
	hot.set_wake(h, hot_wake_proc, rawptr(uintptr(pr.wake_event)))
	if p.setup != nil {
		p.setup(a)
	}
	if !cold {
		// class sets were parsed by the previous build's code: re-parse once with this build's
		// (an edit to the utility parser shows up immediately)
		vui.theme_changed()
	}
	hot.host_set_notes(h, g_notes[:])
	for n in g_notes {
		delete(n)
	}
	clear(&g_notes)
	if cold && p.init != nil {
		p.init(a)
	}
	if h.generation > 1 {
		sync.mutex_lock(&h.mutex)
		h.reloaded_ns = i64(sdl.GetTicksNS())
		sync.mutex_unlock(&h.mutex)
	}
	// make the class cache and layout see the new code at once
	a.dirty_frames = max(a.dirty_frames, 3)
	for next_frame(a) {
		if p.frame != nil {
			p.frame(a)
		}
		hot_overlay(a)
		end_frame(a)
	}
	if a.running && hot.reload_requested(h) && !hot.quit_requested(h) {
		g_hot_result = .Reload // everything stays parked in h.persist
		return true
	}
	hot_teardown(pr, h)
	g_hot_result = .Quit
	return true
}

@(private)
hot_teardown :: proc(pr: ^Hot_Persist, h: ^hot.Host) {
	hot.set_wake(h, nil, nil)
	if pr.shutdown != nil {
		pr.shutdown(pr.app)
	}
	shutdown(pr.app)
	vui.destroy(pr.ctx)
	free(pr.ctx)
	free(pr.app)
	free(pr)
	h.persist = nil
}

// Status as the control server's `info` reports it (`"hot":{...}`); "null" outside vui-hot.
hot_info_json :: proc(sb: ^strings.Builder) {
	h := g_hot
	if h == nil {
		strings.write_string(sb, "null")
		return
	}
	sync.mutex_lock(&h.mutex)
	defer sync.mutex_unlock(&h.mutex)
	fmt.sbprintf(sb, `{{"pid":%d,"generation":%d,"reloads":%d,"cold_starts":%d,"status":"%v","build_ms":%.1f,"swap_ms":%.2f,"error_gen":%d,"kept":%d,"error":`, os.get_pid(), h.generation, h.reloads, h.cold_starts, h.status, h.build_ms, h.swap_ms, h.error_gen, len(g_keeps))
	vui.json_str(sb, h.error_text)
	strings.write_string(sb, `,"changed":`)
	vui.json_str(sb, h.changed)
	strings.write_string(sb, `,"notes":[`)
	for n, i in h.notes {
		if i > 0 {
			strings.write_byte(sb, ',')
		}
		vui.json_str(sb, n)
	}
	strings.write_string(sb, "]}")
}

TOAST_NS :: 1_600_000_000

// Build status drawn over the app while it runs under vui-hot: a pill while rebuilding, the
// compiler output when the build failed (the previous build keeps running underneath), and a
// short "reloaded" toast. VUI_HOT_OVERLAY=0 hides it.
@(private)
hot_overlay :: proc(a: ^App) {
	h := g_hot
	if h == nil || !g_overlay {
		return
	}
	sync.mutex_lock(&h.mutex)
	status := h.status
	err := strings.clone(h.error_text, context.temp_allocator)
	gen := h.generation
	egen := h.error_gen
	reloaded := h.reloaded_ns
	build_ms := h.build_ms
	swap_ms := h.swap_ms
	sync.mutex_unlock(&h.mutex)

	switch status {
	case .Error:
		if vui.div("fixed left-3 right-3 bottom-3 z-50 flex flex-col gap-2 rounded-lg bg-red-950/95 p-4 shadow-2xl ring-1 ring-red-400/50 max-h-[60%] overflow-hidden") {
			if vui.div("flex items-center gap-2") {
				vui.text(fmt.tprintf("Build #%d failed", egen), "text-sm font-semibold text-red-100")
				vui.text(fmt.tprintf("still running build #%d · fix and save to retry", gen), "text-xs text-red-300")
			}
			vui.text(err, "font-mono text-xs/5 text-red-50 whitespace-pre-wrap")
		}
	case .Building:
		hot_pill("Rebuilding…", "bg-gray-900/90 text-gray-100 ring-white/15")
	case .Idle:
		if reloaded != 0 && i64(sdl.GetTicksNS()) - reloaded < TOAST_NS {
			hot_pill(fmt.tprintf("Reloaded #%d · build %.2f s · swap %.0f ms", gen, build_ms / 1000, swap_ms), "bg-emerald-950/90 text-emerald-100 ring-emerald-400/30")
		}
	}
}

@(private)
hot_pill :: proc(label: string, colors: string) {
	if vui.div(strings.concatenate({"fixed top-3 right-3 z-50 pointer-events-none rounded-full px-3 py-1 shadow-lg ring-1 ", colors}, context.temp_allocator)) {
		vui.text(label, "text-xs font-medium")
	}
}

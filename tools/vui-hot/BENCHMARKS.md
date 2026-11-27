# vui-hot: design notes and benchmarks

Hot reload is an optional development mode. A normal `odin build` produces the same executable
it always did: `app.run` is a plain loop, `app.keep` returns immediately, and `next_frame` pays one
nil check.

## How it works

```
vui-hot (supervisor)                       vui-hot --child (runner, owns the window)
  poll watched files (stat, no alloc)        dlopen(app_N.so) -> vui_hot_entry(host, .Run)
  content-hash changed files                   app main() -> app.run(Program)
  odin build entry/ -build-mode:dll  ----->     loop: next_frame sees host.reload -> return .Reload
  "reload N <ms> <path>" on runner stdin       save app.keep globals into host snapshots
  restart runner on crash / roll back        dlopen(app_N+1.so) -> vui_hot_entry(host, .Run)
                                               resume: same App, Context, window, GPU device
                                               setup() again, keep() restores + migrates
```

* **Generated entry package.** vui-hot writes `build/hot/<pkg>/entry/entry.odin`, which imports
  the app package and exports `vui_hot_entry`. The app keeps a normal `main`; nothing hot-specific
  is compiled into a normal build. (Odin runs a library's `main` from its init section, so the
  entry package itself has none.)
* **What persists.** `Host` (runner memory) holds the framework's parked state: `App` and
  `ui.Context` on the heap at stable addresses, so the control-server thread's pointers stay valid.
  Its first field is a structural fingerprint of `Hot_Persist` (and so of `App` and `Context`);
  a build with another layout returns `Incompatible`, the old build closes the window with its
  own code and the new one opens a fresh one in the same process.
* **Kept globals.** `app.keep(&g)` registers `g` under `"<expression>|<package.Type>"` (from
  `#caller_expression`). On hand-off its bytes go to the host; the next build copies them back,
  or migrates them when the type fingerprint differs (struct fields by name, recursively; fixed
  arrays element-wise; integer/float size changes converted when the value fits; everything else
  reset and reported).
* **Old builds stay mapped.** Live state points into them: string literals, procedure values,
  type info, embedded font data. Unloading would leave those dangling, which is the most common
  hot-reload crash in C/Odin setups. Instead each build releases what it owns on hand-off (its
  runtime temp arena and `core:os` scratch arenas: measured +4.2 MB per reload before), and the
  runner marks the old library's pages `MADV_COLD` (Linux) so the kernel drops them first.
* **Allocators.** While a build runs, `context.allocator` is the runner's heap allocator and
  `context.temp_allocator` the runner's main-thread arena, so memory allocated by one build and
  freed by another always goes through code that is never unloaded, and there is one temp arena
  for the whole session.
* **Package globals are per build.** Each library has its own copy of every global. Hence
  idempotent registration (`font_register`, `icon_register`, `materials.register` dedupe by
  name), re-loading `vendor:OpenGL` function pointers on resume, re-parsing class strings, and
  element ids that hash the caller's *path bytes* rather than the path string's address (each
  build has its own copy of the literal; hashing the address reset every scroll offset and focus).

## Results

Linux, 16 cores, Odin dev-2026-11, everything sandboxed (`VUI_HIDDEN=1`, llvmpipe), builds on
disk. `python3 tests/hot/bench_hot.py --runs 12 --poll 50 100 250` and `--app counter`.
"Save to live" is measured from the atomic rename of the edited file until the control port
reports the new generation.

### Showroom (12 packages, 82 watched files, 13 MB debug library)

| | median | p90 |
|---|---|---|
| save -> new code live, `--poll 50` | 1.264 s | 1.287 s |
| save -> new code live, `--poll 100` (default) | 1.424 s | 1.503 s |
| save -> new code live, `--poll 250` | 1.707 s | 1.720 s |
| of which: `odin build -build-mode:dll` | 1.16 to 1.25 s | |
| of which: swap (dlopen + resume + setup) | **2.1 ms** | 2.5 ms |
| traditional: `odin build` + start + first answer | 1.348 s | 1.351 s |

The compile dominates. Hot reload is not faster than a relaunch for a cold app; what it buys is
that the relaunch time is all you pay: the window stays where it is and the page, scroll offsets,
form contents, dark mode and kept state are already there. A library build is about 0.15 s slower
than an executable build (position-independent code, the extra entry package). `-o:none` saves
about 0.2 s per build at the cost of debug info:

| `odin build showroom` | median |
|---|---|
| `-debug` | 1.01 s |
| `-debug -use-separate-modules` | 1.01 s (already the default: 122 modules) |
| `-o:none` | 0.83 s |
| `-o:none -thread-count:16` | 0.82 s |

### Counter example

| | median |
|---|---|
| save -> new code live (`--poll 100`) | 1.205 s |
| swap | 2.1 ms |
| traditional rebuild + relaunch | 0.987 s |

### Watcher cost (idle, no edits)

| `--poll` | CPU over 10 s | share of one core |
|---|---|---|
| 50 ms | 80 ms | 0.8% |
| 100 ms (default) | 40 ms | 0.4% |
| 250 ms | 20 ms | 0.2% |

Before the allocation-free scan (core:os `File_Info` with a cloned full path per file, and a
directory listing per package per poll) the default cost 1.5 to 1.6%. A directory is now listed
only when its own mtime moves (a file created, deleted or renamed into it, which is how editors
save atomically); otherwise each poll is one `stat` per directory and per file.
`--poll 100` is the default: 0.16 s slower than 50 ms on average for half the wakeups.

### Memory across reloads (runner process)

| | start | after 12 reloads | after 24 reloads |
|---|---|---|---|
| showroom anonymous | 32 MB | 76 MB | 80 MB |
| showroom file-backed (reclaimable) | 142 MB | 196 MB | 233 MB |
| counter anonymous | 35 MB | 49 MB | |

Anonymous growth flattens: the heap in use stays constant for the counter
(`mallinfo2().uordblks` 39.3 MB after every reload), the rest is freed memory the allocator
keeps for reuse plus each library's relocated data pages (about 0.36 MB per showroom build).
File-backed pages are old library code and read-only data: clean, marked cold, and dropped by the
kernel under memory pressure. Two things that made memory grow and are fixed:

* each build's runtime temp arena and `core:os` scratch arenas (4.2 MB per reload) are released
  on hand-off (`runtime.run_thread_local_cleaners`);
* making the GL context current again on resume made Mesa allocate new buffers; it is not needed
  (the context stays current on the thread).

On tmpfs (`/tmp` on most distributions) a deleted but mapped library cannot be dropped at all;
vui-hot prints a note when `--out` is on tmpfs. `MADV_PAGEOUT` was tried and rejected: it cost
about 20 ms per swap for no lasting gain over `MADV_COLD`.

### Reliability matrix

`python3 tests/hot/test_hot.py`: 37 end-to-end cases on sandboxed apps (Linux and macOS CI), including state kept
across 6+ reloads in one process, scroll offsets preserved, struct fields added / removed /
retyped / resized, new files and newly imported packages, `#load` assets, no rebuild for a
no-op save, bursts of saves coalesced, a stale build cancelled mid-compile, App layout changes
(cold restart in the same process with kept state restored), a classic `next_frame` loop,
`-define` and app-argument pass-through, syntax/type errors with the overlay, a deleted file,
crashes right after a reload (rollback) and later (restart, crash-loop stop), Ctrl+C and SIGKILL
of the supervisor (no orphan window), a vui/hot ABI mismatch, a mismatched vui checkout, bad
arguments, and that a normal `odin build` of the same package reports no hot state at all.
`odin test tests` adds unit tests for fingerprints, migration, snapshots, the import / `#load`
scanner, the watcher, compiler-output parsing and the runner protocol.

## Research notes

* Keeping old libraries loaded rather than unloading them follows Karl Zylinski's Odin hot-reload
  template, which unloads only on a full reset because the library "can contain stored info such
  as string literals"; the same point appears in the Handmade Network discussions of hot-loaded
  DLL drawbacks.
* cr.h (fungos/cr) inspired the rollback: when a freshly loaded binary crashes, go back to the
  previous working one. vui-hot does it at process level (the supervisor restarts the runner on
  the previous build) instead of with signal handlers and `setjmp`, which conflict with sanitizers
  and leave the process in an unknown state.
* cr.h copies the old library's global sections into the new one. vui-hot copies only what the
  app opts into with `app.keep`, per value and with a type fingerprint, because a blind section
  copy would also carry pointers into the old library's own globals.
* Polling instead of inotify / FSEvents / ReadDirectoryChangesW: one code path on every OS, no
  watch limits (inotify's default `max_user_watches`), and it naturally coalesces the several
  events an atomic save produces (gopls' poll watcher makes the same argument).

Sources: https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template,
https://handmade.network/forums/t/6984, https://github.com/fungos/cr,
https://fungos.github.io/cr-simple-c-hot-reload/,
https://go.googlesource.com/tools/+/HEAD/gopls/internal/filewatcher/poll_watcher.go

## Diagnostics

* `VUI_HOT_TRACE_ALLOC=1` (or `=<bytes>`): the runner logs every app allocation of at least
  16 KB (or `<bytes>`) with its source location.
* `vui-ctl info` -> `hot`: `pid`, `generation`, `reloads`, `cold_starts`, `status`, `error`,
  `build_ms`, `swap_ms`, `kept`, `changed`, `notes`.

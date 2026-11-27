#+build linux
package vui_hot_tool

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/linux"

DLL_EXT :: ".so"

// A runner that dies mid-write must not kill the supervisor with SIGPIPE.
platform_init :: proc() {
	libc.signal(13, transmute(proc "c" (i32))libc.SIG_IGN) // SIGPIPE
}

// Exit statuses that are probably crash signals (Odin reports a signal number as the code).
platform_signal_name :: proc(st: os.Process_State) -> string {
	if st.success {
		return ""
	}
	switch st.exit_code {
	case 4:
		return "SIGILL, an Odin panic or assert"
	case 5:
		return "SIGTRAP, an Odin panic or assert"
	case 6:
		return "SIGABRT"
	case 7:
		return "SIGBUS"
	case 8:
		return "SIGFPE"
	case 9:
		return "SIGKILL"
	case 11:
		return "SIGSEGV"
	}
	return ""
}

// Old builds stay mapped (live state may point at their string literals, procedures and type
// info) but are cold: mark their pages for reclaim first (MADV_COLD: no I/O now; under memory
// pressure the kernel drops them before anything the app uses). Clean file pages are simply
// dropped and fault back in from the (still referenced) file if anything touches them again.
platform_release_library :: proc(path: string) {
	maps, err := os.read_entire_file("/proc/self/maps", context.temp_allocator)
	if err != nil {
		return
	}
	rest := string(maps)
	for line in strings.split_lines_iterator(&rest) {
		if !strings.contains(line, path) { // also matches "(deleted)" mappings
			continue
		}
		dash := strings.index_byte(line, '-')
		sp := strings.index_byte(line, ' ')
		if dash <= 0 || sp <= dash {
			continue
		}
		lo, ok1 := strconv.parse_u64_of_base(line[:dash], 16)
		hi, ok2 := strconv.parse_u64_of_base(line[dash + 1:sp], 16)
		if !ok1 || !ok2 || hi <= lo {
			continue
		}
		_ = linux.madvise(rawptr(uintptr(lo)), uint(hi - lo), .COLD)
	}
}

// Old builds stay mapped until the app exits. On tmpfs (/tmp on most distros) a mapped,
// deleted library keeps its pages in RAM with no disk to drop them to.
platform_check_out_dir :: proc(dir: string) {
	cs := strings.clone_to_cstring(dir, context.temp_allocator)
	st: linux.Stat_FS
	if linux.statfs(cs, &st) == .NONE && st.type == .TMPFS_MAGIC {
		fmt.eprintfln("vui-hot: note: %s is on tmpfs; every reload keeps the previous build in RAM until the app exits (use --out on a disk path to let the kernel drop them)", dir)
	}
}

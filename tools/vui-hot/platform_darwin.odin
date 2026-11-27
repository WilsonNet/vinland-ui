#+build darwin
package vui_hot_tool

import "core:c/libc"
import "core:os"

DLL_EXT :: ".dylib"

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
	case 8:
		return "SIGFPE"
	case 9:
		return "SIGKILL"
	case 10:
		return "SIGBUS"
	case 11:
		return "SIGSEGV"
	}
	return ""
}

// Old builds stay mapped; macOS reclaims their clean pages under pressure on its own.
platform_release_library :: proc(path: string) {}

platform_check_out_dir :: proc(dir: string) {}

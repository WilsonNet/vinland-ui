#+build !linux
#+build !darwin
package vui_hot_tool

import "core:os"

DLL_EXT :: ".dll"

platform_init :: proc() {}

// Windows reports exception codes (e.g. 0xC0000005) instead of signals.
platform_signal_name :: proc(st: os.Process_State) -> string {
	if u32(st.exit_code) == 0xC0000005 {
		return "access violation"
	}
	return ""
}

platform_release_library :: proc(path: string) {}

platform_check_out_dir :: proc(dir: string) {}

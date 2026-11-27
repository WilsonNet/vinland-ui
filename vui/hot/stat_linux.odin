#+build linux
package vui_hot

import "core:sys/linux"

// stat(2) without allocating (core:os builds a File_Info with a cloned full path per call).
// The watcher calls this for every watched file on every poll.
path_stamp :: proc(path: string) -> (size: i64, mtime: i64, is_dir: bool, ok: bool) {
	buf: [4096]u8
	if len(path) >= len(buf) {
		return path_stamp_os(path)
	}
	copy(buf[:], path)
	buf[len(path)] = 0
	st: linux.Stat
	if linux.stat(cstring(&buf[0]), &st) != .NONE {
		return
	}
	return i64(st.size), i64(st.mtime.time_sec) * 1_000_000_000 + i64(st.mtime.time_nsec), linux.S_ISDIR(st.mode), true
}

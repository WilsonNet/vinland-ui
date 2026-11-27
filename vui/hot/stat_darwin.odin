#+build darwin
package vui_hot

import "core:sys/posix"

// stat(2) without allocating (core:os builds a File_Info with a cloned full path per call).
// The watcher calls this for every watched file on every poll.
path_stamp :: proc(path: string) -> (size: i64, mtime: i64, is_dir: bool, ok: bool) {
	buf: [1024]u8
	if len(path) >= len(buf) {
		return path_stamp_os(path)
	}
	copy(buf[:], path)
	buf[len(path)] = 0
	st: posix.stat_t
	if posix.stat(cstring(&buf[0]), &st) != .OK {
		return
	}
	return i64(st.st_size), i64(st.st_mtim.tv_sec) * 1_000_000_000 + i64(st.st_mtim.tv_nsec), posix.S_ISDIR(st.st_mode), true
}

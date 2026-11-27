#+build !linux
#+build !darwin
package vui_hot

path_stamp :: proc(path: string) -> (size: i64, mtime: i64, is_dir: bool, ok: bool) {
	return path_stamp_os(path)
}

#+build !js
package vui

import "core:fmt"
import "core:os"

// Loads a JSON theme file and merges it into t (see theme_apply_json for the format).
theme_load_json :: proc(t: ^Theme, path: string) -> (err: string) {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return fmt.tprintf("cannot read %s", path)
	}
	return theme_apply_json(t, data)
}


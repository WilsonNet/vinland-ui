#+build darwin
package vui_gl

import "core:dynlib"

@(private, rodata)
GL_LIBRARY_PATHS := []string{"/System/Library/Frameworks/OpenGL.framework/OpenGL"}

@(private)
gl_library_paths :: proc() -> []string {
	return GL_LIBRARY_PATHS
}

@(private)
gl_lookup :: proc(lib: dynlib.Library, name: string) -> rawptr {
	ptr, _ := dynlib.symbol_address(lib, name)
	return ptr
}

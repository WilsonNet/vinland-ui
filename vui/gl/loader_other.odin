#+build !darwin
#+build !linux
package vui_gl

import "core:dynlib"
import "core:strings"

@(private, rodata)
GL_LIBRARY_PATHS := []string{"opengl32.dll"}

@(private)
gl_library_paths :: proc() -> []string {
	return GL_LIBRARY_PATHS
}

@(private)
Get_Proc :: #type proc "c" (name: cstring) -> rawptr

@(private)
gl_lookup :: proc(lib: dynlib.Library, name: string) -> rawptr {
	// Windows: GL > 1.1 entry points only come from wglGetProcAddress.
	gpa, ok := dynlib.symbol_address(lib, "wglGetProcAddress")
	if ok && gpa != nil {
		f := cast(Get_Proc)gpa
		if p := f(strings.clone_to_cstring(name, context.temp_allocator)); p != nil {
			return p
		}
	}
	ptr, _ := dynlib.symbol_address(lib, name)
	return ptr
}

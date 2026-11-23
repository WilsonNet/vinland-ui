#+build !linux
#+build !darwin
package vui_app

import "core:mem"
import sdl "vendor:sdl3"

@(private)
platform_prepare_init :: proc(app: ^App) {
}

@(private)
platform_create_gpu_device :: proc(backend_env: string) -> ^sdl.GPUDevice {
	switch backend_env {
	case "vulkan":
		return sdl.CreateGPUDevice({.SPIRV}, false, "vulkan")
	case "metal":
		return sdl.CreateGPUDevice({.MSL}, false, "metal")
	case:
		return sdl.CreateGPUDevice({.SPIRV, .MSL}, false, nil)
	}
}

@(private)
platform_gl_set_attributes :: proc() {
}

@(private)
platform_validate_gl_renderer :: proc(app: ^App, renderer: string) -> bool {
	return true
}

@(private)
platform_clipboard_fallback :: proc(allocator: mem.Allocator) -> (string, bool) {
	return "", false
}

@(private)
platform_foreground_hint :: proc(driver: string, focusable: bool) -> string {
	if !focusable {
		return "the window manager still reports this window as non-focusable"
	}
	return ""
}

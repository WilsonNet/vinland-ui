#+build darwin
package vui_app

import "core:mem"
import sdl "vendor:sdl3"

@(private)
platform_prepare_init :: proc(app: ^App) {
	// On macOS there is no Mesa offscreen GL driver, so hidden/background apps use Cocoa with
	// SDL_MAC_BACKGROUND_APP=1 (no Dock icon or focus steal) and render offscreen via Metal or GL.
	if app.cfg.hidden || app.cfg.background {
		_ = sdl.SetHint(sdl.HINT_MAC_BACKGROUND_APP, "1")
	}
}

@(private)
platform_create_gpu_device :: proc(backend_env: string) -> ^sdl.GPUDevice {
	switch backend_env {
	case "metal":
		return sdl.CreateGPUDevice({.MSL}, false, "metal")
	case "vulkan":
		return sdl.CreateGPUDevice({.SPIRV}, false, "vulkan")
	case:
		// Prefer Metal directly; if unavailable, fall back to OpenGL 3.3 rather than MoltenVK.
		return sdl.CreateGPUDevice({.MSL}, false, nil)
	}
}

@(private)
platform_gl_set_attributes :: proc() {
	_ = sdl.GL_SetAttribute(.CONTEXT_FLAGS, i32(transmute(u32)sdl.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG))
}

@(private)
platform_validate_gl_renderer :: proc(app: ^App, renderer: string) -> bool {
	return true
}

@(private)
platform_clipboard_fallback :: proc(allocator: mem.Allocator) -> (string, bool) {
	if text, ok := clipboard_from_argv([]string{"pbpaste"}, allocator); ok && text != "" {
		return text, true
	} else if ok {
		delete(text)
	}
	return "", false
}

@(private)
platform_foreground_hint :: proc(driver: string, focusable: bool) -> string {
	if !focusable {
		return "the window manager still reports this window as non-focusable"
	}
	return ""
}

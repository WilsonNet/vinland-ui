#+build linux
package vui_app

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

@(private)
is_software_renderer :: proc(r: string) -> bool {
	l := strings.to_lower(r, context.temp_allocator)
	return strings.contains(l, "llvmpipe") || strings.contains(l, "softpipe") || strings.contains(l, "swrast") || strings.contains(l, "swiftshader")
}

@(private)
platform_prepare_init :: proc(app: ^App) {
	_ = sdl.SetHint(sdl.HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "0")
	// Headless runs (tests, agents, site capture) are sandboxed by default, the way headless
	// browsers use SwiftShader: SDL's offscreen video driver (no compositor connection at all)
	// and Mesa's llvmpipe software rasterizer (no GPU memory). A headless run can never
	// starve or crash the user's desktop. VUI_HIDDEN_GPU=1 opts back into the real GPU.
	app.sandboxed = app.cfg.hidden && os.get_env("VUI_HIDDEN_GPU", context.temp_allocator) != "1"
	if app.sandboxed {
		_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "offscreen")
		_ = os.set_env("LIBGL_ALWAYS_SOFTWARE", "1")
		_ = os.set_env("GALLIUM_DRIVER", "llvmpipe")
		_ = os.set_env("MESA_LOADER_DRIVER_OVERRIDE", "swrast")
	}
}

@(private)
platform_create_gpu_device :: proc(backend_env: string) -> ^sdl.GPUDevice {
	switch backend_env {
	case "vulkan":
		return sdl.CreateGPUDevice({.SPIRV}, false, "vulkan")
	case "metal":
		return nil
	case:
		return sdl.CreateGPUDevice({.SPIRV}, false, nil)
	}
}

@(private)
platform_gl_set_attributes :: proc() {
}

@(private)
platform_validate_gl_renderer :: proc(app: ^App, renderer: string) -> bool {
	if app.sandboxed && !is_software_renderer(renderer) {
		// refuse to run headless on hardware: that is how compositors get starved
		fmt.eprintfln("vui: headless run refused: GL renderer %q is hardware, expected llvmpipe/softpipe. Install mesa, or set VUI_HIDDEN_GPU=1 to use the GPU deliberately.", renderer)
		return false
	}
	return true
}

@(private)
platform_clipboard_fallback :: proc(allocator: mem.Allocator) -> (string, bool) {
	wayland := os.get_env("WAYLAND_DISPLAY", context.temp_allocator)
	if wayland != "" {
		if text, ok := clipboard_from_argv([]string{"wl-paste"}, allocator); ok && text != "" {
			return text, true
		} else if ok {
			delete(text)
		}
	}
	display := os.get_env("DISPLAY", context.temp_allocator)
	if display != "" {
		if text, ok := clipboard_from_argv([]string{"xclip", "-selection", "clipboard", "-o"}, allocator); ok && text != "" {
			return text, true
		} else if ok {
			delete(text)
		}
		if text, ok := clipboard_from_argv([]string{"xsel", "--clipboard", "--output"}, allocator); ok && text != "" {
			return text, true
		} else if ok {
			delete(text)
		}
	}
	return "", false
}

@(private)
platform_foreground_hint :: proc(driver: string, focusable: bool) -> string {
	if strings.contains(driver, "wayland") {
		return "Wayland cannot guarantee focus for an existing surface; restart without VUI_BACKGROUND=1 if it stays unfocused"
	}
	if !focusable {
		return "the window manager still reports this window as non-focusable"
	}
	return ""
}

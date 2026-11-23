#+build linux
package vui_test

import "core:encoding/json"

@(private)
platform_headless_env :: proc(envs: ^[dynamic]string, use_gpu: bool) {
	if !use_gpu {
		// VUI_HIDDEN already selects SDL's offscreen driver inside the app; state
		// it in the environment too so an older app cannot pick Wayland/X11 and
		// map a window on the user's desktop.
		append(envs, "SDL_VIDEO_DRIVER=offscreen")
	}
}

@(private)
platform_verify_headless :: proc(info: json.Object, use_gpu: bool) -> (bool, string) {
	sb, _ := info["sandboxed"].(json.Boolean)
	if !bool(sb) && !use_gpu {
		return false, "vui-test: app is not sandboxed (old vinland-ui?) — refusing to run on the real GPU"
	}
	return true, ""
}

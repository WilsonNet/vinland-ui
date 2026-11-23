#+build !linux
#+build !darwin
package vui_test

import "core:encoding/json"

@(private)
platform_headless_env :: proc(envs: ^[dynamic]string, use_gpu: bool) {
}

@(private)
platform_verify_headless :: proc(info: json.Object, use_gpu: bool) -> (bool, string) {
	hd, _ := info["hidden"].(json.Boolean)
	if !bool(hd) && !use_gpu {
		return false, "vui-test: app is not hidden (old vinland-ui?) — refusing to run a visible window"
	}
	return true, ""
}

#+build darwin
package vui_app

import sdl "vendor:sdl3"

SHADER_MSL :: #load("shaders/ui.metal")

@(private)
gpu_create_metal_shaders :: proc(dev: ^sdl.GPUDevice) -> (vs, fs: ^sdl.GPUShader, ok: bool) {
	vs = make_shader(dev, SHADER_MSL, "vs_main", {.MSL}, .VERTEX, 0, 1)
	fs = make_shader(dev, SHADER_MSL, "fs_main", {.MSL}, .FRAGMENT, 2, 1)
	if vs == nil || fs == nil {
		if vs != nil {
			sdl.ReleaseGPUShader(dev, vs)
		}
		if fs != nil {
			sdl.ReleaseGPUShader(dev, fs)
		}
		return nil, nil, false
	}
	return vs, fs, true
}

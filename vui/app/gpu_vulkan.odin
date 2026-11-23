package vui_app

import sdl "vendor:sdl3"

VERT_SPV :: #load("shaders/ui.vert.spv")
FRAG_SPV :: #load("shaders/ui.frag.spv")

@(private)
gpu_create_vulkan_shaders :: proc(dev: ^sdl.GPUDevice) -> (vs, fs: ^sdl.GPUShader, ok: bool) {
	vs = make_shader(dev, VERT_SPV, "main", {.SPIRV}, .VERTEX, 0, 1)
	fs = make_shader(dev, FRAG_SPV, "main", {.SPIRV}, .FRAGMENT, 2, 1)
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

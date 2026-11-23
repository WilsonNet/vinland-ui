#+build !darwin
package vui_app

import sdl "vendor:sdl3"

@(private)
gpu_create_metal_shaders :: proc(dev: ^sdl.GPUDevice) -> (vs, fs: ^sdl.GPUShader, ok: bool) {
	return nil, nil, false
}

package vui_app

import sdl "vendor:sdl3"
import vui ".."
import vsg "../sdlgpu"

// SDL3 GPU renderer: Metal on macOS and Vulkan on Linux. Pipeline, uploads and drawing
// live in vui/sdlgpu (shared with hosts that embed vui in their own SDL GPU frame); this
// file owns the device, the offscreen target, presentation and readback.

Gpu_Renderer :: struct {
	dev:          ^sdl.GPUDevice,
	// fence of the previous frame: at most one frame in flight, so cycled upload
	// buffers can never pile up in VRAM (offscreen rendering has no swapchain pacing)
	frame_fence:  ^sdl.GPUFence,
	occluded:     bool, // last present found no swapchain image
	window:       ^sdl.Window,
	core:         vsg.Renderer, // pipeline, uploads and draw (shared with embedding hosts)
	target:       ^sdl.GPUTexture,
	target_size:  [2]i32,
	readback:     ^sdl.GPUTransferBuffer,
	readback_cap: int,
	driver:       string,
}

TARGET_FORMAT :: sdl.GPUTextureFormat.R8G8B8A8_UNORM

gpu_init :: proc(r: ^Gpu_Renderer, dev: ^sdl.GPUDevice, window: ^sdl.Window, vsync: bool) -> bool {
	r.dev = dev
	r.window = window
	r.driver = string(sdl.GetGPUDeviceDriver(dev))
	_ = sdl.SetGPUSwapchainParameters(dev, window, .SDR, vsync ? .VSYNC : .IMMEDIATE)
	// one frame in flight (gpu_wait_frame): no need to cycle upload buffers
	return vsg.init(&r.core, dev, TARGET_FORMAT, .INVALID, cycle = false)
}

gpu_destroy :: proc(r: ^Gpu_Renderer, ctx: ^vui.Context) {
	dev := r.dev
	gpu_wait_frame(r)
	vsg.destroy(&r.core, ctx)
	if r.target != nil {
		sdl.ReleaseGPUTexture(dev, r.target)
	}
	if r.readback != nil {
		sdl.ReleaseGPUTransferBuffer(dev, r.readback)
	}
	sdl.ReleaseWindowFromGPUDevice(dev, r.window)
	sdl.DestroyGPUDevice(dev)
}

@(private)
ensure_target :: proc(r: ^Gpu_Renderer, w, h: i32) {
	if r.target != nil && r.target_size == {w, h} {
		return
	}
	if r.target != nil {
		_ = sdl.WaitForGPUIdle(r.dev)
		sdl.ReleaseGPUTexture(r.dev, r.target)
	}
	r.target = vsg.make_texture(r.dev, int(w), int(h), TARGET_FORMAT, {.COLOR_TARGET, .SAMPLER})
	r.target_size = r.target != nil ? [2]i32{w, h} : {}
}

gpu_render :: proc(r: ^Gpu_Renderer, ctx: ^vui.Context, d: ^vui.Draw_List, fb_w, fb_h: i32, clear_color: vui.Color, present: bool) {
	if fb_w <= 0 || fb_h <= 0 {
		return
	}
	gpu_wait_frame(r)
	ensure_target(r, fb_w, fb_h)
	if r.target == nil {
		return
	}
	cmd := sdl.AcquireGPUCommandBuffer(r.dev)
	if cmd == nil {
		return
	}
	vsg.prepare(&r.core, ctx, d, cmd)

	// draw into the offscreen target
	cc := clear_color
	target := sdl.GPUColorTargetInfo{
		texture     = r.target,
		clear_color = {cc.r * cc.a, cc.g * cc.a, cc.b * cc.a, cc.a},
		load_op     = .CLEAR,
		store_op    = .STORE,
		cycle       = false, // cycling would allocate extra full-size targets
	}
	pass := sdl.BeginGPURenderPass(cmd, &target, 1, nil)
	if pass != nil {
		vsg.draw(&r.core, ctx, d, cmd, pass, fb_w, fb_h)
		sdl.EndGPURenderPass(pass)
	}

	if present {
		swap: ^sdl.GPUTexture
		sw, sh: u32
		acquired := sdl.WaitAndAcquireGPUSwapchainTexture(cmd, r.window, &swap, &sw, &sh)
		// no image = window occluded/minimized (e.g. on a hidden workspace): no vsync pacing
		r.occluded = !acquired || swap == nil
		if !r.occluded {
			sdl.BlitGPUTexture(cmd, sdl.GPUBlitInfo{
				source = {texture = r.target, w = u32(fb_w), h = u32(fb_h)},
				destination = {texture = swap, w = sw, h = sh},
				load_op = .DONT_CARE,
				filter = .NEAREST,
			})
		}
	}
	r.frame_fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if r.frame_fence == nil {
		// no fence to pace on: drain the queue rather than let frames pile up
		_ = sdl.WaitForGPUIdle(r.dev)
	}
}

@(private)
gpu_wait_frame :: proc(r: ^Gpu_Renderer) {
	if r.frame_fence != nil {
		_ = sdl.WaitForGPUFences(r.dev, true, &r.frame_fence, 1)
		sdl.ReleaseGPUFence(r.dev, r.frame_fence)
		r.frame_fence = nil
	}
}

// Reads back the last rendered frame (RGBA8, top-down rows, straight alpha).
gpu_read_pixels :: proc(r: ^Gpu_Renderer, allocator := context.allocator) -> (pixels: []u8, w, h: i32) {
	w = r.target_size.x
	h = r.target_size.y
	if r.target == nil || w <= 0 || h <= 0 {
		return
	}
	size := int(w) * int(h) * 4
	// screenshots are rare: a per-read download buffer, released right after, instead of
	// keeping up to 64 MB of GPU-visible memory mapped for the life of the app
	if r.readback != nil {
		sdl.ReleaseGPUTransferBuffer(r.dev, r.readback)
		r.readback = nil
		r.readback_cap = 0
	}
	xfer := sdl.CreateGPUTransferBuffer(r.dev, {usage = .DOWNLOAD, size = u32(size)})
	if xfer == nil {
		return nil, 0, 0
	}
	defer sdl.ReleaseGPUTransferBuffer(r.dev, xfer)
	cmd := sdl.AcquireGPUCommandBuffer(r.dev)
	if cmd == nil {
		return nil, 0, 0
	}
	cp := sdl.BeginGPUCopyPass(cmd)
	sdl.DownloadFromGPUTexture(cp, {texture = r.target, w = u32(w), h = u32(h), d = 1}, {transfer_buffer = xfer, pixels_per_row = u32(w), rows_per_layer = u32(h)})
	sdl.EndGPUCopyPass(cp)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence != nil {
		_ = sdl.WaitForGPUFences(r.dev, true, &fence, 1)
		sdl.ReleaseGPUFence(r.dev, fence)
	} else {
		_ = sdl.WaitForGPUIdle(r.dev)
	}
	src := sdl.MapGPUTransferBuffer(r.dev, xfer, false)
	if src == nil {
		return nil, 0, 0
	}
	pixels = make([]u8, size, allocator)
	copy(pixels, (cast([^]u8)src)[:size])
	sdl.UnmapGPUTransferBuffer(r.dev, xfer)
	for i := 0; i < len(pixels); i += 4 {
		a := pixels[i + 3]
		if a > 0 && a < 255 {
			for c in 0 ..< 3 {
				pixels[i + c] = u8(min(255, int(pixels[i + c]) * 255 / int(a)))
			}
		}
	}
	return
}

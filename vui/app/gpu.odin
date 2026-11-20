package vui_app

import "core:fmt"
import sdl "vendor:sdl3"
import vui ".."

// SDL3 GPU renderer: Vulkan on Linux (Metal on macOS, D3D12 on Windows once their shader
// formats are added). Same draw list and the same shader source as the GL renderer;
// SPIR-V is precompiled from shaders/ui.{vert,frag} (see build.sh).

VERT_SPV :: #load("shaders/ui.vert.spv")
FRAG_SPV :: #load("shaders/ui.frag.spv")

Gpu_Renderer :: struct {
	dev:         ^sdl.GPUDevice,
	window:      ^sdl.Window,
	pipeline:    ^sdl.GPUGraphicsPipeline,
	inst_buf:    ^sdl.GPUBuffer,
	inst_cap:    int,
	inst_xfer:   ^sdl.GPUTransferBuffer,
	atlas:       ^sdl.GPUTexture,
	atlas_w:     int,
	atlas_h:     int,
	atlas_gen:   u32,
	atlas_xfer:  ^sdl.GPUTransferBuffer,
	atlas_xfer_cap: int,
	white:       ^sdl.GPUTexture,
	smp_linear:  ^sdl.GPUSampler,
	smp_mip:     ^sdl.GPUSampler,
	target:      ^sdl.GPUTexture,
	target_size: [2]i32,
	driver:      string,
}

Frag_Uniforms :: struct {
	filters:    [MAX_FILTERS]matrix[4, 4]f32,
	filter_off: [MAX_FILTERS][4]f32,
	atlas_size: [2]f32,
	gamma:      f32,
	contrast:   f32,
}

TARGET_FORMAT :: sdl.GPUTextureFormat.R8G8B8A8_UNORM

@(private)
make_shader :: proc(dev: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage, samplers, uniforms: u32) -> ^sdl.GPUShader {
	info := sdl.GPUShaderCreateInfo{
		code_size           = uint(len(code)),
		code                = raw_data(code),
		entrypoint          = "main",
		format              = {.SPIRV},
		stage               = stage,
		num_samplers        = samplers,
		num_uniform_buffers = uniforms,
	}
	return sdl.CreateGPUShader(dev, info)
}

@(private)
make_texture :: proc(dev: ^sdl.GPUDevice, w, h: int, format: sdl.GPUTextureFormat, usage: sdl.GPUTextureUsageFlags, levels: u32 = 1) -> ^sdl.GPUTexture {
	return sdl.CreateGPUTexture(dev, sdl.GPUTextureCreateInfo{
		type = .D2,
		format = format,
		usage = usage,
		width = u32(w),
		height = u32(h),
		layer_count_or_depth = 1,
		num_levels = levels,
	})
}

gpu_init :: proc(r: ^Gpu_Renderer, dev: ^sdl.GPUDevice, window: ^sdl.Window, vsync: bool) -> bool {
	r.dev = dev
	r.window = window
	r.driver = string(sdl.GetGPUDeviceDriver(dev))
	_ = sdl.SetGPUSwapchainParameters(dev, window, .SDR, vsync ? .VSYNC : .IMMEDIATE)

	vs := make_shader(dev, VERT_SPV, .VERTEX, 0, 1)
	fs := make_shader(dev, FRAG_SPV, .FRAGMENT, 2, 1)
	if vs == nil || fs == nil {
		fmt.eprintln("vui: GPU shader creation failed:", sdl.GetError())
		return false
	}
	defer sdl.ReleaseGPUShader(dev, vs)
	defer sdl.ReleaseGPUShader(dev, fs)

	attrs: [15]sdl.GPUVertexAttribute
	for i in 0 ..< 15 {
		attrs[i] = {location = u32(i), buffer_slot = 0, format = .FLOAT4, offset = u32(i * 16)}
	}
	vbd := sdl.GPUVertexBufferDescription{slot = 0, pitch = size_of(vui.Draw_Cmd), input_rate = .INSTANCE}
	ctd := sdl.GPUColorTargetDescription{
		format = TARGET_FORMAT,
		blend_state = {
			enable_blend = true,
			src_color_blendfactor = .ONE,
			dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
			color_blend_op = .ADD,
			src_alpha_blendfactor = .ONE,
			dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
			alpha_blend_op = .ADD,
		},
	}
	r.pipeline = sdl.CreateGPUGraphicsPipeline(dev, sdl.GPUGraphicsPipelineCreateInfo{
		vertex_shader = vs,
		fragment_shader = fs,
		vertex_input_state = {
			vertex_buffer_descriptions = &vbd,
			num_vertex_buffers = 1,
			vertex_attributes = &attrs[0],
			num_vertex_attributes = 15,
		},
		primitive_type = .TRIANGLESTRIP,
		rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE},
		target_info = {color_target_descriptions = &ctd, num_color_targets = 1},
	})
	if r.pipeline == nil {
		fmt.eprintln("vui: GPU pipeline creation failed:", sdl.GetError())
		return false
	}
	r.smp_linear = sdl.CreateGPUSampler(dev, sdl.GPUSamplerCreateInfo{
		min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_mode = .NEAREST,
		address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
	})
	r.smp_mip = sdl.CreateGPUSampler(dev, sdl.GPUSamplerCreateInfo{
		min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_mode = .LINEAR,
		address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
		max_lod = 1000,
	})
	r.white = make_texture(dev, 1, 1, .R8G8B8A8_UNORM, {.SAMPLER})
	white := [4]u8{255, 255, 255, 255}
	upload_texture(r, r.white, white[:], 0, 0, 1, 1, 4)
	return true
}

gpu_destroy :: proc(r: ^Gpu_Renderer, ctx: ^vui.Context) {
	dev := r.dev
	_ = sdl.WaitForGPUIdle(dev)
	for &img in ctx.images {
		if img.handle != 0 {
			sdl.ReleaseGPUTexture(dev, cast(^sdl.GPUTexture)uintptr(img.handle))
			img.handle = 0
		}
	}
	if r.inst_buf != nil {
		sdl.ReleaseGPUBuffer(dev, r.inst_buf)
	}
	if r.inst_xfer != nil {
		sdl.ReleaseGPUTransferBuffer(dev, r.inst_xfer)
	}
	if r.atlas != nil {
		sdl.ReleaseGPUTexture(dev, r.atlas)
	}
	if r.atlas_xfer != nil {
		sdl.ReleaseGPUTransferBuffer(dev, r.atlas_xfer)
	}
	if r.target != nil {
		sdl.ReleaseGPUTexture(dev, r.target)
	}
	sdl.ReleaseGPUTexture(dev, r.white)
	sdl.ReleaseGPUSampler(dev, r.smp_linear)
	sdl.ReleaseGPUSampler(dev, r.smp_mip)
	sdl.ReleaseGPUGraphicsPipeline(dev, r.pipeline)
	sdl.ReleaseWindowFromGPUDevice(dev, r.window)
	sdl.DestroyGPUDevice(dev)
}

// One-shot synchronous texture upload (used for small or rare uploads).
@(private)
upload_texture :: proc(r: ^Gpu_Renderer, tex: ^sdl.GPUTexture, pixels: []u8, x, y, w, h: int, bpp: int) {
	size := w * h * bpp
	xfer := sdl.CreateGPUTransferBuffer(r.dev, {usage = .UPLOAD, size = u32(size)})
	defer sdl.ReleaseGPUTransferBuffer(r.dev, xfer)
	dst := sdl.MapGPUTransferBuffer(r.dev, xfer, false)
	copy((cast([^]u8)dst)[:size], pixels[:size])
	sdl.UnmapGPUTransferBuffer(r.dev, xfer)
	cmd := sdl.AcquireGPUCommandBuffer(r.dev)
	cp := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(cp, {transfer_buffer = xfer, pixels_per_row = u32(w), rows_per_layer = u32(h)}, {texture = tex, x = u32(x), y = u32(y), w = u32(w), h = u32(h), d = 1}, false)
	sdl.EndGPUCopyPass(cp)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
}

@(private)
sync_gpu_atlas :: proc(r: ^Gpu_Renderer, cp: ^sdl.GPUCopyPass, a: ^vui.Atlas) {
	full := false
	if r.atlas == nil || r.atlas_gen != a.generation || r.atlas_w != a.w || r.atlas_h != a.h {
		if r.atlas != nil {
			sdl.ReleaseGPUTexture(r.dev, r.atlas)
		}
		r.atlas = make_texture(r.dev, a.w, a.h, .R8_UNORM, {.SAMPLER})
		r.atlas_gen = a.generation
		r.atlas_w = a.w
		r.atlas_h = a.h
		full = true
	}
	if !full && !a.dirty {
		return
	}
	y0 := full ? 0 : clamp(a.dirty_y0, 0, a.h)
	y1 := full ? a.h : clamp(a.dirty_y1, 0, a.h)
	a.dirty = false
	if y1 <= y0 {
		return
	}
	size := (y1 - y0) * a.w
	if r.atlas_xfer == nil || r.atlas_xfer_cap < size {
		if r.atlas_xfer != nil {
			sdl.ReleaseGPUTransferBuffer(r.dev, r.atlas_xfer)
		}
		r.atlas_xfer_cap = max(size, a.w * a.h)
		r.atlas_xfer = sdl.CreateGPUTransferBuffer(r.dev, {usage = .UPLOAD, size = u32(r.atlas_xfer_cap)})
	}
	dst := sdl.MapGPUTransferBuffer(r.dev, r.atlas_xfer, true)
	copy((cast([^]u8)dst)[:size], a.pixels[y0 * a.w:y1 * a.w])
	sdl.UnmapGPUTransferBuffer(r.dev, r.atlas_xfer)
	sdl.UploadToGPUTexture(cp, {transfer_buffer = r.atlas_xfer, pixels_per_row = u32(a.w), rows_per_layer = u32(y1 - y0)}, {texture = r.atlas, y = u32(y0), w = u32(a.w), h = u32(y1 - y0), d = 1}, false)
}

@(private)
sync_gpu_images :: proc(r: ^Gpu_Renderer, ctx: ^vui.Context) {
	for &img in ctx.images {
		if !img.dirty || img.freed {
			continue
		}
		if img.handle != 0 {
			sdl.ReleaseGPUTexture(r.dev, cast(^sdl.GPUTexture)uintptr(img.handle))
		}
		levels := u32(1)
		for (img.w >> levels) > 0 || (img.h >> levels) > 0 {
			levels += 1
		}
		tex := make_texture(r.dev, img.w, img.h, .R8G8B8A8_UNORM, {.SAMPLER, .COLOR_TARGET}, levels)
		upload_texture(r, tex, img.pixels, 0, 0, img.w, img.h, 4)
		cmd := sdl.AcquireGPUCommandBuffer(r.dev)
		sdl.GenerateMipmapsForGPUTexture(cmd, tex)
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		img.handle = u64(uintptr(tex))
		img.dirty = false
	}
}

@(private)
ensure_target :: proc(r: ^Gpu_Renderer, w, h: i32) {
	if r.target != nil && r.target_size == {w, h} {
		return
	}
	if r.target != nil {
		sdl.ReleaseGPUTexture(r.dev, r.target)
	}
	r.target = make_texture(r.dev, int(w), int(h), TARGET_FORMAT, {.COLOR_TARGET, .SAMPLER})
	r.target_size = {w, h}
}

gpu_render :: proc(r: ^Gpu_Renderer, ctx: ^vui.Context, d: ^vui.Draw_List, fb_w, fb_h: i32, clear_color: vui.Color, present: bool) {
	if fb_w <= 0 || fb_h <= 0 {
		return
	}
	ensure_target(r, fb_w, fb_h)
	sync_gpu_images(r, ctx)
	cmd := sdl.AcquireGPUCommandBuffer(r.dev)
	if cmd == nil {
		return
	}

	// uploads
	n := len(d.cmds)
	bytes := n * size_of(vui.Draw_Cmd)
	if n > 0 && (r.inst_buf == nil || r.inst_cap < n) {
		if r.inst_buf != nil {
			sdl.ReleaseGPUBuffer(r.dev, r.inst_buf)
			sdl.ReleaseGPUTransferBuffer(r.dev, r.inst_xfer)
		}
		r.inst_cap = max(4096, n * 2)
		r.inst_buf = sdl.CreateGPUBuffer(r.dev, {usage = {.VERTEX}, size = u32(r.inst_cap * size_of(vui.Draw_Cmd))})
		r.inst_xfer = sdl.CreateGPUTransferBuffer(r.dev, {usage = .UPLOAD, size = u32(r.inst_cap * size_of(vui.Draw_Cmd))})
	}
	cp := sdl.BeginGPUCopyPass(cmd)
	if n > 0 {
		dst := sdl.MapGPUTransferBuffer(r.dev, r.inst_xfer, true)
		copy((cast([^]u8)dst)[:bytes], (cast([^]u8)raw_data(d.cmds))[:bytes])
		sdl.UnmapGPUTransferBuffer(r.dev, r.inst_xfer)
		sdl.UploadToGPUBuffer(cp, {transfer_buffer = r.inst_xfer}, {buffer = r.inst_buf, size = u32(bytes)}, true)
	}
	sync_gpu_atlas(r, cp, &ctx.atlas)
	sdl.EndGPUCopyPass(cp)

	// draw into the offscreen target
	cc := clear_color
	target := sdl.GPUColorTargetInfo{
		texture     = r.target,
		clear_color = {cc.r * cc.a, cc.g * cc.a, cc.b * cc.a, cc.a},
		load_op     = .CLEAR,
		store_op    = .STORE,
		cycle       = true,
	}
	pass := sdl.BeginGPURenderPass(cmd, &target, 1, nil)
	if n > 0 {
		sdl.BindGPUGraphicsPipeline(pass, r.pipeline)
		binding := sdl.GPUBufferBinding{buffer = r.inst_buf}
		sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
		vu := [4]f32{f32(fb_w), f32(fb_h), 0, 0}
		sdl.PushGPUVertexUniformData(cmd, 0, &vu, size_of(vu))
		fu: Frag_Uniforms
		for i in 0 ..< min(len(d.filters), MAX_FILTERS) {
			fu.filters[i] = d.filters[i].m
			fu.filter_off[i] = d.filters[i].o
		}
		fu.atlas_size = {f32(ctx.atlas.w), f32(ctx.atlas.h)}
		fu.gamma = ctx.text_gamma > 0 ? ctx.text_gamma : 1
		fu.contrast = 1
		sdl.PushGPUFragmentUniformData(cmd, 0, &fu, size_of(fu))
		for b in d.batches {
			img := r.white
			smp := r.smp_linear
			if b.image != 0 && int(b.image) <= len(ctx.images) && ctx.images[b.image - 1].handle != 0 {
				img = cast(^sdl.GPUTexture)uintptr(ctx.images[b.image - 1].handle)
				smp = r.smp_mip
			}
			binds := [2]sdl.GPUTextureSamplerBinding{{texture = r.atlas, sampler = r.smp_linear}, {texture = img, sampler = smp}}
			sdl.BindGPUFragmentSamplers(pass, 0, &binds[0], 2)
			sdl.DrawGPUPrimitives(pass, 4, u32(b.count), 0, u32(b.first))
		}
	}
	sdl.EndGPURenderPass(pass)

	if present {
		swap: ^sdl.GPUTexture
		sw, sh: u32
		if sdl.WaitAndAcquireGPUSwapchainTexture(cmd, r.window, &swap, &sw, &sh) && swap != nil {
			sdl.BlitGPUTexture(cmd, sdl.GPUBlitInfo{
				source = {texture = r.target, w = u32(fb_w), h = u32(fb_h)},
				destination = {texture = swap, w = sw, h = sh},
				load_op = .DONT_CARE,
				filter = .NEAREST,
			})
		}
	}
	_ = sdl.SubmitGPUCommandBuffer(cmd)
}

// Reads back the last rendered frame (RGBA8, top-down rows, straight alpha).
gpu_read_pixels :: proc(r: ^Gpu_Renderer, allocator := context.allocator) -> (pixels: []u8, w, h: i32) {
	w = r.target_size.x
	h = r.target_size.y
	if r.target == nil || w <= 0 || h <= 0 {
		return
	}
	size := int(w * h * 4)
	xfer := sdl.CreateGPUTransferBuffer(r.dev, {usage = .DOWNLOAD, size = u32(size)})
	defer sdl.ReleaseGPUTransferBuffer(r.dev, xfer)
	cmd := sdl.AcquireGPUCommandBuffer(r.dev)
	cp := sdl.BeginGPUCopyPass(cmd)
	sdl.DownloadFromGPUTexture(cp, {texture = r.target, w = u32(w), h = u32(h), d = 1}, {transfer_buffer = xfer, pixels_per_row = u32(w), rows_per_layer = u32(h)})
	sdl.EndGPUCopyPass(cp)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	_ = sdl.WaitForGPUFences(r.dev, true, &fence, 1)
	sdl.ReleaseGPUFence(r.dev, fence)
	src := sdl.MapGPUTransferBuffer(r.dev, xfer, false)
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

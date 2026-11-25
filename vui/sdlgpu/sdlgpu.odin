// Embeddable SDL3 GPU renderer for vinland-ui: draws a vui draw list inside a render pass
// the host owns (a game that already renders with SDL GPU on Metal or Vulkan).
//
//     r: vsg.Renderer
//     vsg.init(&r, dev, color_format, depth_format)  // formats of the pass VUI draws in
//     // each frame, with the host's command buffer:
//     vsg.prepare(&r, ctx, draw_list, cmd)            // before any render pass begins
//     ...host begins its render pass...
//     vsg.draw(&r, ctx, draw_list, cmd, pass, fb_w, fb_h)
//
// Same shaders as vui/app (MSL on Metal, SPIR-V on Vulkan) and the same draw-list contract.
// Images are uploaded by vui; external images (ui.image_register_external) are host-owned
// SDL_GPUTexture pointers and are only sampled.
package vui_sdlgpu

import "core:fmt"
import sdl "vendor:sdl3"
import vui ".."

MAX_FILTERS :: vui.MAX_DRAW_FILTERS

@(private)
SHADER_MSL :: #load("../app/shaders/ui.metal")
@(private)
SHADER_VS_SPV :: #load("../app/shaders/ui.vert.spv")
@(private)
SHADER_FS_SPV :: #load("../app/shaders/ui.frag.spv")

Frag_Uniforms :: struct {
	filters:    [MAX_FILTERS]matrix[4, 4]f32,
	filter_off: [MAX_FILTERS][4]f32,
	atlas_size: [2]f32,
	gamma:      f32,
	contrast:   f32,
	grade:      [4]f32,
	grade_tint: [4]f32,
}

Renderer :: struct {
	dev:            ^sdl.GPUDevice,
	pipeline:       ^sdl.GPUGraphicsPipeline,
	inst_buf:       ^sdl.GPUBuffer,
	inst_cap:       int,
	inst_xfer:      ^sdl.GPUTransferBuffer,
	atlas:          ^sdl.GPUTexture,
	atlas_w:        int,
	atlas_h:        int,
	atlas_gen:      u32,
	atlas_xfer:     ^sdl.GPUTransferBuffer,
	atlas_xfer_cap: int,
	white:          ^sdl.GPUTexture,
	smp_linear:     ^sdl.GPUSampler,
	smp_mip:        ^sdl.GPUSampler,
	smp_nearest:    ^sdl.GPUSampler,
	prepared:       int, // instances uploaded by the last prepare
	// cycle the upload buffers: the host may keep several frames in flight
	cycle:          bool,
}

@(private)
make_shader :: proc(dev: ^sdl.GPUDevice, code: []u8, entrypoint: cstring, format: sdl.GPUShaderFormatFlag, stage: sdl.GPUShaderStage, samplers, uniforms: u32) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(dev, sdl.GPUShaderCreateInfo{
		code_size           = uint(len(code)),
		code                = raw_data(code),
		entrypoint          = entrypoint,
		format              = {format},
		stage               = stage,
		num_samplers        = samplers,
		num_uniform_buffers = uniforms,
	})
}

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

// color_format / depth_format describe the render pass `draw` will be called in
// (depth_format = .INVALID when that pass has no depth attachment).
init :: proc(r: ^Renderer, dev: ^sdl.GPUDevice, color_format: sdl.GPUTextureFormat, depth_format: sdl.GPUTextureFormat = .INVALID, cycle := true) -> bool {
	r.dev = dev
	r.cycle = cycle
	formats := sdl.GetGPUShaderFormats(dev)
	vs, fs: ^sdl.GPUShader
	if .MSL in formats {
		vs = make_shader(dev, SHADER_MSL, "vs_main", .MSL, .VERTEX, 0, 1)
		fs = make_shader(dev, SHADER_MSL, "fs_main", .MSL, .FRAGMENT, 2, 1)
	} else if .SPIRV in formats {
		vs = make_shader(dev, SHADER_VS_SPV, "main", .SPIRV, .VERTEX, 0, 1)
		fs = make_shader(dev, SHADER_FS_SPV, "main", .SPIRV, .FRAGMENT, 2, 1)
	} else {
		fmt.eprintln("vui: GPU device supports no usable shader format")
		return false
	}
	defer if vs != nil {
		sdl.ReleaseGPUShader(dev, vs)
	}
	defer if fs != nil {
		sdl.ReleaseGPUShader(dev, fs)
	}
	if vs == nil || fs == nil {
		fmt.eprintln("vui: GPU shader creation failed:", sdl.GetError())
		return false
	}

	attrs: [15]sdl.GPUVertexAttribute
	for i in 0 ..< 15 {
		attrs[i] = {location = u32(i), buffer_slot = 0, format = .FLOAT4, offset = u32(i * 16)}
	}
	vbd := sdl.GPUVertexBufferDescription{slot = 0, pitch = size_of(vui.Draw_Cmd), input_rate = .INSTANCE}
	ctd := sdl.GPUColorTargetDescription{
		format = color_format,
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
		target_info = {
			color_target_descriptions = &ctd,
			num_color_targets = 1,
			depth_stencil_format = depth_format,
			has_depth_stencil_target = depth_format != .INVALID,
		},
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
	r.smp_nearest = sdl.CreateGPUSampler(dev, sdl.GPUSamplerCreateInfo{
		min_filter = .NEAREST, mag_filter = .NEAREST, mipmap_mode = .NEAREST,
		address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
	})
	r.white = make_texture(dev, 1, 1, .R8G8B8A8_UNORM, {.SAMPLER})
	white := [4]u8{255, 255, 255, 255}
	upload_texture(dev, r.white, white[:], 0, 0, 1, 1, 4)
	return true
}

// Releases the renderer and the images vui uploaded (not external ones). The device stays.
destroy :: proc(r: ^Renderer, ctx: ^vui.Context) {
	dev := r.dev
	if dev == nil {
		return
	}
	_ = sdl.WaitForGPUIdle(dev)
	if ctx != nil {
		for &img in ctx.images {
			if img.handle != 0 && !img.external {
				sdl.ReleaseGPUTexture(dev, cast(^sdl.GPUTexture)uintptr(img.handle))
				img.handle = 0
			}
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
	if r.white != nil {
		sdl.ReleaseGPUTexture(dev, r.white)
	}
	if r.smp_linear != nil {
		sdl.ReleaseGPUSampler(dev, r.smp_linear)
	}
	if r.smp_mip != nil {
		sdl.ReleaseGPUSampler(dev, r.smp_mip)
	}
	if r.smp_nearest != nil {
		sdl.ReleaseGPUSampler(dev, r.smp_nearest)
	}
	if r.pipeline != nil {
		sdl.ReleaseGPUGraphicsPipeline(dev, r.pipeline)
	}
	r^ = {}
}

// One-shot synchronous texture upload (small or rare uploads).
upload_texture :: proc(dev: ^sdl.GPUDevice, tex: ^sdl.GPUTexture, pixels: []u8, x, y, w, h: int, bpp: int) {
	size := w * h * bpp
	if tex == nil || size <= 0 || len(pixels) < size {
		return
	}
	xfer := sdl.CreateGPUTransferBuffer(dev, {usage = .UPLOAD, size = u32(size)})
	if xfer == nil {
		return
	}
	defer sdl.ReleaseGPUTransferBuffer(dev, xfer)
	dst := sdl.MapGPUTransferBuffer(dev, xfer, false)
	if dst == nil {
		return
	}
	copy((cast([^]u8)dst)[:size], pixels[:size])
	sdl.UnmapGPUTransferBuffer(dev, xfer)
	cmd := sdl.AcquireGPUCommandBuffer(dev)
	if cmd == nil {
		return
	}
	cp := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(cp, {transfer_buffer = xfer, pixels_per_row = u32(w), rows_per_layer = u32(h)}, {texture = tex, x = u32(x), y = u32(y), w = u32(w), h = u32(h), d = 1}, false)
	sdl.EndGPUCopyPass(cp)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
}

@(private)
sync_atlas :: proc(r: ^Renderer, cp: ^sdl.GPUCopyPass, a: ^vui.Atlas) {
	full := false
	if r.atlas == nil || r.atlas_w != a.w || r.atlas_h != a.h {
		if r.atlas != nil {
			sdl.ReleaseGPUTexture(r.dev, r.atlas)
		}
		r.atlas = make_texture(r.dev, a.w, a.h, .R8_UNORM, {.SAMPLER})
		if r.atlas == nil {
			return
		}
		r.atlas_w = a.w
		r.atlas_h = a.h
		full = true
	}
	if r.atlas_gen != a.generation {
		// cleared (same size): re-upload into the existing texture instead of re-creating it
		r.atlas_gen = a.generation
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
		if r.atlas_xfer == nil {
			r.atlas_xfer_cap = 0
			a.dirty = true
			return
		}
	}
	dst := sdl.MapGPUTransferBuffer(r.dev, r.atlas_xfer, r.cycle)
	if dst == nil {
		return
	}
	copy((cast([^]u8)dst)[:size], a.pixels[y0 * a.w:y1 * a.w])
	sdl.UnmapGPUTransferBuffer(r.dev, r.atlas_xfer)
	sdl.UploadToGPUTexture(cp, {transfer_buffer = r.atlas_xfer, pixels_per_row = u32(a.w), rows_per_layer = u32(y1 - y0)}, {texture = r.atlas, y = u32(y0), w = u32(a.w), h = u32(y1 - y0), d = 1}, false)
}

// Uploads images vui owns that changed (once; a failed upload is not retried every frame).
sync_images :: proc(r: ^Renderer, ctx: ^vui.Context) {
	for &img in ctx.images {
		if !img.dirty || img.freed || img.external {
			continue
		}
		if img.handle != 0 {
			sdl.ReleaseGPUTexture(r.dev, cast(^sdl.GPUTexture)uintptr(img.handle))
		}
		img.handle = 0
		img.dirty = false
		if img.w <= 0 || img.h <= 0 || len(img.pixels) < img.w * img.h * 4 {
			continue
		}
		levels := u32(1)
		for (img.w >> levels) > 0 || (img.h >> levels) > 0 {
			levels += 1
		}
		tex := make_texture(r.dev, img.w, img.h, .R8G8B8A8_UNORM, {.SAMPLER, .COLOR_TARGET}, levels)
		if tex == nil {
			continue
		}
		upload_texture(r.dev, tex, img.pixels, 0, 0, img.w, img.h, 4)
		if cmd := sdl.AcquireGPUCommandBuffer(r.dev); cmd != nil {
			sdl.GenerateMipmapsForGPUTexture(cmd, tex)
			_ = sdl.SubmitGPUCommandBuffer(cmd)
		}
		img.handle = u64(uintptr(tex))
	}
}

// Uploads this frame's instances, glyph atlas and images. Call before any render pass of
// `cmd` begins (it records a copy pass).
prepare :: proc(r: ^Renderer, ctx: ^vui.Context, d: ^vui.Draw_List, cmd: ^sdl.GPUCommandBuffer) {
	r.prepared = 0
	if r.pipeline == nil || d == nil {
		return
	}
	sync_images(r, ctx)
	n := min(len(d.cmds), vui.MAX_DRAW_CMDS)
	if n > 0 && (r.inst_buf == nil || r.inst_xfer == nil || r.inst_cap < n) {
		if r.inst_buf != nil {
			sdl.ReleaseGPUBuffer(r.dev, r.inst_buf)
		}
		if r.inst_xfer != nil {
			sdl.ReleaseGPUTransferBuffer(r.dev, r.inst_xfer)
		}
		r.inst_cap = clamp(n + n / 2, 4096, vui.MAX_DRAW_CMDS)
		r.inst_buf = sdl.CreateGPUBuffer(r.dev, {usage = {.VERTEX}, size = u32(r.inst_cap * size_of(vui.Draw_Cmd))})
		r.inst_xfer = sdl.CreateGPUTransferBuffer(r.dev, {usage = .UPLOAD, size = u32(r.inst_cap * size_of(vui.Draw_Cmd))})
		if r.inst_buf == nil || r.inst_xfer == nil {
			r.inst_cap = 0 // allocation failed: draw nothing this frame, retry next frame
		}
	}
	if r.inst_cap < n {
		n = 0
	}
	bytes := n * size_of(vui.Draw_Cmd)
	cp := sdl.BeginGPUCopyPass(cmd)
	if n > 0 {
		if dst := sdl.MapGPUTransferBuffer(r.dev, r.inst_xfer, r.cycle); dst != nil {
			copy((cast([^]u8)dst)[:bytes], (cast([^]u8)raw_data(d.cmds))[:bytes])
			sdl.UnmapGPUTransferBuffer(r.dev, r.inst_xfer)
			sdl.UploadToGPUBuffer(cp, {transfer_buffer = r.inst_xfer}, {buffer = r.inst_buf, size = u32(bytes)}, r.cycle)
		} else {
			n = 0
		}
	}
	sync_atlas(r, cp, &ctx.atlas)
	sdl.EndGPUCopyPass(cp)
	r.prepared = n
}

// Draws the prepared list into the host's render pass (full framebuffer viewport).
draw :: proc(r: ^Renderer, ctx: ^vui.Context, d: ^vui.Draw_List, cmd: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, fb_w, fb_h: i32) {
	n := r.prepared
	if n <= 0 || r.atlas == nil || pass == nil || d == nil {
		return
	}
	sdl.SetGPUViewport(pass, sdl.GPUViewport{x = 0, y = 0, w = f32(fb_w), h = f32(fb_h), min_depth = 0, max_depth = 1})
	sdl.SetGPUScissor(pass, sdl.Rect{0, 0, fb_w, fb_h})
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
	fu.grade, fu.grade_tint = vui.grade_uniforms(ctx.grade, ctx.scale)
	sdl.PushGPUFragmentUniformData(cmd, 0, &fu, size_of(fu))
	for b in d.batches {
		if b.count <= 0 || int(b.first) >= n {
			continue
		}
		count := min(int(b.count), n - int(b.first))
		img := r.white
		smp := r.smp_linear
		if b.image != 0 && int(b.image) <= len(ctx.images) && ctx.images[b.image - 1].handle != 0 {
			def := &ctx.images[b.image - 1]
			img = cast(^sdl.GPUTexture)uintptr(def.handle)
			smp = def.nearest ? r.smp_nearest : r.smp_mip
		}
		binds := [2]sdl.GPUTextureSamplerBinding{{texture = r.atlas, sampler = r.smp_linear}, {texture = img, sampler = smp}}
		sdl.BindGPUFragmentSamplers(pass, 0, &binds[0], 2)
		sdl.DrawGPUPrimitives(pass, 4, u32(count), 0, u32(b.first))
	}
}

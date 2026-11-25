---
trigger: model_decision
description: >-
  Keeps GLSL (OpenGL 3.3), SPIR-V (Vulkan), MSL (Metal), and WebGL2 shaders in lockstep
  when modifying Draw_Cmd, uniforms, or rendering primitives.
---

# Shader Parity Contract

Any change to `vui.Draw_Cmd`, `Frag_Uniforms`, draw primitive `kind`s, or blending/clipping must be applied consistently to all four shader targets:

1. **OpenGL 3.3**: `vui/app/shaders/ui_vs_body.glsl`, `vui/app/shaders/ui_fs_body.glsl`, `vui/app/gl.odin`
2. **Vulkan SPIR-V**: `vui/app/shaders/ui.vert`, `vui/app/shaders/ui.frag` (recompiled to `.spv` by `./build.sh` when `glslc` is available)
3. **Metal MSL**: `vui/app/shaders/ui.metal`
4. **WebGL2**: `vui/web/web.odin`

## GLSL-to-MSL Traps (`ui.metal`)

- **Modulo on negative numbers**: GLSL `mod(x, y)` returns `x - y * floor(x / y)` (always in `[0, y)`), whereas MSL `fmod` can return negative values (breaks `draw_arc` dials and stripes). Always use `glsl_mod(x, y)`.
- **2-arg atan**: GLSL `atan(y, x)` is `atan2(y, x)` in MSL.
- **Derivatives & discard**: use `dfdx`/`dfdy` (not `dFdx`/`dFdy`) and `discard_fragment(); return float4(0.0f);`.
- **SDL3 GPU Metal bindings**: vertex/fragment uniform buffers both bind at `[[buffer(0)]]`; vertex buffers use `[[stage_in]]`; sampled textures use `[[texture(n)]]` + `[[sampler(n)]]`.
- **Uniform struct padding**: `VertexUniforms` is 16-byte aligned (`float2 u_viewport; float2 _pad;`); `FragmentUniforms` must match `Frag_Uniforms` in `vui/sdlgpu/sdlgpu.odin` (16x `float4x4` + 16x `float4` + `float2` + `2x float`).

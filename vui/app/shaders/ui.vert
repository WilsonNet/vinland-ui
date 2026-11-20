#version 450
#extension GL_GOOGLE_include_directive : require
#define gl_VertexID gl_VertexIndex
layout(location=0) in vec4 a_size;
layout(location=1) in vec4 a_radii;
layout(location=2) in vec4 a_fill0;
layout(location=3) in vec4 a_fill1;
layout(location=4) in vec4 a_fill2;
layout(location=5) in vec4 a_bw;
layout(location=6) in vec4 a_bc;
layout(location=7) in vec4 a_grad;
layout(location=8) in vec4 a_params;
layout(location=9) in vec4 a_uv;
layout(location=10) in vec4 a_clip;
layout(location=11) in vec4 a_clipr;
layout(location=12) in vec4 a_xf;
layout(location=13) in vec4 a_xt;
layout(location=14) in vec4 a_extra;
layout(set=1, binding=0) uniform VertexUniforms { vec2 u_viewport; };
layout(location=0) out vec2 v_local;
layout(location=1) out vec2 v_world;
layout(location=2) flat out vec4 f_size;
layout(location=3) flat out vec4 f_radii;
layout(location=4) flat out vec4 f_fill0;
layout(location=5) flat out vec4 f_fill1;
layout(location=6) flat out vec4 f_fill2;
layout(location=7) flat out vec4 f_bw;
layout(location=8) flat out vec4 f_bc;
layout(location=9) flat out vec4 f_grad;
layout(location=10) flat out vec4 f_params;
layout(location=11) flat out vec4 f_uv;
layout(location=12) flat out vec4 f_clip;
layout(location=13) flat out vec4 f_clipr;
layout(location=14) flat out vec4 f_xt;
layout(location=15) flat out vec4 f_extra;
#include "ui_vs_body.glsl"

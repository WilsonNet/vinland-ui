#version 450
#extension GL_GOOGLE_include_directive : require
layout(location=0) in vec2 v_local;
layout(location=1) in vec2 v_world;
layout(location=2) flat in vec4 f_size;
layout(location=3) flat in vec4 f_radii;
layout(location=4) flat in vec4 f_fill0;
layout(location=5) flat in vec4 f_fill1;
layout(location=6) flat in vec4 f_fill2;
layout(location=7) flat in vec4 f_bw;
layout(location=8) flat in vec4 f_bc;
layout(location=9) flat in vec4 f_grad;
layout(location=10) flat in vec4 f_params;
layout(location=11) flat in vec4 f_uv;
layout(location=12) flat in vec4 f_clip;
layout(location=13) flat in vec4 f_clipr;
layout(location=14) flat in vec4 f_xt;
layout(location=15) flat in vec4 f_extra;
layout(set=2, binding=0) uniform sampler2D u_atlas;
layout(set=2, binding=1) uniform sampler2D u_image;
layout(set=3, binding=0, std140) uniform FragmentUniforms {
	mat4 u_filters[16];
	vec4 u_filter_off[16];
	vec2 u_atlas_size;
	float u_text_gamma;
	float u_text_contrast;
};
layout(location=0) out vec4 o_color;
#include "ui_fs_body.glsl"

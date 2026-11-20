// Shared vertex shader body (GL 3.3 and Vulkan/SPIR-V). Generated layout lives in the headers.
void main() {
	int kind = int(a_params.x);
	vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
	float pad = 1.0;
	if (kind == 1) pad = 3.0 * a_params.y + 2.0;
	if (kind == 3 || kind == 4) pad = 0.0;
	vec2 local = mix(vec2(-pad), a_size.xy + vec2(pad), corner);
	mat2 m = mat2(a_xf.x, a_xf.z, a_xf.y, a_xf.w);
	vec2 world = m * local + a_xt.xy;
	v_local = local;
	v_world = world;
	f_size = a_size; f_radii = a_radii; f_fill0 = a_fill0; f_fill1 = a_fill1; f_fill2 = a_fill2;
	f_bw = a_bw; f_bc = a_bc; f_grad = a_grad; f_params = a_params; f_uv = a_uv;
	f_clip = a_clip; f_clipr = a_clipr; f_xt = a_xt; f_extra = a_extra;
	gl_Position = vec4(world.x / u_viewport.x * 2.0 - 1.0, 1.0 - world.y / u_viewport.y * 2.0, 0.0, 1.0);
}

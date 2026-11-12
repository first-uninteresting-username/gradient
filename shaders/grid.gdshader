// Emissive wireframe grid drawn from UVs (UV = metres across / along the track,
// UV2.x = 0..1 across the profile for the edge rails).
shader_type spatial;
render_mode cull_disabled, specular_disabled, shadows_disabled;

uniform vec4 line_color : source_color = vec4(0.173, 0.965, 1.0, 1.0);
uniform vec4 far_color : source_color = vec4(0.541, 0.361, 1.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.012, 0.02, 0.05, 1.0);
uniform float cell = 2.0;
uniform float line_width = 0.035;
uniform float energy = 2.2;
uniform float rail_energy = 4.5;
uniform float fade_near = 15.0;
uniform float fade_far = 160.0;

varying float view_dist;

void vertex() {
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float grid_line(vec2 coord, float width) {
	vec2 g = coord / cell;
	vec2 fw = max(fwidth(g), vec2(1e-4));
	vec2 dist = abs(fract(g - 0.5) - 0.5);
	vec2 aa = vec2(1.0) - smoothstep(vec2(width / cell), vec2(width / cell) + fw, dist);
	return max(aa.x, aa.y);
}

void fragment() {
	float line = grid_line(UV, line_width);
	float e = UV2.x;
	float fe = max(fwidth(e), 1e-4);
	float rail = 1.0 - smoothstep(0.004, 0.004 + fe * 1.5, min(e, 1.0 - e));
	vec3 tint = mix(line_color.rgb, far_color.rgb, smoothstep(fade_near, fade_far, view_dist));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = fill_color.rgb + tint * (line * energy + rail * rail_energy);
}

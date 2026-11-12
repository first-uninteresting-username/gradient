// White ball with a cyan rim and faint latitude lines so rolling reads.
shader_type spatial;
render_mode specular_disabled, shadows_disabled;

uniform vec4 body_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.173, 0.965, 1.0, 1.0);
uniform float body_energy = 1.1;
uniform float rim_energy = 3.5;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float lat = abs(fract(UV.y * 6.0) - 0.5);
	float lon = abs(fract(UV.x * 8.0) - 0.5);
	float lines = smoothstep(0.46, 0.5, max(lat, lon));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = body_color.rgb * body_energy * (1.0 - 0.45 * lines) + rim_color.rgb * rim * rim_energy;
}

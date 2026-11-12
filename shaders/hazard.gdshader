// Hazards: solid alarm colour with bright edges, optional diagonal stripes for the
// colour-blind palette, and a pulsing outline while a moving hazard telegraphs.
// Hazards ignore the scene fog (they are the gameplay readout) and fade in on their
// own over a longer distance.
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.353, 0.122, 1.0);
uniform float energy = 3.0;
uniform float fill = 0.35;
uniform float edge_width = 0.05;
uniform bool stripes = false;
uniform float telegraph = 0.0;
uniform float fade_start = 320.0;
uniform float fade_end = 180.0;

varying vec3 local_pos;
varying vec3 half_size;
varying float view_dist;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_pos = VERTEX * s;
	half_size = s * 0.5;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec3 d = half_size - abs(local_pos);
	// The smallest distance is the face itself; the middle one is the distance to an edge.
	float mid = d.x + d.y + d.z - min(d.x, min(d.y, d.z)) - max(d.x, max(d.y, d.z));
	float fw = max(fwidth(mid), 1e-4);
	float edge = 1.0 - smoothstep(edge_width, edge_width + fw * 1.5, mid);
	float body = fill;
	if (stripes) {
		float st = step(0.5, fract((local_pos.x + local_pos.y + local_pos.z) * 1.25));
		body = mix(0.04, 0.9, st);
	}
	float pulse = telegraph * (0.5 + 0.5 * sin(TIME * 25.0));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	float vis = 1.0 - smoothstep(fade_end, fade_start, view_dist);
	EMISSION = color.rgb * (body * (1.0 - 0.6 * telegraph) + edge * energy * (1.0 + pulse * 2.5)) * vis;
}

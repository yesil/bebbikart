shader_type spatial;
// Chequered paint (start/finish lines, banners). UV.x across, UV.y along; `cells` squares
// across. depth_pull lifts road paint over the road surface without z-fighting.

uniform vec4 color_a : source_color = vec4(0.95, 0.95, 0.93, 1.0);
uniform vec4 color_b : source_color = vec4(0.06, 0.06, 0.07, 1.0);
uniform vec2 cells = vec2(8.0, 2.0);
uniform float roughness = 0.55;
uniform float depth_pull = 0.0;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xyz *= 1.0 - depth_pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	vec2 c = floor(UV * cells);
	float k = mod(c.x + c.y, 2.0);
	ALBEDO = mix(color_a.rgb, color_b.rgb, k);
	ROUGHNESS = roughness;
}

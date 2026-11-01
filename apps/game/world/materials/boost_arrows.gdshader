shader_type spatial;
// The boost arrows on the road (contracts §2g): glowing chevrons with a light running forward
// along the strip (UV.x: the chevron's place along it, 0 first .. 1 last).
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 0.5, 0.08, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.95, 0.45, 1.0);
uniform float speed = 6.0;

void fragment() {
	float wave = 0.5 + 0.5 * sin(TIME * speed - UV.x * 9.0);
	// Above 1.0 so the countryside's glow picks it up.
	ALBEDO = mix(base_color.rgb, hot_color.rgb, wave) * (1.0 + 0.7 * wave);
}

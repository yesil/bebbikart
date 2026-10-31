shader_type spatial;
render_mode cull_disabled;
// Cloth flag/banner that ripples more as the weather's wind picks up. UV.x = 0 at the pole.

uniform vec4 color : source_color = vec4(0.9, 0.2, 0.2, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float stripes = 0.0;     // 0 = plain, n = horizontal stripes
uniform float amplitude = 0.12;
global uniform float wind_strength;

void vertex() {
	float w = 0.3 + wind_strength * 1.4;
	float phase = TIME * (3.0 + wind_strength * 4.0) - UV.x * 7.0 + MODEL_MATRIX[3].x;
	VERTEX.z += sin(phase) * amplitude * w * UV.x;
	VERTEX.y += cos(phase * 0.7) * amplitude * 0.3 * w * UV.x;
}

void fragment() {
	vec3 c = color.rgb;
	if (stripes > 0.0 && mod(floor(UV.y * stripes), 2.0) > 0.5) {
		c = color2.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 0.8;
	BACKLIGHT = c * 0.4;
}

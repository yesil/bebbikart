shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Pond and stream water: colour from the depth of water under each pixel (clear shallows over
// the ford, darker deep water), two scrolling normal maps, soft foam where it meets the shore,
// and stronger ripples while it rains (road_wetness).

uniform vec4 shallow_color : source_color = vec4(0.32, 0.62, 0.58, 1.0);
uniform vec4 deep_color : source_color = vec4(0.06, 0.24, 0.30, 1.0);
uniform float depth_fade = 1.4;          // 1/m: how quickly the colour reaches deep_color
uniform float clarity = 0.35;            // alpha in the shallowest water
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.12;         // 1/m
uniform vec2 flow = vec2(0.015, 0.008);  // m/s in texture space
uniform float foam_width = 0.18;         // metres of water depth that show foam
uniform vec4 foam_color : source_color = vec4(0.92, 0.95, 0.95, 1.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform float road_wetness;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * wave_scale;
	float rain = clamp(road_wetness, 0.0, 1.0);
	vec3 n1 = texture(normal_a, uv + TIME * flow).rgb;
	vec3 n2 = texture(normal_b, uv * 1.9 - TIME * flow * 1.6 + vec2(0.3, 0.7)).rgb;
	vec3 n3 = texture(normal_b, uv * 6.0 + TIME * vec2(0.05, -0.04)).rgb;
	NORMAL_MAP = normalize(mix(mix(n1, n2, 0.5), n3, rain * 0.6));
	NORMAL_MAP_DEPTH = 0.5 + rain * 0.7;

	// Water thickness along the view ray (view space).
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	behind.xyz /= behind.w;
	float thick = max(VERTEX.z - behind.z, 0.0);
	float t = 1.0 - exp(-thick * depth_fade);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);
	float foam = (1.0 - smoothstep(0.0, foam_width, thick)) * (0.55 + 0.45 * n2.r);
	ALBEDO = mix(col, foam_color.rgb, foam * 0.7);
	ALPHA = clamp(mix(clarity, 0.94, t) + foam * 0.4, 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.12, rain);
	SPECULAR = 0.6;
}

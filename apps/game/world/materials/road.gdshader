shader_type spatial;
// Road surface for Road Generator meshes. Surface textures are sampled in world space so
// overlapping roads (the shared stub of a Y-split) look identical; the generator's lane UVs
// (1/8-wide atlas columns, column 0 = shoulders) only drive the painted edge lines.
// Detour branches set depth_pull > 0 so they draw over the direct branch where they overlap,
// which leaves their inner edge line as the painted split between the two alternatives.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile_m = 4.0;                 // metres per texture repeat
uniform float roughness_bias = 0.0;
uniform float normal_depth = 1.0;           // relief of the aggregate (1 = the texture's own)
uniform float grain_blur = 0.0;             // mip bias: softens the stones in the texture
uniform float desaturate = 0.0;             // 1 = plain grey (no coloured flecks)
uniform bool edge_lines = true;
uniform vec4 line_color : source_color = vec4(0.93, 0.93, 0.88, 1.0);
uniform float line_inset = 0.025;           // fraction of the lane width
uniform float line_width = 0.035;
uniform vec4 shoulder_color : source_color = vec4(0.42, 0.40, 0.36, 1.0);
uniform float depth_pull = 0.0;             // fraction of view distance pulled towards the camera
global uniform float road_wetness;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Always write POSITION: once a shader writes it, Godot uses it for every vertex.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xyz *= 1.0 - depth_pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	vec3 base = texture(albedo_tex, uv, grain_blur).rgb;
	base = mix(base, vec3(dot(base, vec3(0.299, 0.587, 0.114))), desaturate) * tint.rgb;
	// Low-frequency patchiness so long straights don't read as one repeating tile.
	float patch = texture(albedo_tex, world_pos.xz / (tile_m * 9.7) + vec2(0.37, 0.11)).r;
	base *= mix(0.9, 1.08, patch);
	float rough = clamp(texture(rough_tex, uv, grain_blur).r + roughness_bias, 0.0, 1.0);
	float col = floor(UV.x * 8.0);
	float lane = fract(UV.x * 8.0);
	if (col < 0.5) {
		// Shoulder strip (outer bevel).
		base = mix(base, shoulder_color.rgb, 0.65);
	} else if (edge_lines) {
		float d = min(lane, 1.0 - lane);
		float aa = fwidth(lane) * 1.5;
		float paint = smoothstep(line_inset - aa, line_inset, d) * (1.0 - smoothstep(line_inset + line_width, line_inset + line_width + aa, d));
		base = mix(base, line_color.rgb, paint);
		rough = mix(rough, 0.55, paint);
	}
	// Wet roads darken and turn glossy.
	float wet = clamp(road_wetness, 0.0, 1.0);
	base *= mix(1.0, 0.62, wet);
	rough = mix(rough, 0.12, wet * 0.85);
	ALBEDO = base;
	ROUGHNESS = rough;
	NORMAL_MAP = texture(normal_tex, uv, grain_blur).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.4, wet);
	SPECULAR = 0.4;
}

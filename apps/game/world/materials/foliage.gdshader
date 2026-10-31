shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Leaves, grass and flowers: alpha-scissor cut-outs lit from behind, swaying with the weather's
// wind (global wind_strength 0..1 and wind_dir). Sway grows with height so trunks stay put; each
// plant gets its own phase from its world position.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.45;
uniform float sway = 0.18;          // metres of sideways sway at the top in a calm breeze
uniform float sway_height = 6.0;    // model-space height that gets the full sway
uniform vec4 backlight_color : source_color = vec4(0.32, 0.40, 0.12, 1.0);
uniform float roughness = 0.75;
uniform vec3 crown_center = vec3(0.0, 4.0, 0.0);  // model space; leaf normals bend away from it
uniform float normal_bend = 0.85;    // 0 = card normals, 1 = round crown
uniform float recolor = 0.0;         // 0 = texture colours, 1 = texture luminance in recolor_tint
uniform vec4 recolor_tint : source_color = vec4(0.35, 0.62, 0.22, 1.0);
uniform float variation = 0.18;      // per-plant brightness/hue variation
global uniform float wind_strength;
global uniform vec2 wind_dir;

varying float vary;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vary = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX - crown_center), normal_bend));
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float t = TIME * 1.4 + dot(origin.xz, vec2(0.13, 0.17));
	float w = 0.35 + wind_strength * 1.6;
	vec2 gust = wind_dir * (0.6 + 0.4 * sin(t)) * wind_strength * 1.5;
	vec2 flutter = vec2(sin(t * 2.3 + VERTEX.x * 1.7), cos(t * 1.9 + VERTEX.z * 1.3)) * 0.35;
	vec2 off = (gust + flutter * w) * sway * h * h;
	// World-space offset into model space.
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(off.x, 0.0, off.y));
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(c.rgb, recolor_tint.rgb * luma * 2.2, recolor) * tint.rgb;
	col *= mix(1.0 - variation, 1.0 + variation * 0.6, vary);
	col.g *= mix(1.0, 1.08, vary);
	ALBEDO = col;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	BACKLIGHT = backlight_color.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
}

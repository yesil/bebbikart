shader_type spatial;
// Window panes of the village buildings (world/village/chalet_builder.gd): dark, smooth glass
// that mirrors the sky at a glancing angle, with white lace curtains behind some of them.
//   UV      0..1 across the pane (u left to right, v top to bottom).
//   COLOR.r curtain style of this window (0 none, < 0.5 café curtain over the lower half,
//           else drapes at both sides); COLOR.g a per-window shade of the room behind.

uniform vec4 glass_color : source_color = vec4(0.05, 0.065, 0.08, 1.0);
uniform vec4 curtain_color : source_color = vec4(0.86, 0.85, 0.8, 1.0);
uniform float roughness = 0.04;
uniform float specular = 0.75;

void fragment() {
	float style = COLOR.r;
	float curtain = 0.0;
	if (style > 0.02 && style < 0.5) {
		// Café curtain on a rod across the middle, its hem scalloped.
		float top = 0.42 + 0.02 * sin(UV.x * 31.4);
		curtain = step(top, UV.y);
	} else if (style >= 0.5) {
		// Drapes gathered to both sides, with soft folds.
		float side = min(UV.x, 1.0 - UV.x);
		curtain = 1.0 - smoothstep(0.18, 0.2, side + 0.04 * UV.y);
	}
	float folds = 0.82 + 0.18 * sin(UV.x * 90.0);
	float lace = 0.9 + 0.1 * step(0.5, fract(UV.x * 40.0) + fract(UV.y * 40.0) * 0.5);
	vec3 room = glass_color.rgb * (0.6 + 0.8 * COLOR.g);
	ALBEDO = mix(room, curtain_color.rgb * folds * lace * 0.55, curtain);
	ROUGHNESS = mix(roughness, 0.35, curtain * 0.4);
	SPECULAR = specular;
	METALLIC = 0.0;
}

// Shared soft "vinyl toy" material for every racer part.
// Colour comes from per-instance uniforms, so all parts share one material.
shader_type spatial;
render_mode depth_draw_opaque;

instance uniform vec4 albedo : source_color = vec4(1.0);
instance uniform float glow = 0.0;

uniform float shade_floor = 0.38;     // darkest the lit side falls to (soft, not black)
uniform float band_softness = 0.32;   // width of the light→shadow transition
uniform float gloss = 0.35;           // vinyl highlight strength
uniform float rim = 0.28;             // soft rim light

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * glow;
	ROUGHNESS = 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.1, band_softness, ndl);
	float diffuse = mix(shade_floor, 1.0, band);
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;

	vec3 h = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, h), 0.0), 48.0);
	spec = smoothstep(0.35, 0.6, spec) * gloss;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR / PI;

	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * band;
	DIFFUSE_LIGHT += r * rim * ATTENUATION * LIGHT_COLOR / PI;
}

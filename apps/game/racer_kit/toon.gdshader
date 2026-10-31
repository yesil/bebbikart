// Shared soft "vinyl toy" material for every racer part.
// Colour, pattern and finish come from per-instance uniforms, so all parts share one material.
shader_type spatial;
render_mode depth_draw_opaque;

instance uniform vec4 albedo : source_color = vec4(1.0);
instance uniform float glow = 0.0;
// Pattern painted over the part (RacerSpec pattern.type, see KitMaterial.PATTERNS):
// 0 none, 1 stripes, 2 spots, 3 stars, 4 hearts, 5 zigzag, 6 checks, 7 crayon, 8 swirl.
instance uniform int pattern = 0;
instance uniform vec4 pattern_color : source_color = vec4(1.0);
instance uniform float pattern_scale = 1.0;
// Finish (KitMaterial.FINISHES): 0 glossy, 1 matte, 2 metallic, 3 sparkle, 4 glow.
instance uniform int finish = 0;

uniform float shade_floor = 0.38;     // darkest the lit side falls to (soft, not black)
uniform float band_softness = 0.32;   // width of the light→shadow transition
uniform float gloss = 0.35;           // vinyl highlight strength
uniform float rim = 0.28;             // soft rim light

varying vec3 obj_pos;   // object-space position scaled to metres (pattern stays put when animated)
varying vec3 obj_nrm;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	return vec3(hash13(p), hash13(p + 17.17), hash13(p + 41.41));
}

float star_sdf(vec2 p, float r) {
	// 5-point star (iq).
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = 0.42 * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float heart_sdf(vec2 p) {
	p.y += 0.5;
	p.x = abs(p.x);
	if (p.y + p.x > 1.0)
		return sqrt(dot(p - vec2(0.25, 0.75), p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	return sqrt(min(dot(p - vec2(0.0, 1.0), p - vec2(0.0, 1.0)),
		dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Projects onto the plane facing the dominant normal axis (cheap triplanar).
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > a.y && a.x > a.z) return p.zy;
	if (a.y > a.z) return p.xz;
	return p.xy;
}

// 1 where the pattern colour shows, 0 elsewhere (anti-aliased).
float pattern_mask(vec3 p, vec3 n) {
	float s = 1.0 / max(pattern_scale, 0.05);
	vec3 q = p * s;
	float aa = 0.04;
	if (pattern == 1) { // stripes: bands around the part
		float v = sin(q.y * 26.0);
		return smoothstep(0.25 - aa * 6.0, 0.25 + aa * 6.0, v);
	} else if (pattern == 2) { // spots: jittered 3D cells
		vec3 c = q * 9.0;
		vec3 i = floor(c);
		float d = 9.0;
		for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
			vec3 o = vec3(float(x), float(y), float(z));
			vec3 h = hash33(i + o);
			float r = 0.22 + 0.16 * h.x;
			d = min(d, length(c - (i + o + 0.2 + 0.6 * h)) - r);
		}
		return 1.0 - smoothstep(-aa * 3.0, aa * 3.0, d);
	} else if (pattern == 3 || pattern == 4) { // stars / hearts on a staggered grid
		vec2 uv = plane_uv(q, n) * 7.0;
		uv.x += step(1.0, mod(floor(uv.y), 2.0)) * 0.5;
		vec2 cell = fract(uv) - 0.5;
		float d = pattern == 3 ? star_sdf(cell * 2.2, 0.5) : heart_sdf(cell * 2.6);
		return 1.0 - smoothstep(-aa, aa, d);
	} else if (pattern == 5) { // zigzag bands
		float z = abs(fract((q.x + q.z) * 6.0) - 0.5) * 0.18;
		float v = sin((q.y + z) * 24.0);
		return smoothstep(0.3 - aa * 6.0, 0.3 + aa * 6.0, v);
	} else if (pattern == 6) { // checks
		vec3 c = floor(q * 7.0);
		return mod(c.x + c.y + c.z, 2.0);
	} else if (pattern == 7) { // crayon: wobbly diagonal hatching like colouring-in
		vec2 uv = plane_uv(q, n) * 40.0;
		float w = sin(uv.x * 0.37 + sin(uv.y * 0.21) * 2.0) * 0.6;
		float v = sin(uv.x + uv.y + w);
		float grain = hash13(floor(p * 220.0));
		return smoothstep(0.35, 0.75, v) * (0.55 + 0.45 * grain);
	} else if (pattern == 8) { // swirl
		float a = atan(q.x, q.z);
		float v = sin(a * 3.0 + q.y * 30.0 + length(q.xz) * 20.0);
		return smoothstep(0.2 - aa * 6.0, 0.2 + aa * 6.0, v);
	}
	return 0.0;
}

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	obj_pos = VERTEX * s;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 col = albedo.rgb;
	if (pattern > 0) {
		col = mix(col, pattern_color.rgb, pattern_mask(obj_pos, normalize(obj_nrm)));
	}
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 0.5;
	if (finish == 2) { // metallic
		METALLIC = 0.6;
		ROUGHNESS = 0.25;
	} else if (finish == 4) { // glow
		EMISSION = col * max(glow, 0.45);
	} else if (finish == 3) { // sparkle: glitter specks that twinkle as the view changes
		vec3 cell = floor(obj_pos * 70.0);
		float h = hash13(cell);
		float tw = 0.5 + 0.5 * sin(TIME * 3.0 + h * 40.0 + dot(VIEW, vec3(7.0, 3.0, 5.0)));
		EMISSION += step(0.965, h) * tw * mix(vec3(1.0), col, 0.3) * 0.9;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.1, band_softness, ndl);
	float diffuse = mix(shade_floor, 1.0, band);
	float k_gloss = gloss;
	float k_pow = 48.0;
	if (finish == 1) { k_gloss = 0.05; }
	else if (finish == 2) { k_gloss = 0.9; k_pow = 24.0; diffuse *= 0.8; }
	else if (finish == 3) { k_gloss = 0.6; }
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;

	vec3 h = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, h), 0.0), k_pow);
	spec = smoothstep(0.35, 0.6, spec) * k_gloss;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR / PI;

	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * band;
	DIFFUSE_LIGHT += r * rim * ATTENUATION * LIGHT_COLOR / PI;
}

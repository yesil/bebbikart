shader_type spatial;
// Village buildings (world/village/chalet_builder.gd). One shader for every building material
// (stone, plaster, timber, boards, painted wood, shingles, slate, clay tiles); each material
// sets its texture set and how it weathers.
//   UV      metres along the surface (texel density stays even on every piece).
//   COLOR   rgb: tint of this piece (the house's timber tone, the shutter paint, ...), linear.
//           a: rain streaks (1 just under a window sill, fading to 0 further down).
//   UV2     x: pattern (0 none, 1 log courses, 2/3 flame stripes leaning right/left,
//           4 louvres, 5 dressed stone blocks), y: height above the building's floor in metres.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile_m = vec2(2.0, 2.0);       // metres per texture repeat (u, v)
uniform vec4 tint : source_color = vec4(1.0);
uniform float albedo_gain = 1.0;
uniform float desaturate = 0.0;             // grey the texture before tinting (1 = only its tone)
// The texture is divided by tone_mean (its mean linear luminance) so a piece's COLOR is close
// to its final albedo; contrast scales the texture's detail around that. tone_mean = 1 and
// contrast = 1 keep the texture as it is (COLOR then only tints it).
uniform float tone_mean = 1.0;
uniform float contrast = 1.0;
uniform float normal_depth = 1.0;
uniform vec2 roughness_range = vec2(0.6, 0.95);
uniform float ao_strength = 0.0;
uniform float course_m = 0.0;               // log course height (pattern 1)
uniform float grime = 0.4;                  // darker, browner wall foot (splash zone)
uniform float grime_height = 0.9;
uniform float streaks = 0.45;
uniform float sun_fade = 0.0;               // paler, greyer timber on faces turned to the sun
uniform vec3 sun_dir = vec3(0.432, 0.741, 0.515);
uniform float patchiness = 0.12;            // low-frequency tone variation over a surface
uniform float wet_gloss = 0.5;              // how much rain darkens and glosses the surface
global uniform float road_wetness;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int pattern = int(UV2.x + 0.5);
	float height = UV2.y;
	vec2 uv = UV / tile_m;
	float shade = 1.0;
	float cavity = 1.0;
	vec3 nmod = vec3(0.0);
	if (pattern == 1 && course_m > 0.0) {
		// Log courses (Blockbau): each log has its own grain offset and tone, with a dark,
		// sunken joint between logs.
		float c = UV.y / course_m;
		float ci = floor(c);
		float f = fract(c);
		uv.x += hash11(ci) * 7.31;
		uv.y = (f * course_m + hash11(ci + 3.7) * 3.0) / tile_m.y;
		shade = 0.86 + 0.26 * hash11(ci + 11.3);
		float joint = smoothstep(0.0, 0.09, f) * smoothstep(1.0, 0.86, f);
		cavity = mix(0.35, 1.0, joint);
		// Rounded log faces: the normal tips up near the top edge and down near the bottom.
		nmod.y = (f - 0.5) * 1.1 * (1.0 - joint * 0.3);
	} else if (pattern == 5) {
		// Ashlar: dressed blocks in courses, each a little different, with sunken joints.
		vec2 b = vec2(UV.x / 0.68, UV.y / 0.34);
		b.x += mod(floor(b.y), 2.0) * 0.5;
		vec2 f = fract(b);
		float joint = smoothstep(0.0, 0.035, f.x) * smoothstep(1.0, 0.965, f.x) * smoothstep(0.0, 0.07, f.y) * smoothstep(1.0, 0.93, f.y);
		cavity = mix(0.4, 1.0, joint);
		shade = 0.9 + 0.2 * hash21(floor(b));
		uv += hash21(floor(b) + 3.1) * 5.0;
	}
	vec3 tex = texture(albedo_tex, uv).rgb;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	tex = mix(tex, vec3(lum), desaturate);
	tex = max((tex / tone_mean - 1.0) * contrast + 1.0, vec3(0.0));
	vec3 col = tex * albedo_gain * tint.rgb * COLOR.rgb * shade * mix(1.0, cavity, 0.75);
	if (pattern == 2 || pattern == 3) {
		// Flame stripes on shutters: diagonal bands, the two leaves leaning opposite ways.
		float lean = pattern == 2 ? 1.0 : -1.0;
		float t = (UV.x * lean + UV.y) / 0.26;
		float band = smoothstep(0.45, 0.5, fract(t)) * smoothstep(1.0, 0.95, fract(t));
		col = mix(col, vec3(0.82, 0.8, 0.74) * tex * 1.6, band);
	} else if (pattern == 4) {
		// Louvres: slanted slats, shadowed under each one.
		float f = fract(UV.y / 0.07);
		cavity *= mix(0.45, 1.0, smoothstep(0.0, 0.35, f));
		nmod.y += (f - 0.5) * 1.4;
	}
	// Low-frequency patches so big walls and roofs don't read as one repeating tile.
	float p = noise2(world_pos.xz * 0.5 + world_pos.y * 0.3);
	col *= 1.0 + (p - 0.5) * 2.0 * patchiness;
	// Sun-faded timber: the faces turned to the sun go paler and greyer.
	if (sun_fade > 0.0) {
		vec2 sd = normalize(sun_dir.xz);
		float lit = clamp(dot(normalize(world_nrm.xz + vec2(1e-4)), sd), 0.0, 1.0) * (1.0 - abs(world_nrm.y));
		float g = dot(col, vec3(0.3333));
		col = mix(col, vec3(g) * 1.25, lit * sun_fade);
	}
	// Splash zone: the wall foot is darker and browner, unevenly.
	if (height < grime_height && grime > 0.0) {
		float foot = (1.0 - smoothstep(0.0, grime_height, height)) * grime;
		foot *= 0.65 + 0.35 * noise2(world_pos.xz * 2.1 + world_pos.y * 3.0);
		col = mix(col, col * vec3(0.55, 0.5, 0.43), foot);
	}
	// Rain streaks under the sills: thin vertical runs of grime.
	if (COLOR.a > 0.002 && streaks > 0.0) {
		float runs = noise2(vec2((world_pos.x + world_pos.z) * 9.0, world_pos.y * 0.6));
		col *= 1.0 - COLOR.a * streaks * smoothstep(0.35, 0.8, runs) * 0.55;
	}
	float wet = clamp(road_wetness, 0.0, 1.0) * wet_gloss;
	col *= mix(1.0, 0.65, wet);
	ALBEDO = col;
	float r = texture(rough_tex, uv).r;
	ROUGHNESS = mix(mix(roughness_range.x, roughness_range.y, r), 0.2, wet);
	vec3 nm = texture(normal_tex, uv).rgb;
	nm.xy += nmod.xy * 0.5;
	NORMAL_MAP = clamp(nm, 0.0, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	AO = (ao_strength > 0.0 ? mix(1.0, texture(ao_tex, uv).r, ao_strength) : 1.0) * cavity;
	AO_LIGHT_AFFECT = 0.35;
}

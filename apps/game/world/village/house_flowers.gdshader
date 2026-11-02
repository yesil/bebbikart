shader_type spatial;
render_mode cull_back, diffuse_burley;
// Geraniums in the window and balcony boxes (world/village/chalet_builder.gd _geraniums): a few
// round low-poly blobs per box, with the detail painted here from 3D cell patterns, so they stay
// cheap. Leaf cushions get lobed leaves (lighter centres, darker rims) and, on top, more flower
// heads; flower heads are balls of small florets.
//   COLOR.rgb  base colour (linear): leaf green, or the blossom colour
//   COLOR.a    0 leaves, 1 flower head

uniform vec4 blossom_color : source_color = vec4(0.86, 0.06, 0.08, 1.0);
uniform float floret_scale = 55.0;      // florets per metre
uniform float leaf_scale = 13.0;        // leaves per metre
uniform float head_scale = 8.0;         // painted heads on the leaves, per metre

varying vec3 wp;
varying vec3 wn;

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest jittered cell point, and that cell's random value.
vec2 cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = hash33(i + g);
				vec3 d = g + h - f;
				float dd = dot(d, d);
				if (dd < best) {
					best = dd;
					id = h.x;
				}
			}
		}
	}
	return vec2(sqrt(best), id);
}

vec3 florets(vec3 base) {
	vec2 f = cells(wp * floret_scale);
	float petal = 1.0 - smoothstep(0.2, 0.62, f.x);
	return base * mix(0.38, 1.12, petal) * (0.88 + 0.24 * f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col;
	if (COLOR.a > 0.5) {
		col = florets(COLOR.rgb);
		ROUGHNESS = 0.55;
	} else {
		vec2 l = cells(wp * leaf_scale);
		// Round leaves: lighter in the middle, a darker zone and rim, each its own shade.
		float rim = smoothstep(0.2, 0.75, l.x);
		col = COLOR.rgb * mix(1.05, 0.38, rim) * (0.7 + 0.5 * l.y);
		// Flower heads among the leaves on top of the cushion.
		vec2 h = cells(wp * head_scale);
		float head = (1.0 - smoothstep(0.2, 0.34, h.x)) * step(0.45, h.y) * smoothstep(-0.2, 0.5, wn.y);
		col = mix(col, florets(blossom_color.rgb), head);
		ROUGHNESS = mix(0.72, 0.55, head);
	}
	ALBEDO = col;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.05, 0.07, 0.02);
}

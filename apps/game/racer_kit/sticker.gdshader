// Rounded sticker with a white border, used for the kid's drawing on the ride.
shader_type spatial;

uniform sampler2D drawing : source_color, filter_linear_mipmap;
uniform vec4 border_color : source_color = vec4(1.0);
uniform float corner = 0.2;
uniform float border = 0.07;

void fragment() {
	vec2 p = abs(UV - 0.5);
	vec2 q = p - (vec2(0.5) - corner);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner;
	if (d > 0.0) {
		discard;
	}
	vec2 uv2 = (UV - 0.5) / (1.0 - 2.0 * border) + 0.5;
	vec3 c = texture(drawing, clamp(uv2, 0.0, 1.0)).rgb;
	ALBEDO = (d > -border) ? border_color.rgb : c;
	ROUGHNESS = 0.7;
}

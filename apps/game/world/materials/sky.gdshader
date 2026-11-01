shader_type sky;
// Poly Haven HDRI sky that the weather can turn overcast: `gloom` (0..1, set by weather_fx)
// blends the panorama towards a grey overcast gradient and dims it, smoothly. `rotation` turns
// the panorama about the vertical (radians) so its sun can sit where a track's sun light is.

uniform sampler2D panorama : source_color, filter_linear;
uniform float exposure = 1.0;
uniform float gloom = 0.0;
uniform float rotation = 0.0;
uniform vec4 overcast_top : source_color = vec4(0.40, 0.44, 0.50, 1.0);
uniform vec4 overcast_horizon : source_color = vec4(0.66, 0.69, 0.72, 1.0);
uniform vec4 ground_color : source_color = vec4(0.30, 0.36, 0.26, 1.0);

void sky() {
	vec2 uv = vec2(fract((atan(EYEDIR.x, -EYEDIR.z) - rotation) / TAU + 0.5), acos(clamp(EYEDIR.y, -1.0, 1.0)) / PI);
	vec3 c = texture(panorama, uv).rgb;
	// The pure-sky HDRI has no ground: fade to a soft ground tone below the horizon.
	c = mix(c, ground_color.rgb, smoothstep(0.0, -0.08, EYEDIR.y));
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 over = mix(overcast_horizon.rgb, overcast_top.rgb, sqrt(h));
	c = mix(c, over, gloom * 0.85);
	COLOR = c * exposure * mix(1.0, 0.75, gloom);
}

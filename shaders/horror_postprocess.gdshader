shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float fear : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.45;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.035;
uniform float aberration_strength : hint_range(0.0, 0.01) = 0.0015;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);

	// Subtle heartbeat pulse zoom/shake
	float p = pulse * 0.003;
	uv += centered * p * sin(TIME * 8.0);

	// Chromatic aberration increases with fear
	float ab = aberration_strength + fear * 0.003;
	float r = texture(screen_texture, uv + vec2(ab, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(ab, 0.0)).b;
	vec3 color = vec3(r, g, b);

	// Film grain
	float grain = (rand(uv * TIME * 60.0) - 0.5) * (grain_strength + fear * 0.05);
	color += grain;

	// Vignette
	float vig = smoothstep(0.75, 0.2 - fear * 0.08, dist * (1.0 + vignette_strength + fear * 0.5));
	color *= mix(0.25, 1.0, vig);

	// Fear tint: slight red/dark desaturation
	vec3 fear_tint = vec3(color.r * 1.1, color.g * 0.85, color.b * 0.85);
	color = mix(color, fear_tint, fear * 0.35);
	color *= 1.0 - fear * 0.15;

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}

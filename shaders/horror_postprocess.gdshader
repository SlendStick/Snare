shader_type canvas_item;

// Полноэкранная поставка: зерно, хроматическая аберрация, виньетка и «красный» страх.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float time = 0.0;
uniform float fear = 0.0;
uniform float shake = 0.0;
uniform float grain_amount = 0.024;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);
	vec2 dir = normalize(centered + vec2(0.00001));

	// Лёгкое дрожание камеры при страхе.
	uv += vec2(sin(time * 37.0), cos(time * 43.0)) * shake * 0.0015;

	float aberration = (0.0006 + fear * 0.0030 + shake * 0.0015) * dist;
	float r = texture(screen_tex, uv + dir * aberration).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - dir * aberration).b;
	vec3 col = vec3(r, g, b);

	float grain = hash12(floor(uv * vec2(1366.0, 768.0)) + floor(time * 24.0));
	col += (grain - 0.5) * (grain_amount + fear * 0.030);

	float vignette = 1.0 - smoothstep(0.26, 0.82, dist);
	col *= mix(1.0, vignette, 0.42 + fear * 0.30);
	col = mix(col, vec3(col.r * 1.25, col.g * 0.32, col.b * 0.26), fear * dist * 0.42);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}

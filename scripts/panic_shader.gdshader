shader_type canvas_item;

uniform float panic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// 1. КАЧАНИЕ (Головокружение до выстрела)
	if (panic_intensity > 0.0) {
		float wave_x = sin(TIME * 0.3) * 0.015;
		float wave_y = cos(TIME * 0.15) * 0.015;
		uv.x += wave_x * panic_intensity;
		uv.y += wave_y * panic_intensity;
	}
	
	// 2. РАВНОМЕРНОЕ МЫЛО (Потеря фокуса)
	vec2 center_dist = SCREEN_UV - vec2(0.3);
	float dist_factor = smoothstep(0.0, 0.3, length(center_dist)) + 0.2; 
	float blur_amount = dist_factor * panic_intensity * 0.02;
	
	vec4 color = vec4(0.0);
	float total_weight = 0.0;
	
	for(float x = -1.0; x <= 1.0; x += 0.5) {
		for(float y = -1.0; y <= 1.0; y += 0.5) {
			float weight = 0.5 - (length(vec2(x, y)) / 1.5);
			if (weight > 0.0) {
				vec2 offset = vec2(x, y) * blur_amount;
				color += texture(SCREEN_TEXTURE, uv + offset) * weight;
				total_weight += weight;
			}
		}
	}
	color /= total_weight;
	
	COLOR = color;
}

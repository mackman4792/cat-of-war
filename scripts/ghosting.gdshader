shader_type canvas_item;

// Сдвиг в пикселях (расстояние между контурами)
uniform float ghost_pixel_shift : hint_range(0.0, 20.0) = 5.0;
// ИНТЕНСИВНОСТЬ (ЯРКОСТЬ) ДВОЕНИЯ: 0.0 = не видно, 1.0 = максимальный хардкор
uniform float ghost_intensity : hint_range(0.0, 1.0) = 0.2;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 base_color = texture(SCREEN_TEXTURE, SCREEN_UV);
	vec2 pixel_size = SCREEN_PIXEL_SIZE * ghost_pixel_shift;
	
	vec2 ghost_uv_r = SCREEN_UV + vec2(pixel_size.x, pixel_size.y * 0.5);
	vec2 ghost_uv_b = SCREEN_UV - vec2(pixel_size.x * 0.7, pixel_size.y * 0.3);
	
	float ghost_red = texture(SCREEN_TEXTURE, ghost_uv_r).r;
	float ghost_blue = texture(SCREEN_TEXTURE, ghost_uv_b).b;
	
	vec3 final_color = base_color.rgb;
	
	// Теперь яркость шлейфа динамически регулируется через ghost_intensity!
	final_color.r = mix(final_color.r, ghost_red, ghost_intensity);
	final_color.b = mix(final_color.b, ghost_blue, ghost_intensity * 0.75);
	
	COLOR = vec4(final_color, 1.0);
}

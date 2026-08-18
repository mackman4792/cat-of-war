shader_type spatial;
// blend_add заставляет шейдер работать как "экран" в фотошопе (только осветлять)
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

uniform float outline_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.5, 0.2, 0.05, 1.0);
uniform float glow_power : hint_range(0.1, 8.0) = 4.0;

void fragment() {
	// Вычисляем свечение по краям
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), glow_power);
	
	// В обычном состоянии (intensity = 0) всё полностью прозрачно
	// При наведении (intensity = 1) грани начинают мягко светиться поверх текстуры
	ALBEDO = glow_color.rgb * fresnel * outline_intensity * 1.5;
}

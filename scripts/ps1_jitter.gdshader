shader_type spatial;
render_mode vertex_lighting, diffuse_lambert_wrap, specular_disabled;

// Текстура твоей модели
uniform sampler2D albedo_texture : filter_nearest; 
// Сила дрожания (чем меньше число, тем сильнее шаг сетки округления)
uniform float jitter_strength : hint_range(0.0, 1.0) = 0.5;

void vertex() {
    // Переводим координаты вершины в пространство экрана (Clip Space)
    vec4 clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    
    // Вычисляем разрешение "виртуального экрана" PS1
    // Обычное разрешение консоли было около 320x240
    vec2 snap_res = vec2(320.0, 240.0) * (1.0 - jitter_strength * 0.5);
    
    // Округляем позицию вершин до пиксельной сетки экрана
    clip_position.xyz /= clip_position.w;
    clip_position.xy = floor(clip_position.xy * snap_res) / snap_res;
    clip_position.xyz *= clip_position.w;
    
    POSITION = clip_position;
}

void fragment() {
    // Накладываем текстуру без сглаживания
    vec4 tex = texture(albedo_texture, UV);
    ALBEDO = tex.rgb;
}

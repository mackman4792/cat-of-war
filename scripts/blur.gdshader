shader_type canvas_item;

// Ссылка на текстуру экрана (автоматически берется из BackBufferCopy)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Ползунок для регулировки силы размытия в инспекторе
uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;

void fragment() {
    // Читаем текстуру экрана с указанием уровня размытия (LOD)
    vec4 color = textureLod(screen_texture, SCREEN_UV, blur_amount);
    
    // Слегка затемняем размытый фон для лучшей читаемости текста меню
    color.rgb *= 0.8; 
    
    COLOR = color;
}

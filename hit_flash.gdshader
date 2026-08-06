shader_type canvas_item;

// 控制閃白強度的變數 (0.0 表示原本顏色，1.0 表示全白)
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    // 保持像素原本的 Alpha 透明度，僅將顏色混合為純白
    COLOR = mix(texture_color, vec4(flash_color.rgb, texture_color.a), flash_modifier);
}
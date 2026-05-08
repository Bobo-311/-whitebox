shader_type canvas_item;

uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
// 🌟 把顏色從 (1.0, 0.0, 0.0) 紅色，改成 (1.0, 1.0, 1.0) 白色
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	color.rgb = mix(color.rgb, flash_color.rgb, flash_modifier);
	COLOR = color;
}

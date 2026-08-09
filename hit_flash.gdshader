shader_type canvas_item;

uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 🆕【絕殺招式】我們自建一個狀態顏色通道！預設為純白色
uniform vec4 state_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// 🌟 改用我們自己定義的 state_color，徹底拋棄容易壞掉的內建 COLOR！
	vec4 base_color = tex_color * state_color;
	
	// 最後疊加白閃
	COLOR = mix(base_color, vec4(flash_color.rgb, base_color.a), flash_modifier);
}
shader_type canvas_item;

// 🌟 宣告一個可以在外部控制的變數：飽和度 (1.0 = 全彩，0.0 = 黑白)
uniform float saturation : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// 取出這顆像素原本的顏色，並乘上 COLOR (這能保留你原本 player_hurt.gd 裡的受傷閃紅光效果)
	vec4 color = texture(TEXTURE, UV) * COLOR;

	// 算出這顆像素的「灰階值」(這是一套標準的人眼亮度權重公式)
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));

	// 根據我們的 saturation 變數，在「純灰階」與「原始顏色」之間做混合
	color.rgb = mix(vec3(gray), color.rgb, saturation);

	// 把計算好的顏色輸出到螢幕上
	COLOR = color;
}
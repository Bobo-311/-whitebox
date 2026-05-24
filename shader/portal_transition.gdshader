shader_type canvas_item;

// 這是一個可以在屬性面板調整的開關：數字越大洞越大，0.0 就是全黑
uniform float circle_radius : hint_range(0.0, 1.5) = 1.5;

void fragment() {
	// 計算畫面長寬比例，確保洞是「正圓形」而不是橢圓
	float ratio = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
	vec2 center_uv = UV - vec2(0.5, 0.5);
	center_uv.x *= ratio;

	// 計算當前像素到中心的距離
	float dist = length(center_uv);

	// 如果距離小於半徑，就讓它變成透明的！
	if (dist < circle_radius) {
		COLOR.a = 0.0;
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0); // 否則就是純黑色
	}
}
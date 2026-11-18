shader_type canvas_item;
render_mode unshaded;

// ==========================================
// 《眠境 RE:COLOR》森林動態背景 V2
//
// 主要改善：
// 1. 增加霧氣流動的辨識度
// 2. 加強森林光束的明暗變化
// 3. 保留原本水面與暗角效果
// ==========================================


// ==========================================
// Inspector 可調整參數
// ==========================================

// 背景亮度
uniform float background_brightness :
	hint_range(0.0, 1.0) = 0.68;

// 霧氣濃度
uniform float fog_strength :
	hint_range(0.0, 0.8) = 0.45;

// 霧氣水平移動速度
uniform float fog_speed :
	hint_range(0.0, 0.15) = 0.035;

// 光束明暗變化強度
uniform float light_strength :
	hint_range(0.0, 0.6) = 0.32;

// 光束呼吸速度
uniform float light_speed :
	hint_range(0.0, 2.0) = 0.82;

// 水面波動幅度
uniform float water_strength :
	hint_range(0.0, 0.01) = 0.0025;

// 水面波動速度
uniform float water_speed :
	hint_range(0.0, 3.0) = 1.0;

// 暗角強度
uniform float vignette_strength :
	hint_range(0.0, 1.0) = 0.38;


// 保留節點設定的顏色與透明度
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}


// ==========================================
// 隨機數值生成
// ==========================================

float hash21(vec2 p) {
	return fract(
		sin(dot(p, vec2(127.1, 311.7)))
		* 43758.5453
	);
}


// ==========================================
// 平滑雜訊
// 避免霧氣出現不自然的方塊
// ==========================================

float smooth_noise(vec2 p) {

	vec2 i = floor(p);
	vec2 f = fract(p);

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			hash21(i),
			hash21(i + vec2(1.0, 0.0)),
			u.x
		),
		mix(
			hash21(i + vec2(0.0, 1.0)),
			hash21(i + vec2(1.0, 1.0)),
			u.x
		),
		u.y
	);

}


// ==========================================
// 多層雜訊
// 產生較自然的霧氣形狀
// ==========================================

float fbm(vec2 p) {

	float value = 0.0;
	float amplitude = 0.5;

	for (int i = 0; i < 3; i++) {

		value += smooth_noise(p) * amplitude;

		p = p * 2.0 + vec2(13.4, 7.2);

		amplitude *= 0.5;

	}

	return value / 0.875;

}


// ==========================================
// 柔和區域遮罩
// ==========================================

float soft_band(float x, float center, float width) {

	float d = (x - center) / width;

	return exp(-d * d);

}


// ==========================================
// 主要 Shader 運算
// ==========================================

void fragment() {

	vec2 uv = UV;
	vec2 sample_uv = uv;


	// ======================================
	// 1. 水面波紋
	// 保留原本的水面動態效果
	// ======================================

	float water_mask =
		smoothstep(0.805, 0.86, uv.y)
		* smoothstep(0.25, 0.38, uv.x)
		* (1.0 - smoothstep(0.64, 0.79, uv.x));

	float water_time = TIME * water_speed;

	float wave1 =
		sin(uv.y * 150.0 + water_time * 1.4)
		* sin(uv.x * 24.0 - water_time * 0.45);

	float wave2 =
		sin(uv.y * 230.0 - water_time * 1.7)
		* 0.3;

	sample_uv.x +=
		(wave1 + wave2)
		* water_strength
		* water_mask;

	sample_uv.y +=
		sin(uv.x * 45.0 + water_time)
		* water_strength
		* 0.12
		* water_mask;

	sample_uv = clamp(
		sample_uv,
		vec2(0.0),
		vec2(1.0)
	);

	vec4 original = texture(TEXTURE, sample_uv);

	vec3 final_color = original.rgb;


	// ======================================
	// 2. 森林深藍紫色調
	// ======================================

	final_color *= background_brightness;

	final_color *= vec3(0.88, 0.94, 1.06);


	// ======================================
	// 3. 改良版動態霧氣
	//
	// 使用不同速度及高度的兩層霧氣，
	// 產生具有遠近層次的流動感。
	// ======================================

	float fog_time = TIME * fog_speed;


	// --------------------------------------
	// 遠景霧氣：較慢、較寬廣
	// --------------------------------------

	vec2 far_uv = uv;

	far_uv.x -= fog_time * 0.55;

	far_uv.y += sin(
		uv.x * 8.0 + TIME * 0.18
	) * 0.012;

	float far_noise = fbm(
		far_uv * vec2(5.0, 23.0)
	);

	// 加強霧氣的明暗落差
	float far_density = smoothstep(
		0.30,
		0.72,
		far_noise
	);

	float far_mask = soft_band(
		uv.y,
		0.60,
		0.085
	);


	// --------------------------------------
	// 近景霧氣：較快、較細長
	// --------------------------------------

	vec2 near_uv = uv;

	near_uv.x += fog_time;

	near_uv.y += sin(
		uv.x * 11.0 - TIME * 0.24
	) * 0.018;

	float near_noise = fbm(
		near_uv * vec2(4.0, 30.0)
		+ vec2(3.0, 8.0)
	);

	float near_density = smoothstep(
		0.28,
		0.72,
		near_noise
	);

	float near_mask = soft_band(
		uv.y,
		0.75,
		0.055
	);


	// --------------------------------------
	// 霧氣邊緣限制
	// 避免整個畫面都被霧氣覆蓋
	// --------------------------------------

	float fog_edge =
		smoothstep(0.08, 0.30, uv.x)
		* (1.0 - smoothstep(0.70, 0.93, uv.x));


	// 合併遠景及近景的霧

	float fog = (
		far_density * far_mask * 0.65
		+ near_density * near_mask
	) * fog_edge * fog_strength;


	// 霧氣使用淡藍紫色
	vec3 fog_color = vec3(
		0.65,
		0.69,
		0.86
	);

	final_color = mix(
		final_color,
		fog_color,
		clamp(fog, 0.0, 0.65)
	);


	// ======================================
	// 4. 改良版呼吸光束
	//
	// 直接控制原本圖片光線區域的亮度，
	// 不再只是疊加微弱的光。
	// ======================================

	// 光線主要集中於畫面上方中央

	float light_mask =
		soft_band(uv.x, 0.50, 0.28)
		* (1.0 - smoothstep(0.05, 0.65, uv.y));


	// 光束慢慢變亮、變暗
	// 數值會在 -1 至 1 之間循環

	float breathing = sin(
		TIME * light_speed
	);


	// 模擬從上方光源向外延伸的光束

	float ray_angle =
		(uv.x - 0.50) / (uv.y + 0.23);

	float ray_pattern =
		sin(ray_angle * 23.0 + TIME * 0.12)
		* 0.5 + 0.5;

	float ray_detail =
		0.55 + ray_pattern * 0.45;


	// 控制原始背景的局部明暗

	float light_variation =
		1.0
		+ breathing
		* light_strength
		* light_mask
		* ray_detail;

	final_color *= light_variation;


	// 補充少量柔和的冷色光芒

	float glow =
		(breathing * 0.5 + 0.5)
		* light_mask
		* ray_detail
		* light_strength
		* 0.30;

	final_color +=
		vec3(0.83, 0.86, 1.0) * glow;


	// ======================================
	// 5. 水面細微反光
	// ======================================

	float shimmer =
		sin(uv.y * 320.0 + water_time * 1.8)
		* 0.5 + 0.5;

	final_color +=
		vec3(0.52, 0.56, 0.76)
		* shimmer
		* water_mask
		* water_strength
		* 8.0;


	// ======================================
	// 6. 電影式四周暗角
	// ======================================

	float distance_from_center = length(
		(uv - vec2(0.5))
		* vec2(1.16, 1.0)
	);

	float vignette = smoothstep(
		0.28,
		0.76,
		distance_from_center
	) * vignette_strength;

	final_color *= 1.0 - vignette;


	// ======================================
	// 7. 輸出最終畫面
	// ======================================

	COLOR = vec4(
		final_color,
		original.a
	) * vertex_tint;

}
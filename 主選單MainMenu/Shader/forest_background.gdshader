shader_type canvas_item;
render_mode unshaded;

// ============================================================
// 《眠境 RE:COLOR》森林動態背景 V4
// Advanced Natural Wind System
//
// 【環境效果】
// 1. 多層流動霧氣
// 2. 森林呼吸光束
// 3. 湖泊動態波紋
// 4. 水面細微反光
// 5. 電影式暗角
//
// 【植物動態】
// 6. 前景花草彎曲與回彈
// 7. 多區域櫻花枝條擺動
// 8. 遠景樹冠微幅擺動
// 9. 不規律的自然陣風
// 10. 植物根部固定與邊緣保護
// ============================================================


// ============================================================
// 【環境效果設定】
// ============================================================

group_uniforms Environment;

// 背景整體亮度。
uniform float background_brightness :
	hint_range(0.0, 1.0) = 0.68;

// 霧氣濃度。
uniform float fog_strength :
	hint_range(0.0, 0.8) = 0.45;

// 霧氣移動速度。
uniform float fog_speed :
	hint_range(0.0, 0.15) = 0.035;

// 光束明暗變化強度。
uniform float light_strength :
	hint_range(0.0, 0.6) = 0.32;

// 光束呼吸速度。
uniform float light_speed :
	hint_range(0.0, 2.0) = 0.82;

// 水面波紋幅度。
uniform float water_strength :
	hint_range(0.0, 0.01) = 0.0025;

// 水面波紋速度。
uniform float water_speed :
	hint_range(0.0, 3.0) = 1.0;

// 四周暗角強度。
uniform float vignette_strength :
	hint_range(0.0, 1.0) = 0.38;


// ============================================================
// 【高品質植物微風設定】
// ============================================================

group_uniforms VegetationWind;

// 植物動態總開關。
uniform bool wind_enabled = true;

// 整體風吹速度。
uniform float wind_speed :
	hint_range(0.0, 3.0) = 1.10;

// 前景花草擺動幅度。
// 數值以原始圖片像素為單位。
uniform float grass_strength_px :
	hint_range(0.0, 45.0) = 22.0;

// 櫻花樹枝擺動幅度。
uniform float branch_strength_px :
	hint_range(0.0, 30.0) = 13.0;

// 遠景櫻花樹冠擺動幅度。
uniform float distant_tree_strength_px :
	hint_range(0.0, 15.0) = 4.0;

// 陣風強弱變化。
uniform float gust_strength :
	hint_range(0.0, 1.0) = 0.45;

// 小型植物細微顫動的幅度。
uniform float flutter_strength :
	hint_range(0.0, 1.0) = 0.22;

// 顯示植物動態區域，方便確認遮罩。
uniform bool debug_wind_mask = false;

group_uniforms;


// ============================================================
// 【保留節點透明度與顏色】
// 兼容原本主選單 IntroFade。
// ============================================================

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}


// ============================================================
// 【隨機雜訊工具】
// ============================================================

float hash21(vec2 p) {

	return fract(
		sin(dot(p, vec2(127.1, 311.7)))
		* 43758.5453
	);

}


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


// 多層平滑雜訊，用於自然霧氣。
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


// ============================================================
// 【區域遮罩工具】
// ============================================================

float soft_band(float x, float center, float width) {

	float d = (x - center) / width;

	return exp(-d * d);

}


// 柔和橢圓區域。
// 中心保留較大的作用力，邊緣逐漸減弱。
float soft_ellipse(
	vec2 uv,
	vec2 center,
	vec2 radii
) {

	float d = length(
		(uv - center) / radii
	);

	return 1.0 - smoothstep(
		0.48,
		1.0,
		d
	);

}


// ============================================================
// 【花草固定根部遮罩】
//
// tip_y：花朵或植物尖端高度。
// root_y：植物根部高度。
//
// 越接近根部，位移越接近零。
// ============================================================

float anchored_grass(
	vec2 uv,
	vec2 center,
	vec2 radii,
	float tip_y,
	float root_y
) {

	float region = soft_ellipse(
		uv,
		center,
		radii
	);

	float flexibility =
		1.0 - smoothstep(
			tip_y,
			root_y,
			uv.y
		);

	return region * flexibility;

}


// ============================================================
// 【依照原始森林背景配置植物動態區域】
//
// RGB 分別儲存：
// R：前景花草
// G：櫻花細枝
// B：遠景櫻花樹
// ============================================================

vec3 get_vegetation_masks(vec2 uv) {

	// --------------------------------------------------------
	// A. 左下方高處花朵
	// --------------------------------------------------------

	float grass_left_upper = anchored_grass(
		uv,
		vec2(0.090, 0.695),
		vec2(0.100, 0.215),
		0.670,
		0.925
	);


	// --------------------------------------------------------
	// B. 左下方低處花朵與細草
	// --------------------------------------------------------

	float grass_left_lower = anchored_grass(
		uv,
		vec2(0.115, 0.795),
		vec2(0.095, 0.155),
		0.770,
		0.940
	);


	// --------------------------------------------------------
	// C. 右側較高的白色花朵
	// --------------------------------------------------------

	float grass_right_upper = anchored_grass(
		uv,
		vec2(0.865, 0.625),
		vec2(0.085, 0.210),
		0.585,
		0.845
	);


	// --------------------------------------------------------
	// D. 右側岩石旁的小型花草
	// --------------------------------------------------------

	float grass_right_middle = anchored_grass(
		uv,
		vec2(0.830, 0.720),
		vec2(0.068, 0.120),
		0.690,
		0.825
	);


	// --------------------------------------------------------
	// E. 右下角植物群
	// --------------------------------------------------------

	float grass_right_lower = anchored_grass(
		uv,
		vec2(0.950, 0.755),
		vec2(0.085, 0.170),
		0.700,
		0.890
	);


	// 合併花草動態區域。
	// 使用 max 避免重疊區域的位移被過度加強。

	float grass_mask = max(
		max(
			grass_left_upper,
			grass_left_lower
		),
		max(
			grass_right_upper,
			max(
				grass_right_middle,
				grass_right_lower
			)
		)
	);


	// --------------------------------------------------------
	// F. 左上方延伸出的細樹枝
	// --------------------------------------------------------

	float branch_left_top = soft_ellipse(
		uv,
		vec2(0.270, 0.070),
		vec2(0.155, 0.135)
	);

	// 靠近主樹幹的部分保持固定。
	branch_left_top *= smoothstep(
		0.125,
		0.255,
		uv.x
	);


	// --------------------------------------------------------
	// G. 右上方主要櫻花枝
	// --------------------------------------------------------

	float branch_right_top = soft_ellipse(
		uv,
		vec2(0.765, 0.100),
		vec2(0.155, 0.145)
	);

	branch_right_top *= 1.0 - smoothstep(
		0.805,
		0.940,
		uv.x
	);


	// --------------------------------------------------------
	// H. 右上方較細的懸垂枝條
	// --------------------------------------------------------

	float branch_right_small = soft_ellipse(
		uv,
		vec2(0.855, 0.120),
		vec2(0.075, 0.120)
	);

	branch_right_small *= 1.0 - smoothstep(
		0.865,
		0.965,
		uv.x
	);


	// --------------------------------------------------------
	// I. 左側中段橫向延伸的樹枝
	// --------------------------------------------------------

	float branch_left_middle = soft_ellipse(
		uv,
		vec2(0.190, 0.480),
		vec2(0.125, 0.125)
	);

	branch_left_middle *= smoothstep(
		0.050,
		0.185,
		uv.x
	);


	// 合併樹枝動態區域。

	float branch_mask = max(
		max(
			branch_left_top,
			branch_right_top
		),
		max(
			branch_right_small,
			branch_left_middle
		)
	);


	// --------------------------------------------------------
	// J. 中央遠景櫻花樹冠
	// --------------------------------------------------------

	float distant_tree = soft_ellipse(
		uv,
		vec2(0.515, 0.430),
		vec2(0.100, 0.075)
	);

	// 避免遠景樹幹與地面跟著移動。
	distant_tree *= 1.0 - smoothstep(
		0.450,
		0.500,
		uv.y
	);


	// --------------------------------------------------------
	// K. 圖片邊緣固定
	// 防止移動時露出圖片邊界或產生拉伸。
	// --------------------------------------------------------

	float edge_guard =
		smoothstep(0.0, 0.018, uv.x)
		* (
			1.0 - smoothstep(
				0.982,
				1.0,
				uv.x
			)
		)
		* smoothstep(
			0.0,
			0.015,
			uv.y
		);


	return vec3(
		grass_mask,
		branch_mask,
		distant_tree
	) * edge_guard;

}


// ============================================================
// 【高品質自然風場】
//
// 主風：整體一致的風吹節奏。
// 局部風：不同位置產生細微時間差。
// 陣風：不規律改變風力。
// 細顫動：模擬花朵與細枝的小幅回彈。
// ============================================================

vec2 get_wind_offset(
	vec2 uv,
	vec3 masks,
	vec2 pixel_size
) {

	float t = TIME * wind_speed;


	// --------------------------------------------------------
	// 1. 共用風場
	// --------------------------------------------------------

	float primary_wind = sin(
		t * 1.10
	);

	float secondary_wind = sin(
		t * 1.87 + 0.8
	);

	float global_wind =
		primary_wind * 0.74
		+ secondary_wind * 0.26;


	// --------------------------------------------------------
	// 2. 不規律陣風
	// --------------------------------------------------------

	float gust_wave =
		sin(t * 0.43) * 0.55
		+ sin(t * 0.71 + 1.6) * 0.45;

	float gust =
		1.0 + gust_wave * gust_strength;


	// --------------------------------------------------------
	// 3. 植物位置差異
	// 讓不同植物稍微錯開擺動時間。
	// --------------------------------------------------------

	float phase =
		uv.x * 1.8
		+ uv.y * 1.3;

	float local_wind = sin(
		t * 1.45 + phase
	);

	float flutter = (
		sin(t * 4.2 + phase * 3.0) * 0.70
		+ sin(t * 6.1 + phase * 2.0) * 0.30
	) * flutter_strength;


	// --------------------------------------------------------
	// 4. 前景花草動態
	// 明顯的左右彎曲，附帶微弱上下回彈。
	// --------------------------------------------------------

	float grass_bend =
		global_wind * 0.78
		+ local_wind * 0.22
		+ flutter * 0.30;

	vec2 grass_motion = vec2(

		grass_bend,

		sin(
			t * 1.30 + phase
		) * 0.12

		+ abs(grass_bend) * 0.08

	);

	grass_motion *=
		grass_strength_px
		* masks.r;


	// --------------------------------------------------------
	// 5. 樹枝動態
	// 除了左右擺動，也增加上下柔和彎曲。
	// --------------------------------------------------------

	float branch_bend =
		global_wind * 0.70
		+ sin(
			t * 0.86 + phase
		) * 0.30;

	float branch_vertical =
		sin(t * 0.95 + phase + 0.7) * 0.80
		+ sin(t * 1.73 + phase) * 0.20;

	vec2 branch_motion = vec2(

		branch_bend * 0.82,

		branch_vertical * 0.65

	);

	branch_motion *=
		branch_strength_px
		* masks.g;


	// --------------------------------------------------------
	// 6. 遠景櫻花樹冠
	// 保留遠近景物的動態差異。
	// --------------------------------------------------------

	vec2 distant_motion = vec2(

		sin(t * 0.78 + 0.4),

		sin(t * 0.78 + 1.2) * 0.12

	);

	distant_motion *=
		distant_tree_strength_px
		* masks.b;


	// --------------------------------------------------------
	// 7. 合併自然風場
	// 以原始圖片像素大小換算至 UV。
	// --------------------------------------------------------

	return (
		grass_motion
		+ branch_motion
		+ distant_motion
	)
	* gust
	* pixel_size;

}


// ============================================================
// 【主要 Shader 運算】
// ============================================================

void fragment() {

	vec2 uv = UV;
	vec2 sample_uv = uv;


	// ======================================
	// 1. 植物自然微風
	// ======================================

	vec3 wind_masks = vec3(0.0);

	if (wind_enabled || debug_wind_mask) {

		wind_masks = get_vegetation_masks(uv);

	}

	if (wind_enabled) {

		vec2 wind_offset = get_wind_offset(
			uv,
			wind_masks,
			TEXTURE_PIXEL_SIZE
		);

		sample_uv -= wind_offset;

	}


	// ======================================
	// 2. 原版湖泊動態波紋
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

	// 避免取樣超出圖片。
	sample_uv = clamp(
		sample_uv,
		vec2(0.0),
		vec2(1.0)
	);

	vec4 original = texture(
		TEXTURE,
		sample_uv
	);

	vec3 final_color = original.rgb;


	// ======================================
	// 3. 原版森林深藍紫色調
	// ======================================

	final_color *= background_brightness;

	final_color *= vec3(
		0.88,
		0.94,
		1.06
	);


	// ======================================
	// 4. 原版雙層動態霧氣
	// ======================================

	float fog_time = TIME * fog_speed;


	// 遠景霧氣。

	vec2 far_uv = uv;

	far_uv.x -= fog_time * 0.55;

	far_uv.y += sin(
		uv.x * 8.0 + TIME * 0.18
	) * 0.012;

	float far_noise = fbm(
		far_uv * vec2(5.0, 23.0)
	);

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


	// 近景霧氣。

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


	// 霧氣邊緣保護。

	float fog_edge =
		smoothstep(0.08, 0.30, uv.x)
		* (1.0 - smoothstep(0.70, 0.93, uv.x));

	float fog = (
		far_density * far_mask * 0.65
		+ near_density * near_mask
	) * fog_edge * fog_strength;

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
	// 5. 原版森林呼吸光束
	// ======================================

	float light_mask =
		soft_band(uv.x, 0.50, 0.28)
		* (1.0 - smoothstep(0.05, 0.65, uv.y));

	float breathing = sin(
		TIME * light_speed
	);

	float ray_angle =
		(uv.x - 0.50) / (uv.y + 0.23);

	float ray_pattern =
		sin(ray_angle * 23.0 + TIME * 0.12)
		* 0.5 + 0.5;

	float ray_detail =
		0.55 + ray_pattern * 0.45;

	float light_variation =
		1.0
		+ breathing
		* light_strength
		* light_mask
		* ray_detail;

	final_color *= light_variation;


	// 補充柔和冷色光芒。

	float glow =
		(breathing * 0.5 + 0.5)
		* light_mask
		* ray_detail
		* light_strength
		* 0.30;

	final_color += vec3(
		0.83,
		0.86,
		1.0
	) * glow;


	// ======================================
	// 6. 原版水面細微反光
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
	// 7. 原版電影式暗角
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
	// 8. 植物遮罩除錯模式
	//
	// 綠色：花草
	// 橘色：樹枝
	// 粉色：遠方櫻花樹冠
	// ======================================

	if (debug_wind_mask) {

		vec3 debug_color =
			vec3(0.2, 1.0, 0.5) * wind_masks.r
			+ vec3(1.0, 0.65, 0.15) * wind_masks.g
			+ vec3(1.0, 0.2, 0.7) * wind_masks.b;

		final_color =
			original.rgb * 0.35
			+ debug_color * 0.65;

	}


	// ======================================
	// 9. 最終畫面輸出
	// ======================================

	COLOR = vec4(
		final_color,
		original.a
	) * vertex_tint;

}
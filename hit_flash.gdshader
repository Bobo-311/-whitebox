
shader_type canvas_item;

// ==========================================
// 1. 閃白控制器
// ==========================================
// 0.0 = 正常顏色
// 1.0 = 完全閃白
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// ==========================================
// 2. 狀態顏色控制器
// ==========================================
// 預設純白，不影響原始貼圖顏色
// 可用於中毒、燃燒等特殊狀態
uniform vec4 state_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// ==========================================
// 3. 灰階控制器
// ==========================================
// 0.0 = 原始顏色
// 1.0 = 完全灰階
uniform float grayscale_modifier : hint_range(0.0, 1.0) = 0.0;

// ==========================================
// 4. 消散控制器
// ==========================================
// 0.0 = 完整顯示
// 1.0 = 完全消失
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;

// 控制消散邊緣的柔和程度
uniform float dissolve_edge_width : hint_range(0.001, 0.2) = 0.06;

// 消散時的銀灰色亮邊
uniform vec4 dissolve_edge_color : source_color = vec4(0.78, 0.84, 0.90, 1.0);

// ==========================================
// 5. 雜訊函數
// ==========================================
// 利用雜訊產生不規則的消散形狀
float hash_noise(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 平滑雜訊，避免消散邊緣過於生硬
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash_noise(i);
    float b = hash_noise(i + vec2(1.0, 0.0));
    float c = hash_noise(i + vec2(0.0, 1.0));
    float d = hash_noise(i + vec2(1.0, 1.0));

    return mix(
        mix(a, b, f.x),
        mix(c, d, f.x),
        f.y
    );
}

// ==========================================
// 6. 主要渲染程序
// ==========================================
void fragment() {

    // 取得敵人原始動畫貼圖
    vec4 tex_color = texture(TEXTURE, UV);

    // --------------------------------------
    // A. 保留原始貼圖顏色
    // --------------------------------------
    // 不乘上 COLOR.rgb，避免節點調色影響原始美術顏色
    vec4 base_color = tex_color * state_color;

    // 單獨保留 Godot 傳入的透明度
    base_color.a *= COLOR.a;

    // --------------------------------------
    // B. 灰階處理
    // --------------------------------------
    // 計算符合人眼感知的灰階亮度
    float gray_value = dot(
        base_color.rgb,
        vec3(0.299, 0.587, 0.114)
    );

    // 依照參數混合原始顏色與灰階
    base_color.rgb = mix(
        base_color.rgb,
        vec3(gray_value),
        grayscale_modifier
    );

    // --------------------------------------
    // C. 閃白處理
    // --------------------------------------
    // 保留原本的受擊閃白功能
    vec4 final_color = mix(
        base_color,
        vec4(flash_color.rgb, base_color.a),
        flash_modifier
    );

    // --------------------------------------
    // D. 計算程序化消散
    // --------------------------------------
    // 產生不規則的雜訊區域
    float noise_value = value_noise(
        UV * vec2(24.0, 32.0)
    );

    // 加入垂直方向偏移，使消散由下往上進行
    noise_value += (1.0 - UV.y) * 0.35;

    // 控制消散門檻
    float threshold = mix(
        -0.12,
        1.47,
        dissolve_progress
    );

    // 計算目前仍然存在的區域
    float dissolve_mask = smoothstep(
        threshold - dissolve_edge_width,
        threshold + dissolve_edge_width,
        noise_value
    );

    // --------------------------------------
    // E. 消散邊緣亮光
    // --------------------------------------
    // 找出雜訊邊界，產生銀灰色亮邊
    float edge = 1.0 - smoothstep(
        0.0,
        dissolve_edge_width,
        abs(noise_value - threshold)
    );

    // 限制亮邊只出現在尚未消失的區域
    edge *= dissolve_mask;

    // 將銀灰色亮光混入原始顏色
    final_color.rgb = mix(
        final_color.rgb,
        dissolve_edge_color.rgb,
        edge * 0.9
    );

    // --------------------------------------
    // F. 最終透明度
    // --------------------------------------
    // 讓消散區域逐漸變透明
    final_color.a *= dissolve_mask;

    // 輸出最終畫面
    COLOR = final_color;
}

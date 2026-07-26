shader_type canvas_item;

// 腳本控制血量的變數 (1.0 = 滿血, 0.0 = 沒血)
uniform float saturation : hint_range(0.0, 1.0) = 1.0;

// 🎨 給你手動調的實體感控制
uniform float color_boost : hint_range(1.0, 3.0) = 1.2; // 鮮豔度 (不用拉太高，1.2 左右就有感)
uniform float color_depth : hint_range(1.0, 3.0) = 1.5; // 🌟 濃厚度 (數字越大，顏色越沉穩、越沒有螢光感)

void fragment() {
    // 1. 取出原本的像素圖
    vec4 color = texture(TEXTURE, UV) * COLOR;
    
    // 2. 催出鮮豔度
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(vec3(gray), color.rgb, color_boost);
    
    // 防呆：切掉超過極限的螢光爆光數值
    color.rgb = clamp(color.rgb, 0.0, 1.0);
    
    // 3. 🌟 核心：把亮度壓沉，消除螢光感！
    // 這裡用的是 Gamma 次方算式，它不會改變純黑跟純白，但會把中間的顏色「往下壓深」，製造厚重感。
    color.rgb = pow(color.rgb, vec3(color_depth));
    
    // 4. 最後套用血量變灰邏輯
    float final_gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(vec3(final_gray), color.rgb, saturation);
    
    COLOR = color;
}
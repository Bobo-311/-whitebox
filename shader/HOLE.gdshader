shader_type canvas_item;

uniform float oval_width : hint_range(0.1, 2.0) = 0.8;
uniform float oval_height : hint_range(0.1, 2.0) = 0.5;

void fragment() {
    vec2 center_uv = UV * 2.0 - 1.0;
    float dist = (center_uv.x * center_uv.x) / (oval_width * oval_width) + (center_uv.y * center_uv.y) / (oval_height * oval_height);
    
    if (dist > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0); // 外圍全黑
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0); // 中間透明，露出地板
    }
}
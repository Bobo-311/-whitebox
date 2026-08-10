extends Node2D

# 🌟 圓環參數 (可在 Inspector 直接拉大)
@export var max_radius: float = 80.0         # 🌟 半徑從 40 調大到 80 (衝擊波範圍加倍)
@export var duration: float = 0.18            # 擴散時間微調至 0.18 秒 (範圍大，稍微延長讓視覺更清晰)
@export var ring_color: Color = Color("38bdf8") # 天藍色魔法光芒

var current_radius: float = 4.0               # 當前半徑
var line_width: float = 8.0                  # 🌟 起始線寬從 4 調大到 8 (讓大圓環保持扎實不細薄)

func _ready() -> void:
	var tween = create_tween().set_parallel(true)
	
	# 1. 圓環急速向外推開
	tween.tween_property(self, "current_radius", max_radius, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. 圓環邊框隨擴散平滑收細
	tween.tween_property(self, "line_width", 1.0, duration)
	# 3. 顏色漸隱至透明
	tween.tween_property(self, "ring_color:a", 0.0, duration)
	
	# 4. 動畫結束後自動銷毀
	tween.chain().tween_callback(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if ring_color.a > 0:
		# 畫出極度順暢的空心魔力環
		draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, ring_color, line_width, true)

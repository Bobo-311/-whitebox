extends Node2D

# ==========================================
# 💫 翻滾冷卻完畢：提示特效 (Procedural Effect)
# ==========================================
# 【類似遊戲思考】：擴大特效範圍，能讓玩家在混戰中用「餘光」更清楚地捕捉到冷卻完畢的瞬間。
# 紫色通常在遊戲中代表高階能量或敏捷，能與一般怪物攻擊的紅/黃光做出強烈區別。

@onready var sparks: GPUParticles2D = $Sparks

# 🌟【正規作法：參數開放 (Expose Parameters)】
# 將視覺參數拉出，企劃可以直接在 Inspector 調整數值與顏色，免動程式碼！
@export_category("🎨 光環視覺設定")
@export var ring_max_radius: float = 75.0            # [數值放大]：光環最大擴散半徑 (從 40 放大到 75)
@export var ring_base_color: Color = Color(0.7, 0.2, 1.0) # [顏色更改]：預設改為高能紫色 (RGB)
@export var ring_thickness: float = 3.5              # [視覺調整]：光環線條粗細 (配合半徑放大，稍微加粗)

var ring_radius: float = 0.0:
	set(value):
		ring_radius = value
		queue_redraw()

var ring_alpha: float = 1.0:
	set(value):
		ring_alpha = value
		queue_redraw()

func _ready() -> void:
	# 1. 啟動粒子爆發
	sparks.emitting = true
	
	# 2. 啟動光環擴散動畫 (雙軌 Tween)
	var tween = create_tween().set_parallel(true)
	
	# 軌道 A：光環從半徑 0 瞬間擴張到設定的 最大半徑 (ring_max_radius)
	tween.tween_property(self, "ring_radius", ring_max_radius, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 軌道 B：光環透明度從 1.0 漸漸淡出到 0.0
	tween.tween_property(self, "ring_alpha", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	
	# 3. 自動垃圾回收
	var life_timer = get_tree().create_timer(0.6)
	life_timer.timeout.connect(func(): queue_free())

# ==========================================
# 🎨 幾何繪圖引擎 (底層調用)
# ==========================================
func _draw() -> void:
	if ring_alpha <= 0.0: return
	
	# 融合我們設定好的紫色與目前的透明度 (Alpha)
	var final_color = ring_base_color
	final_color.a = ring_alpha
	
	# 畫出完美的圓圈！
	draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, final_color, ring_thickness, true)

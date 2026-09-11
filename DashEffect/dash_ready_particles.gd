extends Node2D

# ==========================================
# 💫 翻滾冷卻完畢：提示特效 (Procedural Effect)
# ==========================================
# 【類似遊戲思考】：不依賴圖片素材，純用程式碼動態畫出光環 (Ring)。
# 這樣無論畫面怎麼縮放，光環永遠是絕對清晰的 (Crisp)，不會有像素模糊。

@onready var sparks: GPUParticles2D = $Sparks

# 🌟【正規作法：Setter 動態更新】
# 當 Tween 改變 ring_radius 時，自動呼叫 queue_redraw() 重新繪製畫面。
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
	
	# 軌道 A：光環從半徑 0 瞬間擴張到 40 (使用 OUT_BACK 創造回彈的 Q 彈感)
	tween.tween_property(self, "ring_radius", 40.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 軌道 B：光環透明度從 1.0 漸漸淡出到 0.0
	tween.tween_property(self, "ring_alpha", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	
	# 3. 【正規作法：自動垃圾回收】
	# 粒子設定活 0.6 秒，動畫跑 0.4 秒。我們取最長的 0.6 秒後，把自己從地圖上刪除！
	var life_timer = get_tree().create_timer(0.6)
	life_timer.timeout.connect(func(): queue_free())

# ==========================================
# 🎨 幾何繪圖引擎 (底層調用)
# ==========================================
func _draw() -> void:
	# 如果完全透明了就不用畫，節省效能
	if ring_alpha <= 0.0: return
	
	# 設定光環顏色 (高亮青藍色 + 當前的透明度)
	var ring_color = Color(0.2, 1.0, 0.8, ring_alpha)
	var thickness = 2.5 # 光環線條粗細
	
	# 利用 Godot 內建函數畫出完美的圓圈！(圓心, 半徑, 顏色, 填滿=false, 粗細, 抗鋸齒=true)
	draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, ring_color, thickness, true)

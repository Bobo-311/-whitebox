extends CanvasLayer

@onready var black_screen = $BlackScreen

func _ready():
	# 設定黑布不阻擋滑鼠點擊 (很重要，不然你遊戲不能點擊)
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 遊戲剛打開時，確保洞是最大(1.5)的狀態，畫面是清楚的
	black_screen.material.set_shader_parameter("circle_radius", 1.5)

# --- 這是給其他腳本呼叫的轉場函數 ---
func transition_to(target_scene_path: String):
	# 1. 建立動畫：讓圓形半徑從 1.5 縮小到 0.0 (花費 0.5 秒)
	var tween = create_tween()
	tween.tween_property(black_screen.material, "shader_parameter/circle_radius", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	
	# 2. 暫停並等待這個 0.5 秒的動畫播完
	await tween.finished
	
	# 3. 此時畫面已經「全黑」了，我們趁機在背景偷偷切換場景！
	get_tree().change_scene_to_file(target_scene_path)
	
	# 4. 新場景載入好之後，建立新動畫：讓圓形半徑從 0.0 擴大回 1.5 (畫面亮起)
	var tween2 = create_tween()
	tween2.tween_property(black_screen.material, "shader_parameter/circle_radius", 1.5, 0.5).set_trans(Tween.TRANS_SINE)

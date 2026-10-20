# --- scene_transition.gd (掛在 Autoload 的 SceneTransition 上) ---
extends CanvasLayer

@onready var black_screen: ColorRect = $BlackScreen

var is_transitioning: bool = false # 防呆鎖：防止轉場途中重複觸發

func _ready() -> void:
	# 遊戲開局時，確保黑幕是完全透明的 (Alpha = 0)
	black_screen.modulate.a = 0.0

# 🌟 核心轉場函數：接收「目標地圖路徑」與「目標出生點名稱」
func change_map(target_scene_path: String, target_spawn_name: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	# 1. 🎬 拉下黑幕 (0.3 秒內淡入純黑)
	var tween_in = create_tween()
	tween_in.tween_property(black_screen, "modulate:a", 1.0, 0.3)
	await tween_in.finished
	
	# 2. 🗺️ 在黑幕背後切換地圖場景
	get_tree().change_scene_to_file(target_scene_path)
	
	# ⏳ 關鍵等待：等兩幀，確保新地圖的節點與 Player 已經全部載入完畢 (_ready 執行完)
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 3. 📍 將玩家搬移到新地圖指定的 Marker2D 定位針位置
	_move_player_to_spawn(target_spawn_name)
	
	# 4. 🎬 拉開黑幕 (0.3 秒內淡出回透明)
	var tween_out = create_tween()
	tween_out.tween_property(black_screen, "modulate:a", 0.0, 0.3)
	await tween_out.finished
	
	is_transitioning = false

# 內部輔助函數：去新地圖找對應名字的 Marker2D 並把玩家放過去
func _move_player_to_spawn(spawn_name: String) -> void:
	if spawn_name.is_empty():
		return
		
	var current_map = get_tree().current_scene
	if not current_map:
		return
		
	# 在新地圖中搜尋名稱符合 target_spawn_name 的 Marker2D 節點
	var spawn_point = current_map.find_child(spawn_name, true, false) as Node2D
	
	# 透過你的 DataManager 或是群組找到玩家，把座標改過去
	var player = DataManager.player_node if (DataManager and DataManager.player_node) else get_tree().get_first_node_in_group("player")
	
	if spawn_point and player:
		player.global_position = spawn_point.global_position
		
		# 如果鏡頭有平滑跟隨，轉場瞬間強制讓鏡頭立刻對齊玩家，避免鏡頭從舊位置滑過來穿幫
		var camera = get_tree().get_first_node_in_group("camera") as Camera2D
		if camera:
			camera.reset_smoothing()

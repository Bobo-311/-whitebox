# --- scene_transition.gd (掛在 Autoload 的 SceneTransition 上) ---
extends CanvasLayer

@onready var black_screen: ColorRect = $BlackScreen

var is_transitioning: bool = false # 防呆鎖：防止轉場途中重複觸發

func _ready() -> void:
	# 確保轉場總管永遠運作
	process_mode = Node.PROCESS_MODE_ALWAYS
	black_screen.modulate.a = 0.0

func change_map(target_scene_path: String, target_spawn_name: String, target_facing_dir: Vector2 = Vector2.ZERO) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	# 1. 🚀【正規作法：啟動背景非同步讀圖】
	# 在拉下黑幕的同時，就叫電腦在背景偷偷讀取下一張地圖，完全不卡住主畫面與金幣動畫！
	ResourceLoader.load_threaded_request(target_scene_path)
	
	# 2. 🎬 拉下黑幕 (0.35 秒內淡入純黑，期間金幣正常轉動)
	var tween_in = create_tween()
	tween_in.tween_property(black_screen, "modulate:a", 1.0, 0.35)
	await tween_in.finished
	
	# 3. ⏳ 等待背景地圖讀取完成 (每等一幀就刷新一次畫面，讓右上角金幣在黑幕上持續絲滑旋轉！)
	while ResourceLoader.load_threaded_get_status(target_scene_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		
	# 額外停留 0.15 秒黑幕緩衝，讓你肉眼能清楚看到金幣在黑幕期間持續旋轉
	await get_tree().create_timer(0.15).timeout
	
	# 4. 🪙【金幣無縫接力 1】：在舊地圖卸載前，拍下舊 CoinSprite 目前轉到第幾格！
	var saved_frame: int = 0
	var saved_progress: float = 0.0
	var old_coin = get_tree().root.find_child("CoinSprite", true, false) as AnimatedSprite2D
	if old_coin:
		saved_frame = old_coin.frame
		saved_progress = old_coin.frame_progress
	
	# 5. 🗺️ 取出背景已經讀好的地圖包裹，瞬間完成切換（0 卡頓！）
	var new_scene_packed = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
	if new_scene_packed:
		get_tree().change_scene_to_packed(new_scene_packed)
	else:
		get_tree().change_scene_to_file(target_scene_path)
	
	# ⏳ 等待一幀讓新地圖節點掛載上樹
	await get_tree().process_frame
	
	# 6. 🪙【金幣無縫接力 2】：立刻找到新地圖的 CoinSprite，讓它從剛剛那一格無縫繼續轉！
	var new_coin = get_tree().root.find_child("CoinSprite", true, false) as AnimatedSprite2D
	if new_coin:
		new_coin.play("spin")
		new_coin.set_frame_and_progress(saved_frame, saved_progress)
	
	# 再次等待一幀確保 Player 初始化完畢，將玩家搬到定位針
	await get_tree().process_frame
	_move_player_to_spawn(target_spawn_name, target_facing_dir)
	
	# 7. 🎬 拉開黑幕 (0.35 秒內淡出回透明)
	var tween_out = create_tween()
	tween_out.tween_property(black_screen, "modulate:a", 0.0, 0.35)
	await tween_out.finished
	
	is_transitioning = false

# 內部輔助函數：去新地圖找對應名字的 Marker2D 並設定座標
func _move_player_to_spawn(spawn_name: String, facing_dir: Vector2) -> void:
	var current_map = get_tree().current_scene
	if not current_map:
		return
		
	var player = DataManager.player_node if (DataManager and DataManager.player_node) else get_tree().get_first_node_in_group("player")
	if not player:
		return
		
	if not spawn_name.is_empty():
		var spawn_point = current_map.find_child(spawn_name, true, false) as Node2D
		if spawn_point:
			player.global_position = spawn_point.global_position
	
	# 2️⃣ 🌟【本次新增：把過圖前的面向交棒給新玩家！】
	# 呼叫我們在 player.gd 最底部新增的 set_facing_direction 函數
	if facing_dir != Vector2.ZERO and player.has_method("set_facing_direction"):
		player.set_facing_direction(facing_dir)
	
	
	var camera = get_tree().get_first_node_in_group("camera") as Camera2D
	if camera:
		camera.reset_smoothing()

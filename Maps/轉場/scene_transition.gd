extends CanvasLayer
# ============================================================
# 《眠境 RE:RECOLOR》
# SceneTransition V3｜全域場景轉場管理器
# Godot 4.5.1
# Autoload：SceneTransition
# STEP 10.7.7-C
# ============================================================
# 主要職責：
# 1. 管理地圖切換、讀檔及死亡重生轉場。
# 2. 背景非同步載入場景。
# 3. 管理全螢幕黑幕淡入淡出。
# 4. 防止重複轉場。
# 5. 玩家、白貓、相機及金幣動畫同步。
# 6. V3：支援不需要玩家定位的主選單轉場。
#
# 保留原本 change_map() 呼叫方式。
# 不直接操作 JSON 或永久玩家資料。
# ============================================================

# 1. 對外訊號
signal transition_started(scene_path: String)
signal transition_finished(scene_path: String)
signal transition_failed(scene_path: String, reason: String)
signal transition_settled(success: bool, scene_path: String)

# 2. 白貓入口及黑幕設定
@export_group("白貓入口定位")
@export_range(0.0, 512.0, 1.0, "or_greater")
var cat_spawn_distance: float = 64.0

@export_group("黑幕轉場設定")
@export_range(0.01, 2.0, 0.01)
var fade_in_duration: float = 0.18
@export_range(0.01, 2.0, 0.01)
var fade_out_duration: float = 0.22

# 3. 除錯設定
@export_group("除錯設定")
@export var debug_log: bool = true

# 4. 節點及執行狀態
@onready var black_screen: ColorRect = $BlackScreen
var is_transitioning: bool = false
var _transition_started_msec: int = 0
var _black_started_msec: int = 0
var _black_hold_msec: int = 0
var _player_lock: Dictionary = {}

# ============================================================
# 5. 初始化
# 暫停及 Hitstop 期間仍能正常執行黑幕轉場。
# ============================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	black_screen.modulate.a = 0.0
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	if debug_log:
		print("【SceneTransition】V3 全域場景轉場管理器初始化完成")

# 6. 轉場輸入保護
func _input(_event: InputEvent) -> void:
	if is_transitioning:
		get_viewport().set_input_as_handled()

# ============================================================
# 7. 正式場景切換入口
#
# require_player = true：
# 原本的遊戲地圖轉場。
#
# require_player = false：
# 主選單轉場，不要求玩家或出生點。
#
# on_scene_ready：
# 主選單建立完成、黑幕尚未淡出時執行的清理接口。
# ============================================================
func change_map(
	target_scene_path: String,
	target_spawn_name: String,
	target_facing_dir: Vector2 = Vector2.ZERO,
	require_player: bool = true,
	on_scene_ready: Callable = Callable()
) -> void:
	# A. 防止重複轉場。
	if is_transitioning:
		return
	is_transitioning = true
	_transition_started_msec = Time.get_ticks_msec()
	_black_started_msec = 0
	_black_hold_msec = 0

	# B. 驗證目標資源。
	if target_scene_path.is_empty() or not ResourceLoader.exists(
		target_scene_path, "PackedScene"
	):
		_finish_transition(false, target_scene_path, "目標場景資源不存在")
		return
	if not require_player and not on_scene_ready.is_valid():
		_finish_transition(false, target_scene_path, "缺少主選單工作階段清理接口")
		return

	# C. 啟動背景載入。
	var request_error: Error = ResourceLoader.load_threaded_request(
		target_scene_path, "PackedScene"
	)
	if request_error != OK and request_error != ERR_BUSY:
		_finish_transition(
			false,
			target_scene_path,
			"背景載入要求失敗：" + error_string(request_error)
		)
		return

	# D. 啟用輸入保護。
	set_process_input(true)
	black_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var cat_was_present: bool = (
		_find_map_cat(get_tree().current_scene) != null
	)
	_lock_player(_find_current_player())
	transition_started.emit(target_scene_path)
	if debug_log:
		print("【SceneTransition】開始轉場：", target_scene_path)

	# E. 黑幕淡入。
	await _fade_black_screen(1.0, fade_in_duration)
	_black_started_msec = Time.get_ticks_msec()

	# F. 等待背景資源載入完成。
	var load_status: int = ResourceLoader.load_threaded_get_status(
		target_scene_path
	)
	while load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		load_status = ResourceLoader.load_threaded_get_status(target_scene_path)

	# G. 驗證背景載入結果。
	if load_status != ResourceLoader.THREAD_LOAD_LOADED:
		await _reveal_and_finish(
			false,
			target_scene_path,
			"背景資源載入失敗，狀態：" + str(load_status)
		)
		return
	var new_scene_packed: PackedScene = (
		ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
	)
	if new_scene_packed == null:
		await _reveal_and_finish(
			false,
			target_scene_path,
			"載入的資源不是有效 PackedScene"
		)
		return
	if not require_player and not on_scene_ready.is_valid():
		await _reveal_and_finish(
			false, target_scene_path, "主選單工作階段清理接口已失效"
		)
		return

	# H. 記錄金幣動畫進度。
	var coin_state: Dictionary = {}
	if require_player:
		coin_state = _capture_coin_state()

	# I. 正式切換場景。
	var tree: SceneTree = get_tree()
	var change_error: Error = tree.change_scene_to_packed(new_scene_packed)
	if change_error != OK:
		await _reveal_and_finish(
			false,
			target_scene_path,
			"場景切換失敗：" + error_string(change_error)
		)
		return

	# J. 等待真正的場景建立完成。
	await tree.scene_changed
	_player_lock.clear()
	var current_map: Node = tree.current_scene
	if current_map == null:
		await _reveal_and_finish(false, target_scene_path, "無法取得新場景根節點")
		return

	# K. V3：主選單專用流程。
	# 舊場景已卸載，不尋找玩家及出生點。
	if not require_player:
		on_scene_ready.call()
		if debug_log:
			print("【SceneTransition】主選單場景載入完成")
			print("【SceneTransition】略過玩家出生點定位")
		await _reveal_and_finish(true, target_scene_path)
		return

	# L. 原本遊戲地圖流程。
	var player: Node2D = _find_current_player()
	_lock_player(player)
	_restore_coin_state(coin_state)

	# M. 玩家及白貓出生定位。
	var spawn_success: bool = _move_player_to_spawn(
		target_spawn_name,
		target_facing_dir,
		cat_was_present
	)
	if not spawn_success:
		await _reveal_and_finish(
			false,
			target_scene_path,
			"玩家或指定出生點不存在：" + target_spawn_name
		)
		return

	# N. 完成正式轉場。
	await _reveal_and_finish(true, target_scene_path)

# ============================================================
# 8. 黑幕動畫
# 不受 SceneTree 暫停及 Engine.time_scale 影響。
# ============================================================
func _fade_black_screen(target_alpha: float, duration: float) -> void:
	black_screen.show()
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ignore_time_scale(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		black_screen, "modulate:a", target_alpha, duration
	)
	await tween.finished

# ============================================================
# 9. 尋找目前場景的玩家
# 禁止使用已卸載場景中的玩家引用。
# ============================================================
func _find_current_player() -> Node2D:
	var current_map: Node = get_tree().current_scene
	if current_map == null:
		return null
	var registered_player: Node2D = DataManager.player_node
	if is_instance_valid(registered_player):
		if registered_player == current_map or current_map.is_ancestor_of(registered_player):
			return registered_player
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node2D:
			if node == current_map or current_map.is_ancestor_of(node):
				return node as Node2D
	return current_map.find_child("player", true, false) as Node2D

# ============================================================
# 10. 暫時鎖定玩家
# 沿用原本的狀態機，不改動劇情鎖。
# ============================================================
func _lock_player(player: Node2D) -> void:
	if not is_instance_valid(player):
		return
	var machine: Node = null
	if "state_machine" in player:
		machine = player.get("state_machine") as Node
	_player_lock = {
		"player": player,
		"state_machine": machine
	}
	if is_instance_valid(machine):
		_player_lock["process_mode"] = machine.process_mode
		machine.process_mode = Node.PROCESS_MODE_DISABLED
	if player is CharacterBody2D:
		var body: CharacterBody2D = player as CharacterBody2D
		body.velocity = Vector2.ZERO

# 11. 恢復原本玩家狀態機
func _unlock_player() -> void:
	if _player_lock.is_empty():
		return
	var player: Node2D = _player_lock.get("player") as Node2D
	var machine: Node = _player_lock.get("state_machine") as Node
	if is_instance_valid(player) and is_instance_valid(machine):
		var in_dialogue: bool = false
		if "is_in_dialogue" in player:
			in_dialogue = bool(player.get("is_in_dialogue"))
		if not in_dialogue:
			machine.process_mode = int(
				_player_lock.get("process_mode", Node.PROCESS_MODE_INHERIT)
			)
	_player_lock.clear()

# ============================================================
# 12. 玩家定位、面向及相機同步
# ============================================================
func _move_player_to_spawn(
	spawn_name: String,
	facing_dir: Vector2,
	cat_was_present: bool = false
) -> bool:
	var current_map: Node = get_tree().current_scene
	if current_map == null:
		return false
	var player: Node2D = _find_current_player()
	if not is_instance_valid(player):
		return false
	DataManager.player_node = player

	# 指定正式出生點。
	if not spawn_name.is_empty():
		var target_spawn: Node2D = (
			current_map.find_child(spawn_name, true, false) as Node2D
		)
		if target_spawn == null:
			push_warning("【SceneTransition】找不到出生點：" + spawn_name)
			return false
		player.global_position = target_spawn.global_position
		player.reset_physics_interpolation()

		# 保留原本白貓跟隨定位。
		if cat_was_present:
			var cat := _find_map_cat(current_map)
			if cat:
				_place_cat_at_entrance(cat, player, target_spawn, facing_dir)

	# 清除玩家移動速度。
	if player is CharacterBody2D:
		var body: CharacterBody2D = player as CharacterBody2D
		body.velocity = Vector2.ZERO
	if facing_dir != Vector2.ZERO and player.has_method("set_facing_direction"):
		player.call("set_facing_direction", facing_dir)

	# 重設相機。
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		camera = get_tree().get_first_node_in_group("camera") as Camera2D
	if is_instance_valid(camera):
		camera.reset_smoothing()
		camera.force_update_scroll()
	if debug_log:
		print(
			"【SceneTransition】玩家定位完成：",
			spawn_name, " / ", player.global_position
		)
	return true

# ============================================================
# 13. 記錄金幣動畫進度
# ============================================================
func _capture_coin_state() -> Dictionary:
	var coin: AnimatedSprite2D = (
		get_tree().root.find_child("CoinSprite", true, false) as AnimatedSprite2D
	)
	if not is_instance_valid(coin):
		return {}
	return {
		"animation": coin.animation,
		"frame": coin.frame,
		"progress": coin.frame_progress
	}

# 14. 還原金幣動畫
func _restore_coin_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var coin: AnimatedSprite2D = (
		get_tree().root.find_child("CoinSprite", true, false) as AnimatedSprite2D
	)
	if not is_instance_valid(coin):
		return
	if coin.sprite_frames == null:
		return
	var animation_name: StringName = StringName(state.get("animation", "spin"))
	if not coin.sprite_frames.has_animation(animation_name):
		return
	var frame_count: int = coin.sprite_frames.get_frame_count(animation_name)
	if frame_count <= 0:
		return
	var saved_frame: int = clampi(
		int(state.get("frame", 0)), 0, frame_count - 1
	)
	var saved_progress: float = clampf(
		float(state.get("progress", 0.0)), 0.0, 1.0
	)
	coin.play(animation_name)
	coin.set_frame_and_progress(saved_frame, saved_progress)

# ============================================================
# 15. 黑幕淡出
# ============================================================
func _reveal_and_finish(
	success: bool,
	scene_path: String,
	reason: String = ""
) -> void:
	if _black_started_msec > 0:
		_black_hold_msec = Time.get_ticks_msec() - _black_started_msec
	await _fade_black_screen(0.0, fade_out_duration)
	_finish_transition(success, scene_path, reason)

# 16. 統一完成轉場及解除操作鎖
func _finish_transition(
	success: bool,
	scene_path: String,
	reason: String = ""
) -> void:
	black_screen.modulate.a = 0.0
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	_unlock_player()
	is_transitioning = false
	var elapsed_msec: int = Time.get_ticks_msec() - _transition_started_msec
	if success:
		if debug_log:
			print("【SceneTransition】轉場成功：", scene_path)
			print("【SceneTransition】總耗時：%.3f 秒" % (
				float(elapsed_msec) / 1000.0
			))
			print("【SceneTransition】全黑停留：%.3f 秒" % (
				float(_black_hold_msec) / 1000.0
			))
		transition_finished.emit(scene_path)
	else:
		push_warning("【SceneTransition】轉場異常：" + scene_path + " / " + reason)
		transition_failed.emit(scene_path, reason)
	transition_settled.emit(success, scene_path)

# ============================================================
# 17. 尋找目前地圖的白貓
# 保留原本跨地圖跟隨判斷。
# ============================================================
func _find_map_cat(map_root: Node) -> WhiteCat:
	if not map_root:
		return null
	for node in get_tree().get_nodes_in_group("white_cat"):
		var cat := node as WhiteCat
		if not cat or not map_root.is_ancestor_of(cat) or cat.is_queued_for_deletion():
			continue
		if cat.is_visible_in_tree() and cat.process_mode != Node.PROCESS_MODE_DISABLED:
			return cat
	return null

# 18. 白貓入口定位
func _place_cat_at_entrance(
	cat: WhiteCat,
	player: Node2D,
	entrance: Node2D,
	facing_dir: Vector2
) -> void:
	cat.player_node = player
	if player is PhysicsBody2D:
		cat.add_collision_exception_with(player)
		player.add_collision_exception_with(cat)

	# 狹窄入口可設定獨立 CatSpawn。
	var cat_marker := entrance.get_node_or_null("CatSpawn") as Marker2D
	if cat_marker:
		cat.global_position = cat_marker.global_position
	else:
		cat.global_position = _cat_position_beside_player(
			cat, player.global_position, facing_dir
		)
	cat.velocity = Vector2.ZERO
	cat.is_recalling = false
	cat.nav_agent.target_position = cat.global_position
	cat.reset_physics_interpolation()
	if not cat.is_stunned:
		cat.play_animation("idle", facing_dir)

# 19. 尋找白貓安全入口位置
func _cat_position_beside_player(
	cat: WhiteCat,
	arrival: Vector2,
	facing_dir: Vector2
) -> Vector2:
	var side := Vector2.DOWN if absf(facing_dir.x) > absf(facing_dir.y) else Vector2.RIGHT
	var start := cat.global_transform
	start.origin = arrival
	var directions: Array[Vector2] = [
		side, -side, facing_dir.normalized()
	]
	for direction in directions:
		var step := direction * cat_spawn_distance
		if not cat.test_move(start, step):
			return arrival + step
	# 周圍被擋時使用玩家落點。
	return arrival

# ============================================================
# 20. V3：返回主選單專用入口
# 沿用原本黑幕及非同步資源載入系統。
# ============================================================
func change_to_main_menu(
	target_scene_path: String,
	on_scene_ready: Callable
) -> void:
	change_map(
		target_scene_path,
		"",
		Vector2.ZERO,
		false,
		on_scene_ready
	)

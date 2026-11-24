extends CanvasLayer

# ============================================================
# 《眠境 RE:RECOLOR》
# SceneTransition V2｜全域場景轉場管理器
#
# 適用版本：Godot 4.5.1
# Autoload：SceneTransition
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 管理跨地圖與讀檔進場的共用轉場
# 2. 背景非同步載入場景資源
# 3. 管理黑幕淡入及淡出
# 4. 防止重複轉場
# 5. 確認新場景已完成基本初始化
# 6. 玩家出生點定位與面向設定
# 7. 相機位置重設
# 8. 金幣動畫無縫接力
# 9. 回報轉場結果及耗時
# 10. 處理可偵測的載入失敗
#
# ============================================================
# 不負責
# ============================================================
#
# - 存檔 JSON 讀寫
# - 畫架解鎖與快速傳送規則
# - 玩家死亡及重生規則
# - 劇情永久完成紀錄
# - 地圖內部劇情演出
#
# 保留原本 change_map() 呼叫介面，
# 不需要修改現有 PortalArea 或 WorldEntry。
# ============================================================


# ============================================================
# 1. 對外訊號
# ============================================================

## 正式開始轉場
signal transition_started(scene_path: String)

## 場景切換與出生定位成功，黑幕已結束
signal transition_finished(scene_path: String)

## 場景載入或初始化發生異常
signal transition_failed(
	scene_path: String,
	reason: String
)

## 轉場流程已結束，無論成功或失敗皆會發送
##
## BaseMap 透過此訊號等待黑幕結束。
signal transition_settled(
	success: bool,
	scene_path: String
)


# ============================================================
# 2. 黑幕動畫設定
# ============================================================

@export_group("白貓入口定位")
## 入口沒有另外放 CatSpawn 時，白貓與阿尼之間的距離（世界座標單位）。
@export_range(0.0, 512.0, 1.0, "or_greater") var cat_spawn_distance: float = 64.0

@export_group("黑幕轉場設定")

## 黑幕淡入秒數
@export_range(0.01, 2.0, 0.01)
var fade_in_duration: float = 0.18

## 黑幕淡出秒數
@export_range(0.01, 2.0, 0.01)
var fade_out_duration: float = 0.22


# ============================================================
# 3. 除錯設定
# ============================================================

@export_group("除錯設定")

## 是否顯示轉場耗時及操作紀錄
@export var debug_log: bool = true


# ============================================================
# 4. 節點與執行狀態
# ============================================================

@onready var black_screen: ColorRect = $BlackScreen

## 對外提供轉場狀態
##
## WorldEntry、MenuActions 與 BaseMap
## 皆可透過此變數確認轉場是否正在進行。
var is_transitioning: bool = false

## 轉場開始時的真實時間
var _transition_started_msec: int = 0

## 黑幕完全遮住畫面時的時間
var _black_started_msec: int = 0

## 黑幕完全遮蔽畫面的實際耗時
var _black_hold_msec: int = 0

## 玩家暫時操作鎖的原始資料
var _player_lock: Dictionary = {}


# ============================================================
# 5. 初始化
# ============================================================

func _ready() -> void:

	# 確保場景樹暫停時，轉場管理器仍可運作。
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 初始黑幕透明。
	black_screen.modulate.a = 0.0

	# 黑幕沒有作用時，不得阻擋任何 UI。
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	set_process_input(false)


# ============================================================
# 6. 轉場期間的輸入保護
#
# 阻擋輸入事件繼續傳遞至一般 GUI。
#
# 注意：
# Input.is_action_pressed() 屬於直接查詢輸入狀態，
# 不會因 set_input_as_handled() 而停止。
#
# 因此另有玩家狀態機暫時鎖定機制。
# ============================================================

func _input(_event: InputEvent) -> void:

	if is_transitioning:
		get_viewport().set_input_as_handled()


# ============================================================
# 7. 正式場景切換入口
#
# target_scene_path：
# 目標場景路徑
#
# target_spawn_name：
# 目標出生點節點名稱
#
# target_facing_dir：
# 玩家抵達後的面向
#
# Vector2.ZERO 代表不強制變更面向。
# ============================================================

func change_map(
	target_scene_path: String,
	target_spawn_name: String,
	target_facing_dir: Vector2 = Vector2.ZERO
) -> void:

	# --------------------------------------------------------
	# A. 防止重複轉場
	# --------------------------------------------------------

	if is_transitioning:
		return

	is_transitioning = true

	_transition_started_msec = Time.get_ticks_msec()
	_black_started_msec = 0
	_black_hold_msec = 0

	# --------------------------------------------------------
	# B. 驗證場景路徑
	#
	# 如果資源不存在，不進入黑幕，
	# 避免玩家留在無法操作的黑畫面。
	# --------------------------------------------------------

	if (
		target_scene_path.is_empty()
		or not ResourceLoader.exists(
			target_scene_path,
			"PackedScene"
		)
	):

		_finish_transition(
			false,
			target_scene_path,
			"目標場景資源不存在"
		)

		return

	# --------------------------------------------------------
	# C. 啟動背景非同步載入
	#
	# 先提出載入要求，再播放黑幕。
	# 讓資源載入與淡入動畫同時進行。
	# --------------------------------------------------------

	var request_error: Error = (
		ResourceLoader.load_threaded_request(
			target_scene_path,
			"PackedScene"
		)
	)

	if request_error != OK and request_error != ERR_BUSY:

		_finish_transition(
			false,
			target_scene_path,
			"背景載入要求失敗："
			+ error_string(request_error)
		)

		return

	# --------------------------------------------------------
	# D. 啟用轉場輸入保護
	# --------------------------------------------------------

	set_process_input(true)

	black_screen.mouse_filter = Control.MOUSE_FILTER_STOP

	# 只記錄這趟有沒有同行的白貓；舊地圖的節點會隨場景卸載。
	var cat_was_present := _find_map_cat(get_tree().current_scene) != null

	_lock_player(_find_current_player())

	transition_started.emit(target_scene_path)

	if debug_log:

		print(
			"【SceneTransition】開始轉場：",
			target_scene_path
		)

	# --------------------------------------------------------
	# E. 黑幕快速淡入
	# --------------------------------------------------------

	await _fade_black_screen(
		1.0,
		fade_in_duration
	)

	_black_started_msec = Time.get_ticks_msec()

	# --------------------------------------------------------
	# F. 確認背景載入狀態
	#
	# 每幀確認一次，不阻塞主執行緒。
	#
	# 只有狀態為 THREAD_LOAD_LOADED 時，
	# 才正式取出場景資源。
	# --------------------------------------------------------

	var load_status: int = (
		ResourceLoader.load_threaded_get_status(
			target_scene_path
		)
	)

	while load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:

		await get_tree().process_frame

		load_status = (
			ResourceLoader.load_threaded_get_status(
				target_scene_path
			)
		)

	# --------------------------------------------------------
	# G. 處理背景載入失敗
	#
	# 不再盲目使用同步載入作為替代，
	# 避免失敗後再次卡住主執行緒。
	# --------------------------------------------------------

	if load_status != ResourceLoader.THREAD_LOAD_LOADED:

		await _reveal_and_finish(
			false,
			target_scene_path,
			"背景資源載入失敗，狀態："
			+ str(load_status)
		)

		return

	var new_scene_packed: PackedScene = (
		ResourceLoader.load_threaded_get(
			target_scene_path
		) as PackedScene
	)

	if new_scene_packed == null:

		await _reveal_and_finish(
			false,
			target_scene_path,
			"載入的資源不是有效 PackedScene"
		)

		return

	# --------------------------------------------------------
	# H. 記錄舊場景金幣動畫進度
	# --------------------------------------------------------

	var coin_state: Dictionary = _capture_coin_state()

	# --------------------------------------------------------
	# I. 正式切換場景
	#
	# 使用已載入的 PackedScene，
	# 不需要再次從硬碟同步讀取。
	# --------------------------------------------------------

	var tree: SceneTree = get_tree()

	var change_error: Error = (
		tree.change_scene_to_packed(new_scene_packed)
	)

	if change_error != OK:

		await _reveal_and_finish(
			false,
			target_scene_path,
			"場景切換失敗："
			+ error_string(change_error)
		)

		return

	# --------------------------------------------------------
	# J. 等待真正的場景切換完成訊號
	#
	# Godot 4.5 的 scene_changed 訊號，
	# 代表新場景已加入 SceneTree，
	# 可安全取得 current_scene。
	#
	# 不再使用任意等待兩幀的方式猜測。
	# --------------------------------------------------------

	await tree.scene_changed

	# 舊場景玩家已卸載，清除舊的操作鎖資料。
	_player_lock.clear()

	var current_map: Node = tree.current_scene

	if current_map == null:

		await _reveal_and_finish(
			false,
			target_scene_path,
			"無法取得新場景根節點"
		)

		return

	# --------------------------------------------------------
	# K. 繼續鎖定新場景玩家
	#
	# 此處只暫停現有狀態機，
	# 不建立第二個玩家。
	# --------------------------------------------------------

	var player: Node2D = _find_current_player()

	_lock_player(player)

	# --------------------------------------------------------
	# L. 恢復金幣動畫進度
	# --------------------------------------------------------

	_restore_coin_state(coin_state)

	# --------------------------------------------------------
	# M. 玩家出生點定位
	# --------------------------------------------------------

	var spawn_success: bool = (
		_move_player_to_spawn(
			target_spawn_name,
			target_facing_dir,
			cat_was_present
		)
	)

	if not spawn_success:

		# 此時新場景已經載入。
		# 不強行切回舊場景，也不讓黑幕卡住。
		#
		# 保留玩家場景預設位置並輸出錯誤，
		# 供開發期間檢查出生點設定。

		await _reveal_and_finish(
			false,
			target_scene_path,
			"玩家或指定出生點不存在："
			+ target_spawn_name
		)

		return

	# --------------------------------------------------------
	# N. 地圖已準備完成
	#
	# 不增加任何額外黑幕停留時間。
	# 立即開始淡出。
	# --------------------------------------------------------

	await _reveal_and_finish(
		true,
		target_scene_path
	)


# ============================================================
# 8. 黑幕淡入淡出
#
# 使用真實時間播放 Tween。
#
# 不受 Engine.time_scale 影響，
# 避免受到 Hitstop 或慢動作效果拖延。
# ============================================================

func _fade_black_screen(
	target_alpha: float,
	duration: float
) -> void:

	black_screen.show()

	var tween: Tween = create_tween()

	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ignore_time_scale(true)

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		black_screen,
		"modulate:a",
		target_alpha,
		duration
	)

	await tween.finished


# ============================================================
# 9. 尋找目前場景的玩家
#
# 優先使用 DataManager 的玩家引用，
# 但必須確認該玩家屬於目前場景。
#
# 防止跨場景時誤用已經卸載的玩家。
# ============================================================

func _find_current_player() -> Node2D:

	var current_map: Node = get_tree().current_scene

	if current_map == null:
		return null

	var registered_player: Node2D = DataManager.player_node

	if is_instance_valid(registered_player):

		if (
			registered_player == current_map
			or current_map.is_ancestor_of(registered_player)
		):

			return registered_player

	# 備用方式：透過 player 群組尋找。
	for node in get_tree().get_nodes_in_group("player"):

		if (
			node is Node2D
			and (
				node == current_map
				or current_map.is_ancestor_of(node)
			)
		):

			return node as Node2D

	# 相容目前 AM001 使用的 player 節點名稱。
	return current_map.find_child(
		"player",
		true,
		false
	) as Node2D


# ============================================================
# 10. 暫時鎖定玩家操作
#
# 沿用 Player 現有的 state_machine。
#
# 不改動 is_in_dialogue，
# 避免與 CutsceneDirector 的劇情狀態混淆。
# ============================================================

func _lock_player(player: Node2D) -> void:

	if not is_instance_valid(player):
		return

	var machine: Node = null

	if "state_machine" in player:

		machine = player.get("state_machine") as Node

	# 保存原有狀態，以便轉場結束後恢復。
	_player_lock = {
		"player": player,
		"state_machine": machine
	}

	if is_instance_valid(machine):

		_player_lock["process_mode"] = machine.process_mode

		machine.process_mode = Node.PROCESS_MODE_DISABLED

	# 停止原本的移動速度。
	if player is CharacterBody2D:

		var body: CharacterBody2D = player as CharacterBody2D

		body.velocity = Vector2.ZERO


# ============================================================
# 11. 恢復玩家狀態機
#
# 如果玩家已經進入正式劇情，
# 則將操作控制權保留給 CutsceneDirector。
# ============================================================

func _unlock_player() -> void:

	if _player_lock.is_empty():
		return

	var player: Node2D = (
		_player_lock.get("player") as Node2D
	)

	var machine: Node = (
		_player_lock.get("state_machine") as Node
	)

	if (
		is_instance_valid(player)
		and is_instance_valid(machine)
	):

		var in_dialogue: bool = false

		if "is_in_dialogue" in player:

			in_dialogue = bool(
				player.get("is_in_dialogue")
			)

		if not in_dialogue:

			machine.process_mode = int(
				_player_lock.get(
					"process_mode",
					Node.PROCESS_MODE_INHERIT
				)
			)

	_player_lock.clear()


# ============================================================
# 12. 玩家定位、面向及相機重設
#
# 回傳 true：
# 玩家定位成功。
#
# 回傳 false：
# 找不到玩家或指定出生點。
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

	# 更新全域玩家引用。
	DataManager.player_node = player

	# 有指定出生點時，進行位置定位。
	if not spawn_name.is_empty():

		var target_spawn: Node2D = (
			current_map.find_child(
				spawn_name,
				true,
				false
			) as Node2D
		)

		if target_spawn == null:

			push_warning(
				"【SceneTransition】找不到出生點："
				+ spawn_name
			)

			return false

		player.global_position = target_spawn.global_position
		player.reset_physics_interpolation()
		if cat_was_present:
			var cat := _find_map_cat(current_map)
			if cat:
				_place_cat_at_entrance(cat, player, target_spawn, facing_dir)

	# 清除移動速度。
	if player is CharacterBody2D:

		var body: CharacterBody2D = player as CharacterBody2D

		body.velocity = Vector2.ZERO

	# 保留原本的過圖面向功能。
	if (
		facing_dir != Vector2.ZERO
		and player.has_method("set_facing_direction")
	):

		player.call(
			"set_facing_direction",
			facing_dir
		)

	# 優先取得目前正在使用的相機。
	var camera: Camera2D = get_viewport().get_camera_2d()

	if camera == null:

		camera = (
			get_tree().get_first_node_in_group("camera")
			as Camera2D
		)

	if is_instance_valid(camera):

		camera.reset_smoothing()
		camera.force_update_scroll()

	if debug_log:

		print(
			"【SceneTransition】玩家定位完成：",
			spawn_name,
			" / ",
			player.global_position
		)

	return true


# ============================================================
# 13. 記錄金幣動畫狀態
#
# 保留原本的 CoinSprite 接力機制。
# ============================================================

func _capture_coin_state() -> Dictionary:

	var coin: AnimatedSprite2D = (
		get_tree().root.find_child(
			"CoinSprite",
			true,
			false
		) as AnimatedSprite2D
	)

	if not is_instance_valid(coin):
		return {}

	return {
		"animation": coin.animation,
		"frame": coin.frame,
		"progress": coin.frame_progress
	}


# ============================================================
# 14. 恢復金幣動畫
#
# 使用前一場景的動畫名稱及播放進度。
# 並驗證新場景是否有對應動畫。
# ============================================================

func _restore_coin_state(state: Dictionary) -> void:

	if state.is_empty():
		return

	var coin: AnimatedSprite2D = (
		get_tree().root.find_child(
			"CoinSprite",
			true,
			false
		) as AnimatedSprite2D
	)

	if not is_instance_valid(coin):
		return

	if coin.sprite_frames == null:
		return

	var animation_name: StringName = StringName(
		state.get("animation", "spin")
	)

	if not coin.sprite_frames.has_animation(animation_name):
		return

	var frame_count: int = (
		coin.sprite_frames.get_frame_count(animation_name)
	)

	if frame_count <= 0:
		return

	var saved_frame: int = clampi(
		int(state.get("frame", 0)),
		0,
		frame_count - 1
	)

	var saved_progress: float = clampf(
		float(state.get("progress", 0.0)),
		0.0,
		1.0
	)

	coin.play(animation_name)

	coin.set_frame_and_progress(
		saved_frame,
		saved_progress
	)


# ============================================================
# 15. 黑幕淡出並結束轉場
#
# 成功與可處理的失敗都經過這個流程，
# 避免黑幕長時間停留。
# ============================================================

func _reveal_and_finish(
	success: bool,
	scene_path: String,
	reason: String = ""
) -> void:

	# 記錄全黑畫面實際停留時間。
	if _black_started_msec > 0:

		_black_hold_msec = (
			Time.get_ticks_msec()
			- _black_started_msec
		)

	# 場景準備完成後，直接淡出。
	await _fade_black_screen(
		0.0,
		fade_out_duration
	)

	_finish_transition(
		success,
		scene_path,
		reason
	)


# ============================================================
# 16. 統一結束轉場及解除操作鎖
# ============================================================

func _finish_transition(
	success: bool,
	scene_path: String,
	reason: String = ""
) -> void:

	# 確保黑幕回到透明狀態。
	black_screen.modulate.a = 0.0

	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 不再攔截輸入。
	set_process_input(false)

	# 恢復玩家原有操作狀態。
	_unlock_player()

	is_transitioning = false

	# 計算真實轉場時間。
	var elapsed_msec: int = (
		Time.get_ticks_msec()
		- _transition_started_msec
	)

	# 成功及失敗分別回報。
	if success:

		if debug_log:

			print(
				"【SceneTransition】轉場成功：",
				scene_path
			)

			print(
				"【SceneTransition】總耗時：%.3f 秒"
				% (float(elapsed_msec) / 1000.0)
			)

			print(
				"【SceneTransition】全黑停留：%.3f 秒"
				% (float(_black_hold_msec) / 1000.0)
			)

		transition_finished.emit(scene_path)

	else:

		push_warning(
			"【SceneTransition】轉場異常："
			+ scene_path
			+ " / "
			+ reason
		)

		transition_failed.emit(
			scene_path,
			reason
		)

	# 通知等待中的地圖初始化流程。
	transition_settled.emit(
		success,
		scene_path
	)


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

func _place_cat_at_entrance(cat: WhiteCat, player: Node2D, entrance: Node2D, facing_dir: Vector2) -> void:
	cat.player_node = player
	if player is PhysicsBody2D:
		cat.add_collision_exception_with(player)
		player.add_collision_exception_with(cat)

	# 狹窄或不規則的入口，可在玩家 Marker 下放一個名為 CatSpawn 的 Marker2D。
	var cat_marker := entrance.get_node_or_null("CatSpawn") as Marker2D
	if cat_marker:
		cat.global_position = cat_marker.global_position
	else:
		cat.global_position = _cat_position_beside_player(cat, player.global_position, facing_dir)

	cat.velocity = Vector2.ZERO
	cat.is_recalling = false
	cat.nav_agent.target_position = cat.global_position
	cat.reset_physics_interpolation()
	if not cat.is_stunned:
		cat.play_animation("idle", facing_dir)

func _cat_position_beside_player(cat: WhiteCat, arrival: Vector2, facing_dir: Vector2) -> Vector2:
	# 水平門先試下方，上下門先試右方；沿著入口邊緣站，避免直接退回門外。
	var side := Vector2.DOWN if absf(facing_dir.x) > absf(facing_dir.y) else Vector2.RIGHT
	var start := cat.global_transform
	start.origin = arrival
	var directions: Array[Vector2] = [side, -side, facing_dir.normalized()]
	for direction in directions:
		var step := direction * cat_spawn_distance
		if not cat.test_move(start, step):
			return arrival + step
	# 周圍都被擋時共用玩家落點。白貓與玩家有雙向碰撞例外。
	return arrival

extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# RespawnManager V1｜正式玩家死亡重生管理器
#
# Godot 4.5.1
# Autoload：RespawnManager
#
# STEP 10.6.7-A
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 接收玩家死亡後的重生要求
# 2. 取得目前正式存檔的檢查點
# 3. 解析地圖及畫架出生點
# 4. 呼叫 SceneTransition 執行重生轉場
# 5. 同步既有運行時重生資料
# 6. 恢復玩家血量及墨水
# 7. 防止重複重生
# 8. 保留 F6 開發測試相容性
#
# ============================================================
# 安全規則
# ============================================================
#
# 死亡不重新載入整份存檔。
# 不呼叫 SaveManager.load_slot()。
# 不呼叫 SaveManager.save_current_data()。
# 不建立、修改或刪除 JSON。
#
# 保留目前遊戲工作階段中的：
#
# - 劇情完成紀錄
# - 商人任務進度
# - 戰鬥解鎖
# - 藍色顏料解鎖
# - 金幣及死亡靈魂
# - 背包及貼紙資料
#
# 普通敵人透過重新載入地圖刷新。
#
# 本腳本不負責死亡動畫與死亡懲罰。
# 上述功能仍由 player_die.gd 管理。
# ============================================================


# ============================================================
# 1. 對外訊號
# ============================================================

signal respawn_started

signal respawn_finished

signal respawn_failed(reason: String)


# ============================================================
# 2. Inspector 設定
# ============================================================

@export_group("除錯設定")

@export var debug_log: bool = true


# ============================================================
# 3. 內部重生狀態
# ============================================================

## 是否正在執行正式死亡重生
var is_respawning: bool = false

var _pending_slot_id: int = 0

var _pending_map_id: String = ""

var _pending_easel_id: String = ""

var _pending_scene_path: String = ""


# ============================================================
# 4. 初始化
# ============================================================

func _ready() -> void:

	if not SceneTransition.transition_settled.is_connected(
		_on_transition_settled
	):

		SceneTransition.transition_settled.connect(
			_on_transition_settled
		)

	_log("V1 死亡重生管理器初始化完成")


# ============================================================
# 5. 正式死亡重生入口
#
# 由 player_die.gd 在死亡動畫播放完畢後呼叫。
#
# true：重生要求已受理。
# false：重生前置檢查失敗。
#
# 注意：
# true 不代表玩家已經完成重生。
# ============================================================

func request_respawn() -> bool:

	if is_respawning:
		return false

	if SceneTransition.is_transitioning:

		return _fail("目前已有場景正在切換")

	var player = DataManager.player_node

	if not is_instance_valid(player):

		return _fail("找不到目前玩家")

	if not player.is_dead:

		return _fail("玩家尚未進入死亡狀態")

	var slot_id: int = SaveManager.current_slot_id

	# 沒有正式存檔時，只允許開發版本使用舊重生流程。
	if slot_id <= 0:

		return _respawn_debug(player)

	return _respawn_formal(slot_id, player)


# ============================================================
# 6. 正式存檔死亡重生
#
# 使用目前已載入的存檔資料。
#
# 只讀取 checkpoint。
# 不重新載入完整存檔。
# 不重設劇情與背包資料。
# ============================================================

func _respawn_formal(
	slot_id: int,
	player: Player
) -> bool:

	# --------------------------------------------------------
	# A. 確認正式存檔仍然有效
	# --------------------------------------------------------

	if SaveManager.get_slot_state(slot_id) != SaveManager.SlotState.READY:

		return _fail("目前正式存檔狀態異常")

	# --------------------------------------------------------
	# B. 取得目前已保存的檢查點資料
	# --------------------------------------------------------

	var save_data: Dictionary = (
		SaveManager.get_current_data()
	)

	if typeof(save_data.get("checkpoint")) != TYPE_DICTIONARY:

		return _fail("checkpoint 資料格式異常")

	var checkpoint: Dictionary = save_data["checkpoint"]

	var map_id: String = String(
		checkpoint.get("map_id", "")
	)

	var easel_id: String = String(
		checkpoint.get("easel_id", "")
	)

	# --------------------------------------------------------
	# C. 解析正式出生位置
	# --------------------------------------------------------

	var resolved: Dictionary = (
		CheckpointManager.resolve_checkpoint(
			map_id,
			easel_id
		)
	)

	if resolved.is_empty():

		return _fail("找不到正式登記的重生檢查點")

	var scene_path: String = String(
		resolved["scene_path"]
	)

	var spawn_name: String = String(
		resolved["spawn_name"]
	)

	if not CheckpointManager.validate_checkpoint(
		map_id,
		easel_id
	):

		return _fail("重生地圖資源驗證失敗")

	# 確認出生定位點確實存在。
	# 不實例化場景，避免提前執行地圖劇情。
	if not _validate_spawn_marker(
		scene_path,
		spawn_name
	):

		return _fail("重生定位點不存在或名稱重複")

	# --------------------------------------------------------
	# D. 建立重生工作階段
	# --------------------------------------------------------

	is_respawning = true

	_pending_slot_id = slot_id

	_pending_map_id = map_id

	_pending_easel_id = easel_id

	_pending_scene_path = scene_path

	# --------------------------------------------------------
	# E. 準備新玩家的生命值
	#
	# Player._ready() 仍會讀取 saved_hp。
	# 不將死亡時的 0 HP 帶入新地圖。
	# --------------------------------------------------------

	DataManager.saved_hp = float(player.max_hp)

	player.velocity = Vector2.ZERO

	_log("開始正式死亡重生")

	_log("目前存檔：Slot %02d" % slot_id)

	_log("重生地圖 ID：" + map_id)

	_log("重生畫架 ID：" + easel_id)

	_log("目標場景：" + scene_path)

	_log("目標出生點：" + spawn_name)

	respawn_started.emit()

	# --------------------------------------------------------
	# F. 使用原有共用轉場系統
	#
	# 即使死亡地圖與重生地圖相同，
	# 仍重新載入場景，以刷新普通敵人。
	# --------------------------------------------------------

	get_tree().paused = false

	SceneTransition.change_map(
		scene_path,
		spawn_name,
		Vector2.DOWN
	)

	if not SceneTransition.is_transitioning:

		if is_respawning:

			_reset_pending()

			return _fail("SceneTransition 未能開始重生轉場")

		return false

	return true


# ============================================================
# 7. 驗證目標場景中的出生定位點
#
# 使用 PackedScene.get_state()。
#
# 不執行地圖 _ready()。
# 不建立玩家。
# 不觸發劇情。
#
# 目前正式登記的定位點皆直接存在於地圖場景。
# ============================================================

func _validate_spawn_marker(
	scene_path: String,
	spawn_name: String
) -> bool:

	var packed: PackedScene = (
		load(scene_path) as PackedScene
	)

	if packed == null:

		return false

	var scene_state: SceneState = packed.get_state()

	var name_count: int = 0

	var marker_count: int = 0

	for index in range(scene_state.get_node_count()):

		if String(scene_state.get_node_name(index)) != spawn_name:

			continue

		name_count += 1

		if scene_state.get_node_type(index) == &"Marker2D":

			marker_count += 1

	return name_count == 1 and marker_count == 1


# ============================================================
# 8. 接收正式轉場結果
#
# 本管理器為 Autoload。
#
# 即使原本的死亡玩家已經被卸載，
# 仍可持續接收 SceneTransition 的轉場結果。
# ============================================================

func _on_transition_settled(
	success: bool,
	scene_path: String
) -> void:

	# 一般過圖及主選單讀檔不屬於死亡重生。
	if not is_respawning:

		return

	if not success:

		_reset_pending()

		_fail("死亡重生轉場失敗")

		return

	if scene_path != _pending_scene_path:

		_reset_pending()

		_fail("重生完成的場景與要求不一致")

		return

	if SaveManager.current_slot_id != _pending_slot_id:

		_reset_pending()

		_fail("重生期間的存檔工作階段異常")

		return

	# --------------------------------------------------------
	# A. 驗證新玩家及重生位置
	# --------------------------------------------------------

	var player = DataManager.player_node

	if not is_instance_valid(player):

		_reset_pending()

		_fail("重生後找不到玩家")

		return

	var current_map: Node = get_tree().current_scene

	if not is_instance_valid(current_map):

		_reset_pending()

		_fail("重生後找不到地圖")

		return

	if not current_map.is_ancestor_of(player) or player.is_dead:

		_reset_pending()

		_fail("新玩家尚未完成正常初始化")

		return

	var marker: Marker2D = (
		CheckpointManager.get_current_spawn_marker(
			_pending_map_id,
			_pending_easel_id
		)
	)

	if not is_instance_valid(marker):

		_reset_pending()

		_fail("重生後找不到正式定位點")

		return

	# --------------------------------------------------------
	# B. 同步舊版運行時重生資料
	# --------------------------------------------------------

	DataManager.last_save_position = marker.global_position

	DataManager.save_map_path = current_map.scene_file_path

	DataManager.saved_hp = float(player.max_hp)

	# --------------------------------------------------------
	# C. 恢復玩家生命值及墨水
	#
	# 不修改背包、金幣及快捷欄配置。
	# --------------------------------------------------------

	player.current_hp = player.max_hp

	player.velocity = Vector2.ZERO

	player.update_hp_bar()

	player.refill_full_ink()

	# --------------------------------------------------------
	# D. 正式重生完成
	# --------------------------------------------------------

	_log(
		"Slot %02d 正式死亡重生成功"
		% _pending_slot_id
	)

	_log("重生位置：" + str(marker.global_position))

	_log("血量：" + str(player.current_hp))

	_log("墨水：" + str(player.current_ink))

	_log("保留原有劇情及死亡靈魂資料")

	_log("本次死亡重生未寫入 JSON")

	_reset_pending()

	respawn_finished.emit()


# ============================================================
# 9. F6 開發測試重生
#
# 保留舊版運行時重生機制。
#
# 已互動畫架並按下存檔：
# 回到測試用畫架。
#
# 尚未使用畫架：
# 重新載入目前地圖。
#
# 絕不建立或覆蓋正式存檔。
# ============================================================

func _respawn_debug(player: Player) -> bool:

	if not OS.is_debug_build():

		return _fail("未載入正式存檔")

	DataManager.saved_hp = float(player.max_hp)

	player.velocity = Vector2.ZERO

	var tree: SceneTree = get_tree()

	tree.paused = false

	var result: Error

	var target_path: String = DataManager.save_map_path

	if not target_path.is_empty():

		if not ResourceLoader.exists(
			target_path,
			"PackedScene"
		):

			return _fail("F6 測試重生地圖不存在")

		result = tree.change_scene_to_file(target_path)

	else:

		result = tree.reload_current_scene()

	if result != OK:

		return _fail(
			"F6 重生失敗：" + error_string(result)
		)

	_log("F6 測試重生要求已受理")

	_log("未建立或修改任何正式存檔")

	return true


# ============================================================
# 10. 清除重生工作階段
# ============================================================

func _reset_pending() -> void:

	is_respawning = false

	_pending_slot_id = 0

	_pending_map_id = ""

	_pending_easel_id = ""

	_pending_scene_path = ""


# ============================================================
# 11. 統一錯誤處理
#
# 正式重生失敗時，不擅自將玩家送回初始地圖。
# 避免掩蓋存檔及定位設定錯誤。
# ============================================================

func _fail(reason: String) -> bool:

	push_error(
		"【RespawnManager】死亡重生失敗：" + reason
	)

	respawn_failed.emit(reason)

	return false


# ============================================================
# 12. 統一除錯輸出
# ============================================================

func _log(message: String) -> void:

	if debug_log:

		print("【RespawnManager】" + message)

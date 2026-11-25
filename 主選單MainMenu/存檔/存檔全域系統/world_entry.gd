
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# WorldEntry V3｜正式遊戲進場與重生資料同步管理器
#
# Godot：4.5.1
# Autoload：WorldEntry
#
# STEP 10.6.5
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 接收主選單正式讀檔要求
# 2. 驗證指定存檔與檢查點
# 3. 呼叫 SaveManager 還原正式存檔
# 4. 透過 CheckpointManager 解析地圖及出生點
# 5. 交由 SceneTransition 執行正式進場
# 6. 監聽實際轉場成功或失敗
# 7. 還原運行時重生位置及地圖路徑
# 8. 同步玩家重生血量基準
# 9. 防止不同存檔繼承舊重生資料
# 10. 防止普通跨地圖傳送覆蓋正式重生點
#
# ============================================================
# V3 新增功能
# ============================================================
#
# 正式讀檔成功後，自動同步：
#
# DataManager.last_save_position
# DataManager.save_map_path
# DataManager.saved_hp
#
# 不再只完成玩家出生定位，
# 而是同時還原既有死亡重生系統所需的資料。
#
# ============================================================
# 相容性
# ============================================================
#
# 保留原有 load_existing_slot() 呼叫介面。
#
# 不修改：
# - 主選單 UI
# - 畫架 UI
# - 地圖登記表
# - 既有 JSON 存檔格式
# - StoryProgress 永久劇情保存機制
# - A001、A005、A008 劇情還原規則
# - 白貓跟隨系統
#
# ============================================================
# 不負責
# ============================================================
#
# - JSON 實體檔案寫入
# - 玩家死亡動畫
# - 玩家永久能力數值還原
# - 背包及裝備永久保存
# - 普通敵人刷新
# - 畫架快速傳送
# - 初見畫架劇情保存
#
# 上述功能由各自的正式系統負責。
# ============================================================


# ============================================================
# 1. 對外訊號
# ============================================================

## 正式進場要求已提出。
## 不代表地圖已完成載入。
signal entry_requested(
	slot_id: int,
	map_id: String
)


## 正式進場要求或後續轉場驗證失敗。
signal entry_rejected(
	slot_id: int,
	reason: String
)


## 正式進場完成，且運行時重生資料已同步。
signal entry_completed(
	slot_id: int,
	map_id: String,
	easel_id: String
)


# ============================================================
# 2. Inspector 設定
# ============================================================

@export_group("除錯設定")

## 正式發行前可關閉一般除錯輸出。
## 錯誤及警告仍會正常顯示。
@export var debug_log: bool = true


# ============================================================
# 3. 正式進場操作鎖
# ============================================================

## 是否存在尚未完成的正式進場要求。
##
## 從正式讀檔開始，
## 直到 SceneTransition 回報結果才解除。
var _entry_pending: bool = false


## 本次準備載入的存檔編號。
var _pending_slot_id: int = 0


## 本次正式進場的完整檢查點資料。
var _pending_checkpoint: Dictionary = {}


# ============================================================
# 4. 正式讀取已有存檔
#
# 保留 V2 原有對外介面。
#
# 回傳 true：
# 正式進場要求已受理。
#
# 回傳 false：
# 前置驗證或立即啟動轉場失敗。
#
# 注意：
# true 不代表已完成地圖載入。
# 最終結果由 entry_completed 或 entry_rejected 通知。
# ============================================================

func load_existing_slot(slot_id: int) -> bool:

	# --------------------------------------------------------
	# A. 防止重複進場
	# --------------------------------------------------------

	if _entry_pending:

		return _reject(
			slot_id,
			"已有尚未完成的進場要求"
		)

	if SceneTransition.is_transitioning:

		return _reject(
			slot_id,
			"場景正在切換"
		)

	# --------------------------------------------------------
	# B. 驗證正式存檔狀態
	#
	# 只允許正常存檔進入遊戲。
	# 備份復原功能由後續階段處理。
	# --------------------------------------------------------

	if (
		SaveManager.get_slot_state(slot_id)
		!= SaveManager.SlotState.READY
	):

		return _reject(
			slot_id,
			"指定欄位沒有正常存檔"
		)

	# --------------------------------------------------------
	# C. 取得正式檢查點資料
	#
	# 不直接讀取 JSON。
	# 統一透過 SaveManager 查詢。
	# --------------------------------------------------------

	var summary: Dictionary = (
		SaveManager.get_slot_summary(slot_id)
	)

	var map_id: String = str(
		summary.get("map_id", "")
	)

	var easel_id: String = str(
		summary.get("easel_id", "")
	)

	# --------------------------------------------------------
	# D. 解析正式地圖及出生點
	#
	# WorldEntry 不另外維護地圖登記表。
	# 統一使用 CheckpointManager。
	# --------------------------------------------------------

	var checkpoint: Dictionary = (
		CheckpointManager.resolve_checkpoint(
			map_id,
			easel_id
		)
	)

	if checkpoint.is_empty():

		return _reject(
			slot_id,
			"尚未登記檢查點：%s / %s"
			% [map_id, easel_id]
		)

	if not CheckpointManager.validate_checkpoint(
		map_id,
		easel_id
	):

		return _reject(
			slot_id,
			"地圖或檢查點資源無效"
		)

	var scene_path: String = (
		checkpoint["scene_path"]
	)

	var spawn_name: String = (
		checkpoint["spawn_name"]
	)

	# --------------------------------------------------------
	# E. 建立本次進場工作階段
	#
	# 必須在正式載入前建立操作鎖，
	# 防止其他訊號重複觸發進場。
	# --------------------------------------------------------

	_entry_pending = true

	_pending_slot_id = slot_id

	_pending_checkpoint = (
		checkpoint.duplicate(true)
	)

	# --------------------------------------------------------
	# F. 正式載入存檔
	#
	# SaveManager 成功載入後，
	# 會發送 slot_loaded 訊號。
	#
	# StoryProgress 仍透過原有訊號還原：
	#
	# - A001 開場劇情
	# - A005 初見白國王
	# - A008 樹林聲音劇情
	# - 商人任務進度
	# - 戰鬥解鎖狀態
	# - 永久事件旗標
	#
	# 本腳本不重新實作劇情還原。
	# --------------------------------------------------------

	if not SaveManager.load_slot(slot_id):

		_clear_pending_entry()

		return _reject(
			slot_id,
			"SaveManager 讀取存檔失敗"
		)

	# --------------------------------------------------------
	# G. 再次驗證已載入的正式資料
	#
	# 避免存檔摘要與實際載入的資料不一致，
	# 造成玩家進入錯誤地圖或出生位置。
	# --------------------------------------------------------

	if not _matches_loaded_checkpoint(
		slot_id,
		map_id,
		easel_id
	):

		_clear_runtime_respawn()

		_clear_pending_entry()

		return _reject(
			slot_id,
			"已載入存檔與進場檢查點不一致"
		)

	# --------------------------------------------------------
	# H. 清除上一格存檔的運行時重生資料
	#
	# 必須在新地圖建立前執行。
	#
	# 避免玩家初始化時誤用上一格的：
	# - 重生座標
	# - 重生地圖
	# - 血量紀錄
	#
	# 此處不修改任何磁碟存檔。
	# --------------------------------------------------------

	_clear_runtime_respawn()

	# 清除原有快速傳送旗標。
	# 避免 BaseMap 使用舊 PortalSpawnPoint
	# 覆蓋正式讀檔出生位置。

	DataManager.is_teleporting = false

	# --------------------------------------------------------
	# I. 連接正式轉場結果
	#
	# 必須在提出轉場要求前完成連接。
	#
	# 不使用固定等待秒數，
	# 不自行猜測地圖是否已經載入。
	#
	# 只有本次正式讀檔需要監聽。
	# 普通傳送門不會使用此重生同步流程。
	# --------------------------------------------------------

	SceneTransition.transition_finished.connect(
		_on_entry_transition_finished
	)

	SceneTransition.transition_failed.connect(
		_on_entry_transition_failed
	)

	if debug_log:

		print(
			"【WorldEntry】讀取 Slot %02d"
			% slot_id
		)

		print(
			"【WorldEntry】地圖 ID：",
			map_id
		)

		print(
			"【WorldEntry】檢查點 ID：",
			easel_id
		)

		print(
			"【WorldEntry】目標地圖：",
			scene_path
		)

		print(
			"【WorldEntry】目標出生點：",
			spawn_name
		)

	# --------------------------------------------------------
	# J. 提出正式進場要求
	#
	# 保留原有 SceneTransition.change_map()。
	#
	# 不直接操作 SceneTree。
	# 不自行建立第二個玩家。
	# 不自行移動白貓。
	# --------------------------------------------------------

	entry_requested.emit(
		slot_id,
		map_id
	)

	SceneTransition.change_map(
		scene_path,
		spawn_name,
		Vector2.ZERO
	)

	# --------------------------------------------------------
	# K. 確認轉場要求已受理
	#
	# 如果 SceneTransition 立即回報失敗，
	# 對應的失敗回呼會解除操作鎖。
	# --------------------------------------------------------

	if not SceneTransition.is_transitioning:

		if _entry_pending:

			_clear_pending_entry()

			return _reject(
				slot_id,
				"SceneTransition 未能開始轉場"
			)

		return false

	return true


# ============================================================
# 5. 驗證目前工作階段與正式檢查點
#
# 不信任上一格存檔的運行時資料。
#
# 必須確認：
# A. 存檔編號一致
# B. checkpoint 資料格式正確
# C. 地圖 ID 一致
# D. 畫架 ID 一致
# ============================================================

func _matches_loaded_checkpoint(
	slot_id: int,
	map_id: String,
	easel_id: String
) -> bool:

	if SaveManager.current_slot_id != slot_id:

		return false

	var data: Dictionary = (
		SaveManager.get_current_data()
	)

	var raw_checkpoint: Variant = (
		data.get("checkpoint")
	)

	if typeof(raw_checkpoint) != TYPE_DICTIONARY:

		return false

	var checkpoint: Dictionary = raw_checkpoint

	return (
		checkpoint.get("map_id", "") == map_id
		and checkpoint.get("easel_id", "") == easel_id
	)


# ============================================================
# 6. 正式讀檔轉場成功
#
# V3 核心新增功能。
#
# SceneTransition 會先發送 transition_finished，
# 接著才發送 transition_settled。
#
# 此時：
#
# - 新地圖已加入 SceneTree
# - 玩家已完成出生定位
# - 玩家相機已完成設定
# - BaseMap 等待中的開場流程尚未因 settled 恢復
#
# 因此可在此同步正式重生資料。
#
# 不使用固定秒數或任意等待幀數。
# ============================================================

func _on_entry_transition_finished(
	scene_path: String
) -> void:

	if not _entry_pending:

		return

	var slot_id: int = _pending_slot_id

	var map_id: String = (
		_pending_checkpoint["map_id"]
	)

	var easel_id: String = (
		_pending_checkpoint["easel_id"]
	)

	var expected_path: String = (
		_pending_checkpoint["scene_path"]
	)

	# --------------------------------------------------------
	# A. 確認完成轉場的地圖符合本次要求
	# --------------------------------------------------------

	if scene_path != expected_path:

		_fail_pending_entry(
			"完成轉場的地圖與讀檔要求不符"
		)

		return

	# 再次確認正式存檔工作階段沒有變更。

	if not _matches_loaded_checkpoint(
		slot_id,
		map_id,
		easel_id
	):

		_fail_pending_entry(
			"轉場期間存檔工作階段或檢查點已變更"
		)

		return

	# --------------------------------------------------------
	# B. 取得正式重生定位點
	#
	# 必須是 CheckpointManager 認可的：
	#
	# - 正確地圖
	# - 正確畫架
	# - 唯一 Marker2D
	#
	# AM001 初始出生點可用於重生資料還原，
	# 但仍不可以作為正式畫架執行 save_checkpoint()。
	# --------------------------------------------------------

	var marker: Marker2D = (
		CheckpointManager.get_current_spawn_marker(
			map_id,
			easel_id
		)
	)

	var current_map: Node = (
		get_tree().current_scene
	)

	if (
		not is_instance_valid(marker)
		or not is_instance_valid(current_map)
	):

		_fail_pending_entry(
			"讀檔地圖缺少合法且唯一的 Marker2D"
		)

		return

	if current_map.scene_file_path != expected_path:

		_fail_pending_entry(
			"目前場景與正式檢查點不一致"
		)

		return

	# --------------------------------------------------------
	# C. 驗證目前地圖中的正式玩家
	#
	# 不使用上一張地圖已卸載的玩家。
	# 不使用其他場景的玩家引用。
	# --------------------------------------------------------

	var player: Player = (
		DataManager.player_node as Player
	)

	if not is_instance_valid(player):

		_fail_pending_entry(
			"找不到目前地圖的玩家"
		)

		return

	if not current_map.is_ancestor_of(player):

		_fail_pending_entry(
			"玩家不屬於目前讀檔地圖"
		)

		return

	# --------------------------------------------------------
	# D. 取得重生血量及座標
	#
	# 沿用原有畫架存檔補滿血量的規則。
	#
	# 不將尚未實作的 player.stats
	# 當作正式永久能力資料。
	#
	# 不直接修改玩家目前 HP 或 HUD。
	# --------------------------------------------------------

	var respawn_hp: float = float(
		player.max_hp
	)

	if (
		not is_finite(respawn_hp)
		or respawn_hp <= 0.0
	):

		_fail_pending_entry(
			"玩家最大血量無效"
		)

		return

	var respawn_position: Vector2 = (
		marker.global_position
	)

	if not respawn_position.is_finite():

		_fail_pending_entry(
			"重生定位點座標無效"
		)

		return

	# --------------------------------------------------------
	# E. 正式同步運行時重生資料
	#
	# 所有驗證成功後才一次更新。
	#
	# 不保存玩家任意站立位置。
	# 使用正式 Marker2D 世界座標。
	#
	# 此處只同步記憶體資料，
	# 不重新寫入 JSON。
	# --------------------------------------------------------

	DataManager.last_save_position = (
		respawn_position
	)

	DataManager.save_map_path = (
		expected_path
	)

	DataManager.saved_hp = (
		respawn_hp
	)

	# --------------------------------------------------------
	# F. 正式同步完成通知
	# --------------------------------------------------------

	if debug_log:

		print(
			"【WorldEntry】Slot %02d 正式讀檔及重生資料同步成功"
			% slot_id
		)

		print(
			"【WorldEntry】last_save_position：",
			DataManager.last_save_position
		)

		print(
			"【WorldEntry】save_map_path：",
			DataManager.save_map_path
		)

		print(
			"【WorldEntry】saved_hp：",
			DataManager.saved_hp
		)

	# 先解除操作鎖並移除轉場監聽，
	# 避免後續一般跨地圖傳送再次觸發。

	_clear_pending_entry()

	entry_completed.emit(
		slot_id,
		map_id,
		easel_id
	)


# ============================================================
# 7. 正式讀檔轉場失敗
#
# 不回寫 JSON。
# 不使用任意座標。
# 不恢復上一格存檔的重生資料。
#
# 黑幕及轉場操作鎖的處理，
# 仍由 SceneTransition 負責。
# ============================================================

func _on_entry_transition_failed(
	scene_path: String,
	reason: String
) -> void:

	if not _entry_pending:

		return

	_fail_pending_entry(
		"轉場失敗：%s / %s"
		% [scene_path, reason]
	)


func _fail_pending_entry(
	reason: String
) -> void:

	var slot_id: int = _pending_slot_id

	_clear_runtime_respawn()

	_clear_pending_entry()

	_reject(
		slot_id,
		reason
	)


# ============================================================
# 8. 清除舊版運行時重生資料
#
# 使用 DataManager 原本的預設值。
#
# 只清除運行時重生資料，
# 不修改永久存檔內容及劇情完成紀錄。
# ============================================================

func _clear_runtime_respawn() -> void:

	DataManager.last_save_position = Vector2.ZERO

	DataManager.save_map_path = ""

	DataManager.saved_hp = 0.0


# ============================================================
# 9. 解除正式進場工作階段
#
# 無論進場成功或失敗，
# 都必須解除本次專用訊號監聽。
#
# 避免一般傳送門、快速傳送或後續地圖切換，
# 錯誤覆蓋最後正式存檔點。
# ============================================================

func _clear_pending_entry() -> void:

	if SceneTransition.transition_finished.is_connected(
		_on_entry_transition_finished
	):

		SceneTransition.transition_finished.disconnect(
			_on_entry_transition_finished
		)

	if SceneTransition.transition_failed.is_connected(
		_on_entry_transition_failed
	):

		SceneTransition.transition_failed.disconnect(
			_on_entry_transition_failed
		)

	_entry_pending = false

	_pending_slot_id = 0

	_pending_checkpoint.clear()


# ============================================================
# 10. 保留 V2 相容接口
#
# 地圖及出生點查詢統一交給 CheckpointManager。
# 不在此建立第二份地圖登記表。
# ============================================================

func _resolve_map_scene(
	map_id: String
) -> String:

	return CheckpointManager.resolve_map_scene(
		map_id
	)


func _resolve_spawn_name(
	map_id: String,
	easel_id: String
) -> String:

	return CheckpointManager.resolve_spawn_name(
		map_id,
		easel_id
	)


# ============================================================
# 11. 統一進場失敗處理
#
# 所有拒絕操作統一使用相同訊號及輸出格式。
#
# 本函式不直接修改存檔資料。
# ============================================================

func _reject(
	slot_id: int,
	reason: String
) -> bool:

	push_warning(
		"【WorldEntry】Slot %02d 無法進場：%s"
		% [slot_id, reason]
	)

	entry_rejected.emit(
		slot_id,
		reason
	)

	return false

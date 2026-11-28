
extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# WorldEntry V5｜正式進場與中央工作階段防護管理器
# Godot 4.5.1
# Autoload：WorldEntry
# STEP 10.8.9-A
# ============================================================
# 主要職責：
# 1. 接收主選單正式讀檔要求。
# 2. 驗證存檔及正式檢查點。
# 3. 呼叫 SaveManager 還原正式存檔。
# 4. 驗證世界永久資料工作階段。
# 5. 阻止異常世界資料直接進場。
# 6. 透過 SceneTransition 執行正式轉場。
# 7. 監聽轉場完成及失敗。
# 8. 同步正式死亡重生位置及血量基準。
# 9. V5：異常進場統一使用中央清理機制。
#
# 保留 load_existing_slot() 公開接口。
# 不直接操作 JSON。
# 不修改既有地圖登記及出生定位規則。
# 不修改玩家、白貓及劇情系統。
# ============================================================

# 1. 對外訊號
signal entry_requested(slot_id: int, map_id: String)
signal entry_rejected(slot_id: int, reason: String)
signal entry_completed(slot_id: int, map_id: String, easel_id: String)

# 2. Inspector 設定
@export_group("除錯設定")
@export var debug_log: bool = true

# 3. 正式進場工作階段
var _entry_pending: bool = false
var _pending_slot_id: int = 0
var _pending_checkpoint: Dictionary = {}

# ============================================================
# 4. 正式讀取已有存檔
# true 代表進場要求已受理，不代表轉場完成。
# ============================================================
func load_existing_slot(slot_id: int) -> bool:
	# A. 防止重複進場及轉場衝突。
	if _entry_pending:
		return _reject(slot_id, "已有尚未完成的進場要求")
	if SceneTransition.is_transitioning:
		return _reject(slot_id, "場景正在切換")
	# B. 驗證正式存檔狀態。
	if SaveManager.get_slot_state(slot_id) != SaveManager.SlotState.READY:
		return _reject(slot_id, "指定欄位沒有正常存檔")
	# C. 取得正式檢查點摘要。
	var summary: Dictionary = SaveManager.get_slot_summary(slot_id)
	var map_id: String = str(summary.get("map_id", ""))
	var easel_id: String = str(summary.get("easel_id", ""))
	# D. 解析正式地圖及出生點。
	var checkpoint: Dictionary = CheckpointManager.resolve_checkpoint(map_id, easel_id)
	if checkpoint.is_empty():
		return _reject(slot_id, "尚未登記檢查點：%s / %s" % [map_id, easel_id])
	if not CheckpointManager.validate_checkpoint(map_id, easel_id):
		return _reject(slot_id, "地圖或檢查點資源無效")
	var scene_path: String = checkpoint["scene_path"]
	var spawn_name: String = checkpoint["spawn_name"]
	# E. 建立本次進場工作階段。
	_entry_pending = true
	_pending_slot_id = slot_id
	_pending_checkpoint = checkpoint.duplicate(true)
	# F. 正式載入存檔。
	# 各永久管理器透過 slot_loaded 同步還原資料。
	if not SaveManager.load_slot(slot_id):
		_clear_pending_entry()
		return _reject(slot_id, "SaveManager 讀取存檔失敗")
	# G. 確認正式檢查點。
	if not _matches_loaded_checkpoint(slot_id, map_id, easel_id):
		return _reject_loaded_entry(slot_id, "已載入存檔與進場檢查點不一致")
	# H. 正式世界資料進場防護。
	if not _has_valid_world_session(slot_id):
		return _reject_loaded_entry(slot_id, "世界永久資料還原失敗，已阻止正式進場")
	if debug_log:
		print("【WorldEntry】Slot %02d 世界永久資料進場驗證通過" % slot_id)
	# I. 清除上一格存檔的重生資料。
	_clear_runtime_respawn()
	DataManager.is_teleporting = false
	# J. 連接本次專用轉場訊號。
	SceneTransition.transition_finished.connect(_on_entry_transition_finished)
	SceneTransition.transition_failed.connect(_on_entry_transition_failed)
	if debug_log:
		print("【WorldEntry】讀取 Slot %02d" % slot_id)
		print("【WorldEntry】地圖 ID：", map_id)
		print("【WorldEntry】檢查點 ID：", easel_id)
		print("【WorldEntry】目標地圖：", scene_path)
		print("【WorldEntry】目標出生點：", spawn_name)
	# K. 提出正式進場要求。
	entry_requested.emit(slot_id, map_id)
	SceneTransition.change_map(scene_path, spawn_name, Vector2.ZERO)
	# L. 確認轉場要求已受理。
	if not SceneTransition.is_transitioning:
		if _entry_pending:
			_clear_pending_entry()
			return _reject(slot_id, "SceneTransition 未能開始轉場")
		return false
	return true

# 5. 驗證正式存檔及檢查點
func _matches_loaded_checkpoint(slot_id: int, map_id: String, easel_id: String) -> bool:
	if SaveManager.current_slot_id != slot_id:
		return false
	var data: Dictionary = SaveManager.get_current_data()
	var raw_checkpoint: Variant = data.get("checkpoint")
	if typeof(raw_checkpoint) != TYPE_DICTIONARY:
		return false
	var checkpoint: Dictionary = raw_checkpoint
	return (
		checkpoint.get("map_id", "") == map_id
		and checkpoint.get("easel_id", "") == easel_id
	)

# 6. 驗證正式世界資料工作階段
func _has_valid_world_session(slot_id: int) -> bool:
	return (
		WorldProgress.is_initialized()
		and WorldProgress.has_active_session()
		and WorldProgress.get_loaded_slot_id() == slot_id
		and WorldProgress.can_save_world()
	)

# ============================================================
# 7. 拒絕已載入但尚未正式進場的存檔
#
# V5：只呼叫中央 close_session()。
# 各永久管理器透過 session_closed 自行清理。
# 不覆蓋或刪除異常存檔。
# ============================================================
func _reject_loaded_entry(slot_id: int, reason: String) -> bool:
	if SaveManager.current_slot_id == slot_id:
		_clear_runtime_respawn()
		DataManager.is_teleporting = false
		SaveManager.close_session()
	_clear_pending_entry()
	if debug_log:
		print("【WorldEntry】異常進場要求已取消")
		print("【WorldEntry】目前正式存檔：", SaveManager.current_slot_id)
		print("【WorldEntry】WorldProgress 工作階段：", WorldProgress.get_loaded_slot_id())
		print("【WorldEntry】本次拒絕進場未寫入 JSON")
	return _reject(slot_id, reason)

# ============================================================
# 8. 正式讀檔轉場成功
# 在地圖開場流程恢復前同步正式重生資料。
# ============================================================
func _on_entry_transition_finished(scene_path: String) -> void:
	if not _entry_pending:
		return
	var slot_id: int = _pending_slot_id
	var map_id: String = _pending_checkpoint["map_id"]
	var easel_id: String = _pending_checkpoint["easel_id"]
	var expected_path: String = _pending_checkpoint["scene_path"]
	# A. 驗證轉場地圖及正式工作階段。
	if scene_path != expected_path:
		_fail_pending_entry("完成轉場的地圖與讀檔要求不符")
		return
	if not _matches_loaded_checkpoint(slot_id, map_id, easel_id):
		_fail_pending_entry("轉場期間存檔工作階段或檢查點已變更")
		return
	if not _has_valid_world_session(slot_id):
		_fail_pending_entry("轉場期間世界永久資料工作階段已失效")
		return
	# B. 驗證正式重生定位點。
	var marker: Marker2D = CheckpointManager.get_current_spawn_marker(map_id, easel_id)
	var current_map: Node = get_tree().current_scene
	if not is_instance_valid(marker) or not is_instance_valid(current_map):
		_fail_pending_entry("讀檔地圖缺少合法且唯一的 Marker2D")
		return
	if current_map.scene_file_path != expected_path:
		_fail_pending_entry("目前場景與正式檢查點不一致")
		return
	# C. 驗證目前地圖中的正式玩家。
	var player: Player = DataManager.player_node as Player
	if not is_instance_valid(player):
		_fail_pending_entry("找不到目前地圖的玩家")
		return
	if not current_map.is_ancestor_of(player):
		_fail_pending_entry("玩家不屬於目前讀檔地圖")
		return
	# D. 驗證正式重生血量及座標。
	var respawn_hp: float = float(player.max_hp)
	if not is_finite(respawn_hp) or respawn_hp <= 0.0:
		_fail_pending_entry("玩家最大血量無效")
		return
	var respawn_position: Vector2 = marker.global_position
	if not respawn_position.is_finite():
		_fail_pending_entry("重生定位點座標無效")
		return
	# E. 同步正式重生資料。
	DataManager.last_save_position = respawn_position
	DataManager.save_map_path = expected_path
	DataManager.saved_hp = respawn_hp
	# F. 正式同步完成通知。
	if debug_log:
		print("【WorldEntry】Slot %02d 正式讀檔及重生資料同步成功" % slot_id)
		print("【WorldEntry】last_save_position：", DataManager.last_save_position)
		print("【WorldEntry】save_map_path：", DataManager.save_map_path)
		print("【WorldEntry】saved_hp：", DataManager.saved_hp)
		print("【WorldEntry】世界永久資料工作階段同步正常")
	_clear_pending_entry()
	entry_completed.emit(slot_id, map_id, easel_id)

# 9. 正式讀檔轉場失敗
func _on_entry_transition_failed(scene_path: String, reason: String) -> void:
	if not _entry_pending:
		return
	_fail_pending_entry("轉場失敗：%s / %s" % [scene_path, reason])

func _fail_pending_entry(reason: String) -> void:
	var slot_id: int = _pending_slot_id
	_clear_runtime_respawn()
	_clear_pending_entry()
	_reject(slot_id, reason)

# 10. 清除舊版運行時重生資料
func _clear_runtime_respawn() -> void:
	DataManager.last_save_position = Vector2.ZERO
	DataManager.save_map_path = ""
	DataManager.saved_hp = 0.0

# 11. 解除正式進場工作階段
func _clear_pending_entry() -> void:
	if SceneTransition.transition_finished.is_connected(_on_entry_transition_finished):
		SceneTransition.transition_finished.disconnect(_on_entry_transition_finished)
	if SceneTransition.transition_failed.is_connected(_on_entry_transition_failed):
		SceneTransition.transition_failed.disconnect(_on_entry_transition_failed)
	_entry_pending = false
	_pending_slot_id = 0
	_pending_checkpoint.clear()

# 12. 保留舊版相容接口
func _resolve_map_scene(map_id: String) -> String:
	return CheckpointManager.resolve_map_scene(map_id)

func _resolve_spawn_name(map_id: String, easel_id: String) -> String:
	return CheckpointManager.resolve_spawn_name(map_id, easel_id)

# 13. 統一進場失敗處理
func _reject(slot_id: int, reason: String) -> bool:
	push_warning("【WorldEntry】Slot %02d 無法進場：%s" % [slot_id, reason])
	entry_rejected.emit(slot_id, reason)
	return false


extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# WorldProgress V2｜世界永久狀態核心管理器
# Godot 4.5.1
# Autoload：WorldProgress
# STEP 10.8.9-A
# ============================================================
# 主要職責：
# 1. 管理世界永久狀態的運行時資料。
# 2. 驗證永久狀態 ID 及資料格式。
# 3. 保存及還原 Boss 擊敗紀錄。
# 4. 保存及還原捷徑開啟紀錄。
# 5. 保存及還原唯一性道具取得紀錄。
# 6. 管理正式存檔工作階段。
# 7. 防止跨存檔資料污染。
# 8. 防止永久完成紀錄意外遺失。
# 9. 提供正式存檔候選資料整合接口。
# 10. V2：接入 SaveManager 中央工作階段清理訊號。
#
# 系統分工：
# SaveManager：正式 JSON 讀寫及備份。
# CheckpointManager：畫架及正式保存整合。
# StoryProgress：永久劇情及既有任務資料。
# PlayerProgress：永久玩家資料。
# WorldProgress：永久世界狀態。
#
# 不直接操作 JSON。
# 不自行建立或觸發存檔。
# 不管理普通敵人死亡紀錄。
# 不接管 StoryProgress 的資料。
# 不修改 Schema Version 1。
# ============================================================

# 1. 對外訊號
signal world_restored(slot_id: int)
signal world_restore_failed(slot_id: int, reason: String)
signal world_state_changed(slot_id: int, category: String, world_id: String)

# 2. 正式資料欄位
const WORLD_FIELD: String = "world"
const BOSS_FIELD: String = "defeated_bosses"
const SHORTCUT_FIELD: String = "opened_shortcuts"
const UNIQUE_ITEM_FIELD: String = "collected_unique_items"
const MANAGED_FIELDS: Array[String] = [
	BOSS_FIELD,
	SHORTCUT_FIELD,
	UNIQUE_ITEM_FIELD
]
const MAX_ID_LENGTH: int = 96

# 3. Inspector 設定
@export_group("除錯設定")
@export var debug_log: bool = true

# 4. 正式世界工作階段
var _loaded_slot_id: int = 0
var _initialized: bool = false
var _world_data_valid: bool = false
var _runtime_world: Dictionary = {}

# ============================================================
# 5. 初始化
# 必須在 SaveManager 之後初始化。
# ============================================================
func _ready() -> void:
	_runtime_world = build_initial_world_data()
	if SaveManager.current_slot_id != 0:
		push_error("【WorldProgress】初始化時已有存檔工作階段")
		return
	if not SaveManager.slot_created.is_connected(_on_slot_created):
		SaveManager.slot_created.connect(_on_slot_created)
	if not SaveManager.slot_loaded.is_connected(_on_slot_loaded):
		SaveManager.slot_loaded.connect(_on_slot_loaded)
	# V2：統一監聽正式工作階段結束訊號。
	if not SaveManager.session_closed.is_connected(_on_session_closed):
		SaveManager.session_closed.connect(_on_session_closed)
	# 不監聽 slot_saved 進行還原。
	# 避免劇情保存時重設未保存的世界狀態。
	_initialized = true
	_log("V2 世界永久狀態管理器初始化完成")
	_log("目前管理資料類型：3")
	_log("存檔格式相容版本：Schema 1")
	_log("中央工作階段清理訊號已連接")
	_log("等待正式存檔工作階段")

# 6. 建立初始世界資料
func build_initial_world_data() -> Dictionary:
	return {
		BOSS_FIELD: {},
		SHORTCUT_FIELD: {},
		UNIQUE_ITEM_FIELD: {}
	}

# ============================================================
# 7. 驗證正式世界 ID
# 第一個字元必須為英文小寫。
# 後續允許英文小寫、數字及底線。
# 長度限制為 1～96 個字元。
# ============================================================
func is_valid_world_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var world_id: String = value
	if world_id.is_empty() or world_id.length() > MAX_ID_LENGTH:
		return false
	var first_code: int = world_id.unicode_at(0)
	if first_code < 97 or first_code > 122:
		return false
	for index in range(world_id.length()):
		var code: int = world_id.unicode_at(index)
		var is_lowercase: bool = code >= 97 and code <= 122
		var is_number: bool = code >= 48 and code <= 57
		var is_underscore: bool = code == 95
		if not (is_lowercase or is_number or is_underscore):
			return false
	return true

# ============================================================
# 8. 驗證世界永久資料
# 空字串代表資料有效。
# 只驗證本管理器負責的欄位。
# ============================================================
func get_world_data_error(raw_world: Variant) -> String:
	if typeof(raw_world) != TYPE_DICTIONARY:
		return "world 必須為 Dictionary"
	var world: Dictionary = raw_world
	for field in MANAGED_FIELDS:
		# 保留核心資料處理的舊版相容性。
		if not world.has(field):
			continue
		var raw_entries: Variant = world[field]
		if typeof(raw_entries) != TYPE_DICTIONARY:
			return field + " 必須為 Dictionary"
		var entries: Dictionary = raw_entries
		for raw_id in entries.keys():
			if not is_valid_world_id(raw_id):
				return field + " 包含無效 ID：" + str(raw_id)
			var raw_value: Variant = entries[raw_id]
			if typeof(raw_value) != TYPE_BOOL:
				return field + " 包含非布林狀態：" + str(raw_id)
			if raw_value != true:
				return field + " 包含無效的未完成紀錄：" + str(raw_id)
	return ""

func validate_world_data(raw_world: Variant) -> bool:
	return get_world_data_error(raw_world).is_empty()

# 9. 建立正式還原資料
func build_restored_world_data(raw_world: Variant) -> Dictionary:
	if not validate_world_data(raw_world):
		return {}
	var source: Dictionary = raw_world
	var restored: Dictionary = build_initial_world_data()
	for field in MANAGED_FIELDS:
		if source.has(field):
			var entries: Dictionary = source[field]
			restored[field] = entries.duplicate(true)
	return restored

# 10. 驗證正式存檔編號
func _matches_slot_id(save_data: Dictionary, expected_slot_id: int) -> bool:
	if expected_slot_id < 1 or expected_slot_id > SaveManager.SLOT_COUNT:
		return false
	var raw_id: Variant = save_data.get("slot_id")
	if typeof(raw_id) != TYPE_INT and typeof(raw_id) != TYPE_FLOAT:
		return false
	return float(raw_id) == float(expected_slot_id)

# 11. 全新遊戲與正式讀檔
func _on_slot_created(slot_id: int) -> void:
	_restore_current_slot(slot_id)

func _on_slot_loaded(slot_id: int) -> void:
	_restore_current_slot(slot_id)

# ============================================================
# 12. 正式世界資料還原
# 先清除舊工作階段，再驗證及還原新資料。
# 不允許異常資料被視為正常空白世界。
# ============================================================
func _restore_current_slot(slot_id: int) -> void:
	_reset_runtime_world()
	if not _initialized:
		_restore_fail(slot_id, "管理器尚未初始化")
		return
	if SaveManager.current_slot_id != slot_id:
		_restore_fail(slot_id, "目前存檔工作階段不一致")
		return
	var save_data: Dictionary = SaveManager.get_current_data()
	if not _matches_slot_id(save_data, slot_id):
		_restore_fail(slot_id, "正式存檔編號不一致")
		return
	var raw_world: Variant = save_data.get(WORLD_FIELD)
	var validation_error: String = get_world_data_error(raw_world)
	if not validation_error.is_empty():
		_restore_fail(slot_id, validation_error)
		return
	var restored: Dictionary = build_restored_world_data(raw_world)
	if restored.is_empty():
		_restore_fail(slot_id, "世界永久資料還原失敗")
		return
	_runtime_world = restored
	_loaded_slot_id = slot_id
	_world_data_valid = true
	_log("Slot %02d 世界永久資料還原成功" % slot_id)
	_log("目前已擊敗 Boss：" + str(_runtime_world[BOSS_FIELD].size()))
	_log("目前已開啟捷徑：" + str(_runtime_world[SHORTCUT_FIELD].size()))
	_log("目前已取得唯一性道具：" + str(_runtime_world[UNIQUE_ITEM_FIELD].size()))
	world_restored.emit(slot_id)

# 13. 工作階段查詢
func is_initialized() -> bool:
	return _initialized

func has_active_session() -> bool:
	return (
		_initialized
		and _world_data_valid
		and _loaded_slot_id > 0
		and SaveManager.current_slot_id == _loaded_slot_id
	)

func get_loaded_slot_id() -> int:
	if not has_active_session():
		return 0
	return _loaded_slot_id

func can_save_world() -> bool:
	if not has_active_session():
		return false
	if SaveManager.get_slot_state(_loaded_slot_id) != SaveManager.SlotState.READY:
		return false
	return validate_world_data(_runtime_world)

# ============================================================
# 14. 世界狀態查詢
# 供正式 Boss、捷徑及特殊道具使用。
# ============================================================
func is_boss_defeated(boss_id: String) -> bool:
	return _has_world_state(BOSS_FIELD, boss_id)

func is_shortcut_opened(shortcut_id: String) -> bool:
	return _has_world_state(SHORTCUT_FIELD, shortcut_id)

func is_unique_item_collected(item_id: String) -> bool:
	return _has_world_state(UNIQUE_ITEM_FIELD, item_id)

func _has_world_state(category: String, world_id: String) -> bool:
	if not has_active_session():
		return false
	if not MANAGED_FIELDS.has(category):
		return false
	if not is_valid_world_id(world_id):
		return false
	var entries: Dictionary = _runtime_world[category]
	return entries.get(world_id, false) == true

# ============================================================
# 15. 登記世界永久狀態
# 只修改運行時資料，不直接寫入 JSON。
# 重複登記相同 ID 不再次發送訊號。
# ============================================================
func mark_boss_defeated(boss_id: String) -> bool:
	return _record_world_state(BOSS_FIELD, boss_id)

func mark_shortcut_opened(shortcut_id: String) -> bool:
	return _record_world_state(SHORTCUT_FIELD, shortcut_id)

func mark_unique_item_collected(item_id: String) -> bool:
	return _record_world_state(UNIQUE_ITEM_FIELD, item_id)

func _record_world_state(category: String, world_id: String) -> bool:
	if not can_save_world():
		return _fail("目前沒有可用的正式世界工作階段")
	if not MANAGED_FIELDS.has(category):
		return _fail("未知世界狀態類型：" + category)
	if not is_valid_world_id(world_id):
		return _fail("無效世界狀態 ID：" + world_id)
	var entries: Dictionary = _runtime_world[category]
	if entries.has(world_id):
		return true
	entries[world_id] = true
	_runtime_world[category] = entries
	_log("Slot %02d 登記世界狀態：%s / %s" % [_loaded_slot_id, category, world_id])
	_log("本次世界狀態變更尚未寫入正式 JSON")
	world_state_changed.emit(_loaded_slot_id, category, world_id)
	return true

# 16. 取得運行時世界資料深層副本
func capture_runtime_world() -> Dictionary:
	if not has_active_session():
		return {}
	return _runtime_world.duplicate(true)

# ============================================================
# 17. 建立世界候選資料
# 保留劇情、任務、NPC 及其他未知世界欄位。
# 不允許已永久保存的紀錄遭到移除。
# ============================================================
func build_merged_world_data(raw_existing: Variant, raw_runtime: Variant) -> Dictionary:
	if not validate_world_data(raw_existing):
		return {}
	if not validate_world_data(raw_runtime):
		return {}
	var existing: Dictionary = raw_existing
	var runtime: Dictionary = raw_runtime
	var merged: Dictionary = existing.duplicate(true)
	for field in MANAGED_FIELDS:
		if not runtime.has(field):
			return {}
		var old_entries: Dictionary = existing.get(field, {})
		var new_entries: Dictionary = runtime[field]
		for world_id in old_entries.keys():
			if not new_entries.has(world_id):
				return {}
			if new_entries[world_id] != true:
				return {}
		merged[field] = new_entries.duplicate(true)
	return merged

# ============================================================
# 18. 加入正式存檔候選資料
# 由 CheckpointManager 統一呼叫。
# 不自行執行第二次 JSON 寫入。
# ============================================================
func append_world_to_candidate(candidate: Dictionary) -> bool:
	if not can_save_world():
		return _fail("世界永久資料工作階段尚未準備完成")
	if not _matches_slot_id(candidate, _loaded_slot_id):
		return _fail("世界候選資料存檔編號不一致")
	var current_data: Dictionary = SaveManager.get_current_data()
	if not _matches_slot_id(current_data, _loaded_slot_id):
		return _fail("目前正式存檔編號異常")
	var saved_world: Variant = current_data.get(WORLD_FIELD)
	var candidate_world: Variant = candidate.get(WORLD_FIELD)
	if not validate_world_data(saved_world):
		return _fail("原本正式世界資料異常")
	if not validate_world_data(candidate_world):
		return _fail("候選世界資料異常")
	var saved_managed: Dictionary = build_restored_world_data(saved_world)
	var candidate_managed: Dictionary = build_restored_world_data(candidate_world)
	if saved_managed != candidate_managed:
		return _fail("候選資料包含非預期的世界狀態變更")
	var merged: Dictionary = build_merged_world_data(candidate_world, _runtime_world)
	if merged.is_empty():
		return _fail("世界永久候選資料整合失敗")
	candidate[WORLD_FIELD] = merged
	_log("Slot %02d 世界永久資料已準備，等待正式寫入" % _loaded_slot_id)
	return true

# ============================================================
# 19. V2：中央工作階段結束訊號
#
# SaveManager 已先將 current_slot_id 設為 0。
# 因此此處不可使用 has_active_session() 作為清理條件。
#
# 使用訊號提供的 slot_id 記錄實際結束的存檔。
# 即使先前世界資料還原失敗，也要完成清理。
# ============================================================
func _on_session_closed(slot_id: int) -> void:
	_reset_runtime_world()
	_log("Slot %02d 世界工作階段已結束" % slot_id)
	_log("世界永久運行時資料已清除")
	_log("已完成中央工作階段清理")

# 20. 保留 V1 原有手動清理接口
# 正式離場流程應使用 SaveManager.close_session()。
func clear_session() -> void:
	var previous_slot_id: int = _loaded_slot_id
	_reset_runtime_world()
	if previous_slot_id > 0:
		_log("Slot %02d 世界工作階段已結束" % previous_slot_id)
		_log("世界永久運行時資料已清除")

# 21. 統一重設運行時資料
func _reset_runtime_world() -> void:
	_loaded_slot_id = 0
	_world_data_valid = false
	_runtime_world = build_initial_world_data()

# 22. 統一資料還原失敗處理
func _restore_fail(slot_id: int, reason: String) -> void:
	_reset_runtime_world()
	push_error("【WorldProgress】Slot %02d 世界資料還原失敗：%s" % [slot_id, reason])
	world_restore_failed.emit(slot_id, reason)

# 23. 統一操作失敗處理
func _fail(reason: String) -> bool:
	push_warning("【WorldProgress】世界資料操作失敗：" + reason)
	return false

# 24. 統一除錯輸出
func _log(message: String) -> void:
	if debug_log:
		print("【WorldProgress】" + message)

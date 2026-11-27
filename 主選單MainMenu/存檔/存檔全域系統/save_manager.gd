extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# SaveManager V3｜四格存檔核心管理器
# Godot 4.5.1
# Autoload：SaveManager
# STEP 10.7.7-C
# ============================================================
# 主要職責：
# 1. 建立四格獨立存檔。
# 2. 建立及讀取正式遊戲紀錄。
# 3. 驗證 JSON 存檔格式。
# 4. 提供存檔摘要。
# 5. 使用暫存檔及備份保護正式資料。
# 6. 防止損壞資料被認定為空白存檔。
# 7. V3：正式結束存檔工作階段。
#
# 不負責地圖切換、玩家定位或死亡重生。
# 結束工作階段不會寫入或刪除任何存檔。
# ============================================================

# 1. 對外訊號
signal slot_created(slot_id: int)
signal slot_loaded(slot_id: int)
signal slot_saved(slot_id: int)
signal session_closed(slot_id: int)
signal operation_failed(operation: String, slot_id: int, reason: String)

# 2. 基本常數
const SLOT_COUNT: int = 4
const SCHEMA_VERSION: int = 1
const SAVE_DIRECTORY: String = "user://saves"
const MAX_SAVE_BYTES: int = 5 * 1024 * 1024

# 3. 全新遊戲起點
const INITIAL_MAP_ID: String = "first_land_sakura_garden"
const INITIAL_EASEL_ID: String = "easel_start_01"
const INITIAL_MAP_DISPLAY_NAME: String = "最初之地・櫻花庭園"

# 4. 存檔狀態
enum SlotState {
	EMPTY,
	READY,
	RECOVERABLE,
	DAMAGED
}

# 5. 除錯設定
@export_group("除錯設定")
@export var debug_log: bool = true

# 6. 正式存檔工作階段
# 0 代表目前沒有正式使用中的存檔。
var current_slot_id: int = 0
var _current_data: Dictionary = {}

# ============================================================
# 7. 初始化
# 只確認存檔目錄及既有資料，不自動建立新存檔。
# ============================================================
func _ready() -> void:
	if not _ensure_directory():
		push_error("【SaveManager】無法建立存檔資料夾")
		return
	if debug_log:
		print("========== SaveManager ==========")
		print("【SaveManager】V3 四格存檔管理器初始化完成")
		print("【SaveManager】存檔目錄：", ProjectSettings.globalize_path(SAVE_DIRECTORY))
		for slot_id in range(1, SLOT_COUNT + 1):
			print("【SaveManager】Slot %02d：%s" % [
				slot_id, _state_to_text(get_slot_state(slot_id))
			])
		print("=================================")

# 8. 確保存檔資料夾存在
func _ensure_directory() -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(SAVE_DIRECTORY)
	return DirAccess.make_dir_recursive_absolute(absolute_path) == OK

# 9. 驗證存檔編號
func _is_valid_slot_id(slot_id: int) -> bool:
	return slot_id >= 1 and slot_id <= SLOT_COUNT

# 10. 取得正式、備份及暫存檔路徑
func _get_slot_path(slot_id: int) -> String:
	return "%s/slot_%02d.json" % [SAVE_DIRECTORY, slot_id]

func _get_backup_path(slot_id: int) -> String:
	return _get_slot_path(slot_id) + ".bak"

func _get_temp_path(slot_id: int) -> String:
	return _get_slot_path(slot_id) + ".tmp"

# ============================================================
# 11. 查詢存檔狀態
# 優先使用主檔，再檢查備份。
# 三種檔案均不存在時，才視為空白欄位。
# ============================================================
func get_slot_state(slot_id: int) -> SlotState:
	if not _is_valid_slot_id(slot_id):
		return SlotState.DAMAGED
	var main_path: String = _get_slot_path(slot_id)
	var backup_path: String = _get_backup_path(slot_id)
	var temp_path: String = _get_temp_path(slot_id)
	var has_main: bool = FileAccess.file_exists(main_path)
	var has_backup: bool = FileAccess.file_exists(backup_path)
	var has_temp: bool = FileAccess.file_exists(temp_path)
	if not has_main and not has_backup and not has_temp:
		return SlotState.EMPTY
	if has_main:
		var main_data: Dictionary = _read_slot_file(main_path, slot_id)
		if not main_data.is_empty():
			return SlotState.READY
	if has_backup:
		var backup_data: Dictionary = _read_slot_file(backup_path, slot_id)
		if not backup_data.is_empty():
			return SlotState.RECOVERABLE
	return SlotState.DAMAGED

# ============================================================
# 12. 建立全新遊戲
# ============================================================
func create_new_game(slot_id: int) -> bool:
	if INITIAL_MAP_ID.is_empty() or INITIAL_EASEL_ID.is_empty():
		return _fail("建立新遊戲", slot_id, "初始地圖或畫架 ID 尚未設定")
	return create_slot(
		slot_id,
		INITIAL_MAP_ID,
		INITIAL_EASEL_ID,
		INITIAL_MAP_DISPLAY_NAME
	)

# ============================================================
# 13. 建立指定存檔
# 禁止覆蓋既有存檔、備份或異常資料。
# ============================================================
func create_slot(
	slot_id: int,
	map_id: String,
	easel_id: String,
	map_display_name: String
) -> bool:
	if not _is_valid_slot_id(slot_id):
		return _fail("建立存檔", slot_id, "存檔編號超出 1～4")
	if map_id.strip_edges().is_empty() or easel_id.strip_edges().is_empty():
		return _fail("建立存檔", slot_id, "地圖或畫架 ID 不可為空")
	if get_slot_state(slot_id) != SlotState.EMPTY:
		return _fail("建立存檔", slot_id, "欄位已有資料，禁止覆蓋")
	var new_data: Dictionary = _create_initial_data(
		slot_id, map_id, easel_id, map_display_name
	)
	if not _write_slot(slot_id, new_data, true):
		return false

	# 成功寫入磁碟後才建立工作階段。
	current_slot_id = slot_id
	_current_data = new_data.duplicate(true)
	slot_created.emit(slot_id)
	if debug_log:
		print("【SaveManager】成功建立 Slot %02d" % slot_id)
	return true

# ============================================================
# 14. 建立初始存檔結構
# 維持 Schema Version 1。
# 玩家初始數值由 PlayerProgress 管理。
# ============================================================
func _create_initial_data(
	slot_id: int,
	map_id: String,
	easel_id: String,
	map_display_name: String
) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	return {
		"schema_version": SCHEMA_VERSION,
		"slot_id": slot_id,
		"meta": {
			"created_at_unix": now,
			"updated_at_unix": now,
			"play_seconds": 0.0,
			"map_display_name": map_display_name
		},
		"checkpoint": {
			"map_id": map_id,
			"easel_id": easel_id
		},
		"player": {
			"stats": {},
			"inventory": {},
			"equipment": {},
			"unlocked_skills": []
		},
		"world": {
			"defeated_bosses": {},
			"opened_shortcuts": {},
			"collected_unique_items": {},
			"quest_states": {},
			"npc_flags": {}
		}
	}

# ============================================================
# 15. 正式載入存檔
# 備份可供讀取，但不會自動覆蓋主檔。
# ============================================================
func load_slot(slot_id: int) -> bool:
	if not _is_valid_slot_id(slot_id):
		return _fail("讀取存檔", slot_id, "存檔編號不正確")
	var state: SlotState = get_slot_state(slot_id)
	if state != SlotState.READY and state != SlotState.RECOVERABLE:
		return _fail("讀取存檔", slot_id, "沒有可使用的有效存檔")
	var source_path: String = _get_slot_path(slot_id)
	if state == SlotState.RECOVERABLE:
		source_path = _get_backup_path(slot_id)
		push_warning("【SaveManager】Slot %02d 暫時從備份讀取" % slot_id)
	var loaded_data: Dictionary = _read_slot_file(source_path, slot_id)
	if loaded_data.is_empty():
		return _fail("讀取存檔", slot_id, "資料讀取或驗證失敗")

	current_slot_id = slot_id
	_current_data = loaded_data.duplicate(true)
	slot_loaded.emit(slot_id)
	return true

# 16. 取得目前存檔深層副本
func get_current_data() -> Dictionary:
	return _current_data.duplicate(true)

# ============================================================
# 17. 更新目前正式存檔
# 只允許正常且已載入的存檔執行寫入。
# ============================================================
func save_current_data(updated_data: Dictionary) -> bool:
	if current_slot_id == 0:
		return _fail("更新存檔", 0, "目前尚未載入任何存檔")
	if get_slot_state(current_slot_id) != SlotState.READY:
		return _fail("更新存檔", current_slot_id, "目前存檔無法安全更新")
	var candidate: Dictionary = updated_data.duplicate(true)
	if not _validate_slot_data(candidate, current_slot_id):
		return _fail("更新存檔", current_slot_id, "資料結構驗證失敗")
	var meta: Dictionary = candidate["meta"]
	meta["updated_at_unix"] = int(Time.get_unix_time_from_system())
	candidate["meta"] = meta
	if not _write_slot(current_slot_id, candidate, false):
		return false
	_current_data = candidate.duplicate(true)
	slot_saved.emit(current_slot_id)
	return true

# ============================================================
# 18. 提供存檔選擇介面摘要
# ============================================================
func get_slot_summary(slot_id: int) -> Dictionary:
	var state: SlotState = get_slot_state(slot_id)
	var summary: Dictionary = {
		"slot_id": slot_id,
		"state": state
	}
	if state != SlotState.READY and state != SlotState.RECOVERABLE:
		return summary
	var source_path: String = _get_slot_path(slot_id)
	if state == SlotState.RECOVERABLE:
		source_path = _get_backup_path(slot_id)
	var data: Dictionary = _read_slot_file(source_path, slot_id)
	if data.is_empty():
		return {
			"slot_id": slot_id,
			"state": SlotState.DAMAGED
		}
	var meta: Dictionary = data["meta"]
	var checkpoint: Dictionary = data["checkpoint"]
	summary["map_name"] = meta["map_display_name"]
	summary["play_seconds"] = meta["play_seconds"]
	summary["updated_at_unix"] = meta["updated_at_unix"]
	summary["map_id"] = checkpoint["map_id"]
	summary["easel_id"] = checkpoint["easel_id"]
	return summary

# ============================================================
# 19. 讀取及解析 JSON
# 讀取失敗時不修改任何原始檔案。
# ============================================================
func _read_slot_file(path: String, expected_slot_id: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var file_size: int = file.get_length()
	if file_size <= 0 or file_size > MAX_SAVE_BYTES:
		file = null
		return {}
	var content: String = file.get_as_text()
	file = null
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parser.data
	if not _validate_slot_data(data, expected_slot_id):
		return {}
	return data

# 20. 相容 JSON 整數型 float
func _is_json_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

# ============================================================
# 21. 驗證正式存檔結構
# ============================================================
func _validate_slot_data(data: Dictionary, expected_slot_id: int) -> bool:
	# A. 版本及存檔編號。
	if not data.has("schema_version") or not data.has("slot_id"):
		return false
	if not _is_json_number(data["schema_version"]):
		return false
	if not _is_json_number(data["slot_id"]):
		return false
	if float(data["schema_version"]) != float(SCHEMA_VERSION):
		return false
	if float(data["slot_id"]) != float(expected_slot_id):
		return false

	# B. 主要資料區塊。
	for key in ["meta", "checkpoint", "player", "world"]:
		if not data.has(key):
			return false
		if typeof(data[key]) != TYPE_DICTIONARY:
			return false

	# C. 時間及地圖摘要。
	var meta: Dictionary = data["meta"]
	for key in ["created_at_unix", "updated_at_unix", "play_seconds"]:
		if not meta.has(key):
			return false
		if not _is_json_number(meta[key]):
			return false
		if float(meta[key]) < 0.0:
			return false
	if not meta.has("map_display_name"):
		return false
	if typeof(meta["map_display_name"]) != TYPE_STRING:
		return false

	# D. 正式檢查點。
	var checkpoint: Dictionary = data["checkpoint"]
	for key in ["map_id", "easel_id"]:
		if not checkpoint.has(key):
			return false
		if typeof(checkpoint[key]) != TYPE_STRING:
			return false
		if String(checkpoint[key]).strip_edges().is_empty():
			return false

	# E. 玩家資料區塊。
	var player: Dictionary = data["player"]
	for key in ["stats", "inventory", "equipment"]:
		if not player.has(key):
			return false
		if typeof(player[key]) != TYPE_DICTIONARY:
			return false
	if not player.has("unlocked_skills"):
		return false
	if typeof(player["unlocked_skills"]) != TYPE_ARRAY:
		return false

	# F. 世界永久資料區塊。
	var world: Dictionary = data["world"]
	for key in [
		"defeated_bosses",
		"opened_shortcuts",
		"collected_unique_items",
		"quest_states",
		"npc_flags"
	]:
		if not world.has(key):
			return false
		if typeof(world[key]) != TYPE_DICTIONARY:
			return false
	return true

# ============================================================
# 22. 正式磁碟寫入
#
# 流程：
# 驗證 → 寫入 .tmp → 重新讀取驗證
# → 建立 .bak → 取代正式 JSON。
#
# 不自動刪除未處理的暫存檔。
# ============================================================
func _write_slot(
	slot_id: int,
	data: Dictionary,
	new_file: bool
) -> bool:
	# A. 基礎驗證。
	if not _is_valid_slot_id(slot_id):
		return _fail("寫入存檔", slot_id, "存檔編號無效")
	if not _validate_slot_data(data, slot_id):
		return _fail("寫入存檔", slot_id, "資料驗證失敗")
	if not _ensure_directory():
		return _fail("寫入存檔", slot_id, "無法建立存檔目錄")

	var main_path: String = _get_slot_path(slot_id)
	var backup_path: String = _get_backup_path(slot_id)
	var temp_path: String = _get_temp_path(slot_id)

	# B. 保護殘留暫存檔。
	if FileAccess.file_exists(temp_path):
		return _fail("寫入存檔", slot_id, "存在尚未處理的暫存檔")

	# C. 區分新建及更新。
	if new_file:
		if FileAccess.file_exists(main_path) or FileAccess.file_exists(backup_path):
			return _fail("寫入存檔", slot_id, "欄位已有檔案，禁止覆蓋")
	else:
		if get_slot_state(slot_id) != SlotState.READY:
			return _fail("寫入存檔", slot_id, "既有存檔不是可安全更新的狀態")

	# D. 寫入暫存檔。
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("寫入存檔", slot_id, "無法開啟暫存檔")
	var json_text: String = JSON.stringify(data, "\t")
	file.store_string(json_text)
	file.flush()
	var write_error: Error = file.get_error()
	file = null
	if write_error != OK:
		return _fail("寫入存檔", slot_id, "暫存檔寫入失敗")

	# E. 重新驗證暫存檔。
	var verified_data: Dictionary = _read_slot_file(temp_path, slot_id)
	if verified_data.is_empty():
		return _fail("寫入存檔", slot_id, "暫存檔資料驗證失敗")
	var read_back_text: String = FileAccess.get_file_as_string(temp_path)
	if read_back_text != json_text:
		return _fail("寫入存檔", slot_id, "暫存檔內容比對失敗")

	# F. 備份原本的正式存檔。
	if not new_file:
		var backup_error: Error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(main_path),
			ProjectSettings.globalize_path(backup_path)
		)
		if backup_error != OK:
			return _fail("寫入存檔", slot_id, "舊存檔備份失敗")

	# G. 正式檔案替換。
	var rename_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(main_path)
	)
	if rename_error != OK:
		return _fail("寫入存檔", slot_id, "無法完成正式檔案替換")
	if debug_log:
		print("【SaveManager】存檔寫入成功：", slot_id)
	return true

# 23. 統一錯誤處理
func _fail(operation: String, slot_id: int, reason: String) -> bool:
	var message: String = "【SaveManager】%s失敗｜Slot %02d｜%s" % [
		operation, slot_id, reason
	]
	push_error(message)
	operation_failed.emit(operation, slot_id, reason)
	return false

# 24. 存檔狀態文字
func _state_to_text(state: SlotState) -> String:
	match state:
		SlotState.EMPTY:
			return "空白"
		SlotState.READY:
			return "正常"
		SlotState.RECOVERABLE:
			return "可從備份復原"
		SlotState.DAMAGED:
			return "損壞或版本不相容"
	return "未知狀態"

# ============================================================
# 25. V3：正式結束存檔工作階段
#
# 只清除記憶體，不修改任何磁碟資料。
# 先解除正式存檔資格，再通知其他管理器。
# ============================================================
func close_session() -> void:
	var previous_slot_id: int = current_slot_id
	current_slot_id = 0
	_current_data.clear()
	if previous_slot_id <= 0:
		return

	session_closed.emit(previous_slot_id)
	if debug_log:
		print("【SaveManager】Slot %02d 工作階段已結束" % previous_slot_id)
		print("【SaveManager】目前存檔編號：", current_slot_id)
		print("【SaveManager】本次結束工作階段未寫入 JSON")

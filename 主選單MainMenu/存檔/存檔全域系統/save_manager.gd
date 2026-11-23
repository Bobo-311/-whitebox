
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# SaveManager V1｜四格存檔核心管理器
#
# Godot 4.5.1
#
# 目前負責：
# 1. 管理四個獨立存檔欄位
# 2. 建立新存檔資料
# 3. 讀取與驗證存檔
# 4. 更新目前使用中的存檔
# 5. 產生存檔列表需要的摘要
# 6. 暫存檔寫入及正式檔案替換
# 7. 保留有效存檔的上一版本備份
# 8. 防止意外覆蓋損壞或不相容的存檔
#
# 暫時不負責：
# - 玩家節點資料收集
# - 地圖切換
# - 死亡重生
# - 普通敵人生成
# - 畫架互動
# - 清除存檔 UI 連接
#
# 注意：
# 本腳本使用 Autoload，名稱為 SaveManager。
# 不需要另外宣告 class_name SaveManager。
# ============================================================


# ============================================================
# 1. 對外訊號
#
# 其他 UI 可以透過這些訊號，
# 得知存檔資料是否發生變化。
# ============================================================

signal slot_created(slot_id: int)
signal slot_loaded(slot_id: int)
signal slot_saved(slot_id: int)

signal operation_failed(
	operation: String,
	slot_id: int,
	reason: String
)


# ============================================================
# 2. 核心常數
# ============================================================

## 存檔欄位數量
const SLOT_COUNT: int = 4

## 目前支援的資料格式版本
##
## 未來修改存檔資料結構時，
## 必須配合資料遷移程序更新版本。
const SCHEMA_VERSION: int = 1

## 存檔資料夾
const SAVE_DIRECTORY: String = "user://saves"


# ============================================================
# 3. 存檔欄位狀態
# ============================================================

enum SlotState {

	## 沒有任何存檔資料
	EMPTY,

	## 存檔正常
	READY,

	## 主要檔案損壞，但有效備份仍存在
	RECOVERABLE,

	## 資料無法正常讀取或版本不相容
	DAMAGED
}


# ============================================================
# 4. 除錯設定
# ============================================================

@export_group("除錯設定")

## 開發期間顯示初始化及槽位狀態
@export var debug_log: bool = true


# ============================================================
# 5. 目前使用中的存檔
# ============================================================

## 0 代表尚未載入任何存檔
var current_slot_id: int = 0

## 目前存檔的記憶體資料
##
## 不直接開放外部修改。
## 外部系統應透過 get_current_data()
## 取得副本，再交由 save_current_data() 儲存。
var _current_data: Dictionary = {}

## 存檔目錄是否成功建立
var _directory_ready: bool = false


# ============================================================
# 6. 初始化
# ============================================================

func _ready() -> void:

	_directory_ready = _ensure_directory()

	if not _directory_ready:

		push_error(
			"【SaveManager】存檔資料夾初始化失敗"
		)

		return

	if debug_log:

		print("========== SaveManager ==========")

		print(
			"【SaveManager】存檔目錄：",
			ProjectSettings.globalize_path(
				SAVE_DIRECTORY
			)
		)

		for slot_id in range(1, SLOT_COUNT + 1):

			print(
				"【SaveManager】Slot %02d：%s"
				% [
					slot_id,
					_state_to_text(
						get_slot_state(slot_id)
					)
				]
			)

		print("=================================")


# ============================================================
# 7. 確保存檔資料夾存在
#
# 使用作業系統實際路徑建立資料夾，
# 不依賴 Godot 編輯器中的 res:// 目錄。
# ============================================================

func _ensure_directory() -> bool:

	var absolute_directory: String = (
		ProjectSettings.globalize_path(
			SAVE_DIRECTORY
		)
	)

	var result: Error = (
		DirAccess.make_dir_recursive_absolute(
			absolute_directory
		)
	)

	return result == OK


# ============================================================
# 8. 檢查存檔編號
# ============================================================

func _is_valid_slot_id(slot_id: int) -> bool:

	return (
		slot_id >= 1
		and slot_id <= SLOT_COUNT
	)


# ============================================================
# 9. 產生各個欄位的檔案路徑
# ============================================================

func _get_slot_path(slot_id: int) -> String:

	return (
		"%s/slot_%02d.json"
		% [SAVE_DIRECTORY, slot_id]
	)


func _get_backup_path(slot_id: int) -> String:

	return _get_slot_path(slot_id) + ".bak"


func _get_temp_path(slot_id: int) -> String:

	return _get_slot_path(slot_id) + ".tmp"


# ============================================================
# 10. 取得存檔欄位狀態
#
# 優先檢查主要存檔。
# 如果主要存檔損壞，再檢查備份。
#
# 不可以只依照「檔案是否存在」，
# 就判定一份存檔能正常使用。
# ============================================================

func get_slot_state(slot_id: int) -> SlotState:

	if not _is_valid_slot_id(slot_id):

		return SlotState.DAMAGED

	var slot_path: String = (
		_get_slot_path(slot_id)
	)

	var backup_path: String = (
		_get_backup_path(slot_id)
	)

	var has_main: bool = (
		FileAccess.file_exists(slot_path)
	)

	var has_backup: bool = (
		FileAccess.file_exists(backup_path)
	)

	# 沒有主要檔案也沒有備份
	if not has_main and not has_backup:

		return SlotState.EMPTY

	# 檢查主要檔案是否有效
	if has_main:

		var main_data: Dictionary = (
			_read_slot_file(
				slot_path,
				slot_id
			)
		)

		if not main_data.is_empty():

			return SlotState.READY

	# 主要檔案無效時檢查備份
	if has_backup:

		var backup_data: Dictionary = (
			_read_slot_file(
				backup_path,
				slot_id
			)
		)

		if not backup_data.is_empty():

			return SlotState.RECOVERABLE

	return SlotState.DAMAGED


# ============================================================
# 11. 建立新存檔
#
# 只接受空白欄位。
# 不會覆蓋任何既有存檔或備份。
#
# map_id：
# 地圖的穩定識別碼。
#
# easel_id：
# 初始畫架的穩定識別碼。
#
# map_display_name：
# 用於存檔選擇介面的顯示名稱。
# ============================================================

func create_slot(
	slot_id: int,
	map_id: String,
	easel_id: String,
	map_display_name: String
) -> bool:

	if not _is_valid_slot_id(slot_id):

		return _fail(
			"建立存檔",
			slot_id,
			"存檔編號超出範圍"
		)

	if map_id.is_empty() or easel_id.is_empty():

		return _fail(
			"建立存檔",
			slot_id,
			"初始地圖或畫架 ID 不可為空"
		)

	if get_slot_state(slot_id) != SlotState.EMPTY:

		return _fail(
			"建立存檔",
			slot_id,
			"欄位已有資料，禁止覆蓋"
		)

	# 建立符合目前版本的初始資料
	var new_data: Dictionary = (
		_create_initial_data(
			slot_id,
			map_id,
			easel_id,
			map_display_name
		)
	)

	if not _write_slot(
		slot_id,
		new_data
	):

		return false

	# 寫入成功後才切換目前存檔
	current_slot_id = slot_id

	_current_data = new_data.duplicate(true)

	slot_created.emit(slot_id)

	return true


# ============================================================
# 12. 建立初始存檔資料結構
#
# 所有新存檔必須使用相同資料結構。
#
# 玩家及世界資料先預留欄位，
# 未來由對應的系統填入真正數值。
#
# 注意：
# 不在這裡猜測阿尼的 HP、墨水或裝備數值。
# ============================================================

func _create_initial_data(
	slot_id: int,
	map_id: String,
	easel_id: String,
	map_display_name: String
) -> Dictionary:

	var now: int = int(
		Time.get_unix_time_from_system()
	)

	return {

		"schema_version": SCHEMA_VERSION,

		"slot_id": slot_id,

		# ----------------------------------------------------
		# 存檔列表與時間資訊
		# ----------------------------------------------------

		"meta": {

			"created_at_unix": now,

			"updated_at_unix": now,

			"play_seconds": 0.0,

			"map_display_name": map_display_name
		},

		# ----------------------------------------------------
		# 最後使用的畫架
		#
		# 死亡後要回到的位置，
		# 由 map_id + easel_id 共同決定。
		# ----------------------------------------------------

		"checkpoint": {

			"map_id": map_id,

			"easel_id": easel_id
		},

		# ----------------------------------------------------
		# 玩家永久進度
		#
		# 後續接入角色數值、背包及技能系統。
		# ----------------------------------------------------

		"player": {

			"stats": {},

			"inventory": {},

			"equipment": {},

			"unlocked_skills": []
		},

		# ----------------------------------------------------
		# 世界永久進度
		#
		# 使用 Dictionary 儲存穩定 ID 與狀態。
		# ----------------------------------------------------

		"world": {

			"defeated_bosses": {},

			"opened_shortcuts": {},

			"collected_unique_items": {},

			"quest_states": {},

			"npc_flags": {}
		}
	}


# ============================================================
# 13. 載入指定存檔
#
# 優先載入主要檔案。
#
# 如果主要檔案損壞而備份有效，
# 可以將備份讀入記憶體。
#
# 注意：
# 目前不自動覆寫損壞的主要檔案。
# 正式的備份還原操作將另外製作。
# ============================================================

func load_slot(slot_id: int) -> bool:

	if not _is_valid_slot_id(slot_id):

		return _fail(
			"讀取存檔",
			slot_id,
			"存檔編號超出範圍"
		)

	var state: SlotState = (
		get_slot_state(slot_id)
	)

	if (
		state == SlotState.EMPTY
		or state == SlotState.DAMAGED
	):

		return _fail(
			"讀取存檔",
			slot_id,
			"欄位沒有可讀取的有效資料"
		)

	var source_path: String = (
		_get_slot_path(slot_id)
	)

	if state == SlotState.RECOVERABLE:

		source_path = _get_backup_path(slot_id)

		push_warning(
			"【SaveManager】主要存檔無效，"
			+ "暫時從備份讀取"
		)

	var loaded_data: Dictionary = (
		_read_slot_file(
			source_path,
			slot_id
		)
	)

	if loaded_data.is_empty():

		return _fail(
			"讀取存檔",
			slot_id,
			"資料驗證失敗"
		)

	current_slot_id = slot_id

	_current_data = loaded_data.duplicate(true)

	slot_loaded.emit(slot_id)

	return true


# ============================================================
# 14. 取得目前存檔資料
#
# 回傳深層副本，
# 避免外部程式意外直接修改記憶體原件。
# ============================================================

func get_current_data() -> Dictionary:

	return _current_data.duplicate(true)


# ============================================================
# 15. 更新目前存檔
#
# 外部的 PlayerData、WorldState 等系統，
# 未來會把更新後的資料交給這個函式。
#
# 寫入成功後才更新目前記憶體資料。
# ============================================================

func save_current_data(
	updated_data: Dictionary
) -> bool:

	if current_slot_id == 0:

		return _fail(
			"更新存檔",
			0,
			"尚未選擇存檔欄位"
		)

	var candidate: Dictionary = (
		updated_data.duplicate(true)
	)

	if not _validate_slot_data(
		candidate,
		current_slot_id
	):

		return _fail(
			"更新存檔",
			current_slot_id,
			"資料結構或版本不正確"
		)

	# 更新保存時間
	var meta: Dictionary = candidate["meta"]

	meta["updated_at_unix"] = int(
		Time.get_unix_time_from_system()
	)

	candidate["meta"] = meta

	# 寫入成功後才更新目前資料
	if not _write_slot(
		current_slot_id,
		candidate
	):

		return false

	_current_data = candidate.duplicate(true)

	slot_saved.emit(current_slot_id)

	return true


# ============================================================
# 16. 取得存檔列表摘要
#
# 讓夢境紀錄 UI 只取得需要顯示的資訊。
# 不需要將整份玩家背包或世界資料傳給 UI。
# ============================================================

func get_slot_summary(slot_id: int) -> Dictionary:

	var state: SlotState = (
		get_slot_state(slot_id)
	)

	var summary: Dictionary = {

		"slot_id": slot_id,

		"state": state
	}

	if (
		state != SlotState.READY
		and state != SlotState.RECOVERABLE
	):

		return summary

	var path: String = _get_slot_path(slot_id)

	if state == SlotState.RECOVERABLE:

		path = _get_backup_path(slot_id)

	var data: Dictionary = (
		_read_slot_file(
			path,
			slot_id
		)
	)

	if data.is_empty():

		return summary

	var meta: Dictionary = data["meta"]

	var checkpoint: Dictionary = (
		data["checkpoint"]
	)

	summary["map_name"] = meta.get(
		"map_display_name",
		"未知地區"
	)

	summary["play_seconds"] = meta.get(
		"play_seconds",
		0.0
	)

	summary["updated_at_unix"] = meta.get(
		"updated_at_unix",
		0
	)

	summary["map_id"] = checkpoint.get(
		"map_id",
		""
	)

	summary["easel_id"] = checkpoint.get(
		"easel_id",
		""
	)

	return summary


# ============================================================
# 17. 讀取及驗證 JSON 檔案
#
# 任何讀取失敗、JSON 格式錯誤，
# 或版本不相容的資料都回傳空 Dictionary。
#
# 不會在此自動刪除或修改檔案。
# ============================================================

func _read_slot_file(
	path: String,
	expected_slot_id: int
) -> Dictionary:

	if not FileAccess.file_exists(path):

		return {}

	var file: FileAccess = FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:

		return {}

	var content: String = file.get_as_text()

	file = null

	if content.is_empty():

		return {}

	var parser := JSON.new()

	if parser.parse(content) != OK:

		return {}

	if typeof(parser.data) != TYPE_DICTIONARY:

		return {}

	var data: Dictionary = parser.data

	if not _validate_slot_data(
		data,
		expected_slot_id
	):

		return {}

	return data


# ============================================================
# 18. 驗證存檔資料結構
#
# 第一版驗證：
# - 存檔格式版本
# - 存檔欄位編號
# - 主要資料區塊
# - 畫架 ID 是否存在
#
# 未來加入具體玩家資料後，
# 再加入更詳細的欄位與型別驗證。
# ============================================================

func _validate_slot_data(
	data: Dictionary,
	expected_slot_id: int
) -> bool:

	if not data.has("schema_version"):
		return false

	if not data.has("slot_id"):
		return false

	if int(data["schema_version"]) != SCHEMA_VERSION:
		return false

	if int(data["slot_id"]) != expected_slot_id:
		return false

	for required_key in [
		"meta",
		"checkpoint",
		"player",
		"world"
	]:

		if not data.has(required_key):
			return false

		if typeof(data[required_key]) != TYPE_DICTIONARY:
			return false

	var checkpoint: Dictionary = (
		data["checkpoint"]
	)

	if not checkpoint.has("map_id"):
		return false

	if not checkpoint.has("easel_id"):
		return false

	if typeof(checkpoint["map_id"]) != TYPE_STRING:
		return false

	if typeof(checkpoint["easel_id"]) != TYPE_STRING:
		return false

	if String(checkpoint["map_id"]).is_empty():
		return false

	if String(checkpoint["easel_id"]).is_empty():
		return false

	return true


# ============================================================
# 19. 安全寫入存檔
#
# 寫入流程：
#
# 1. 確保資料夾存在
# 2. 將資料寫入 .tmp 暫存檔
# 3. 重新讀取並驗證暫存檔
# 4. 如果舊存檔有效，複製為 .bak 備份
# 5. 將暫存檔移動為正式存檔
#
# 如果主要存檔已損壞，
# 不允許直接覆蓋，以免破壞復原機會。
#
# 注意：
# 此流程可降低不完整寫入的風險，
# 但不能保證對所有硬體故障完全免疫。
# ============================================================

func _write_slot(
	slot_id: int,
	data: Dictionary
) -> bool:

	if not _validate_slot_data(
		data,
		slot_id
	):

		return _fail(
			"寫入存檔",
			slot_id,
			"資料驗證未通過"
		)

	if not _ensure_directory():

		return _fail(
			"寫入存檔",
			slot_id,
			"無法建立存檔目錄"
		)

	var main_path: String = (
		_get_slot_path(slot_id)
	)

	var temp_path: String = (
		_get_temp_path(slot_id)
	)

	var backup_path: String = (
		_get_backup_path(slot_id)
	)

	# --------------------------------------------------------
	# A. 寫入暫存檔
	# --------------------------------------------------------

	var file: FileAccess = FileAccess.open(
		temp_path,
		FileAccess.WRITE
	)

	if file == null:

		return _fail(
			"寫入存檔",
			slot_id,
			"無法開啟暫存檔"
		)

	var json_text: String = (
		JSON.stringify(data, "\t")
	)

	file.store_string(json_text)

	# 要求 FileAccess 將目前緩衝內容寫出
	file.flush()

	var write_error: Error = file.get_error()

	# 關閉檔案後再驗證
	file = null

	if write_error != OK:

		return _fail(
			"寫入存檔",
			slot_id,
			"暫存檔寫入失敗"
		)

	# --------------------------------------------------------
	# B. 重新讀取暫存檔
	# --------------------------------------------------------

	var verified_data: Dictionary = (
		_read_slot_file(
			temp_path,
			slot_id
		)
	)

	if verified_data.is_empty():

		return _fail(
			"寫入存檔",
			slot_id,
			"暫存資料驗證失敗"
		)

	# --------------------------------------------------------
	# C. 備份舊存檔
	# --------------------------------------------------------

	if FileAccess.file_exists(main_path):

		var old_data: Dictionary = (
			_read_slot_file(
				main_path,
				slot_id
			)
		)

		# 舊資料已損壞或版本不相容
		# 不允許在一般保存流程覆蓋
		if old_data.is_empty():

			return _fail(
				"寫入存檔",
				slot_id,
				"舊存檔無效，已停止覆蓋"
			)

		var backup_error: Error = (
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path(
					main_path
				),
				ProjectSettings.globalize_path(
					backup_path
				)
			)
		)

		if backup_error != OK:

			return _fail(
				"寫入存檔",
				slot_id,
				"建立備份失敗"
			)

	# --------------------------------------------------------
	# D. 以驗證完成的暫存檔取代正式檔案
	# --------------------------------------------------------

	var rename_error: Error = (
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(
				temp_path
			),
			ProjectSettings.globalize_path(
				main_path
			)
		)
	)

	if rename_error != OK:

		return _fail(
			"寫入存檔",
			slot_id,
			"正式存檔替換失敗"
		)

	if debug_log:

		print(
			"【SaveManager】存檔寫入成功：",
			slot_id
		)

	return true


# ============================================================
# 20. 統一錯誤處理
# ============================================================

func _fail(
	operation: String,
	slot_id: int,
	reason: String
) -> bool:

	var message: String = (
		"【SaveManager】%s失敗｜Slot %02d｜%s"
		% [
			operation,
			slot_id,
			reason
		]
	)

	push_error(message)

	operation_failed.emit(
		operation,
		slot_id,
		reason
	)

	return false


# ============================================================
# 21. 將存檔狀態轉成可讀文字
#
# 僅供初始化及除錯使用。
# ============================================================

func _state_to_text(
	state: SlotState
) -> String:

	match state:

		SlotState.EMPTY:
			return "空白"

		SlotState.READY:
			return "正常"

		SlotState.RECOVERABLE:
			return "可由備份復原"

		SlotState.DAMAGED:
			return "損壞或版本不相容"

	return "未知狀態"

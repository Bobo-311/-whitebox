
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# SaveManager V2｜四格存檔核心管理器
#
# 適用版本：Godot 4.5.1
#
# Autoload 名稱：SaveManager
#
# ------------------------------------------------------------
# 本腳本負責：
#
# 1. 建立四個獨立存檔欄位
# 2. 建立全新遊戲紀錄
# 3. 讀取已有存檔
# 4. 更新目前使用中的存檔
# 5. 驗證存檔資料格式
# 6. 產生供 UI 使用的存檔摘要
# 7. 使用暫存檔降低不完整寫入風險
# 8. 更新存檔時保留上一份有效資料備份
# 9. 防止損壞資料被誤認為空白存檔
#
# ------------------------------------------------------------
# 本腳本暫時不負責：
#
# - 實際切換遊戲地圖
# - 控制阿尼生成
# - 玩家死亡及重生
# - 畫架互動
# - 普通敵人刷新
# - NPC 或 Boss 的實際狀態收集
#
# 以上功能會逐步接入，而不是全部塞在 SaveManager。
#
# ------------------------------------------------------------
# 存檔位置：
#
# user://saves/slot_01.json
# user://saves/slot_02.json
# user://saves/slot_03.json
# user://saves/slot_04.json
#
# .bak = 前一次有效紀錄的備份
# .tmp = 尚未完成替換的寫入暫存檔
#
# 注意：
# 本階段不自動清理未知或損壞檔案。
# ============================================================


# ============================================================
# 1. 對外訊號
#
# SaveManager 不直接修改 UI。
# UI 透過訊號得知資料何時發生變化。
# ============================================================

## 成功建立新存檔
signal slot_created(slot_id: int)

## 成功載入存檔
signal slot_loaded(slot_id: int)

## 成功更新存檔
signal slot_saved(slot_id: int)

## 操作發生錯誤
signal operation_failed(
	operation: String,
	slot_id: int,
	reason: String
)


# ============================================================
# 2. 基本常數
# ============================================================

## 總存檔欄位數量
const SLOT_COUNT: int = 4

## 存檔資料格式版本
##
## 後續若修改必要欄位，
## 必須規劃資料遷移，不能只修改版本數字。
const SCHEMA_VERSION: int = 1

## 使用者存檔資料夾
const SAVE_DIRECTORY: String = "user://saves"

## 單個存檔允許的最大大小：5 MB
##
## 防止意外讀取異常巨大的檔案。
const MAX_SAVE_BYTES: int = 5 * 1024 * 1024


# ============================================================
# 3. 全新遊戲起點
#
# UI 不需要知道遊戲開始於哪張地圖。
# 全部新存檔使用這組統一起點。
#
# 這些是穩定的遊戲資料 ID，
# 不是 Godot 節點路徑。
#
# TODO：
# 後續 CheckpointManager 需將 ID
# 對應到真正的地圖及畫架。
# ============================================================

const INITIAL_MAP_ID: String = "first_land_sakura_garden"

const INITIAL_EASEL_ID: String = "easel_start_01"

const INITIAL_MAP_DISPLAY_NAME: String = "最初之地・櫻花庭園"


# ============================================================
# 4. 存檔狀態
# ============================================================

enum SlotState {

	## 沒有主要存檔、備份與暫存資料
	EMPTY,

	## 主要存檔正常
	READY,

	## 主要存檔無效，但備份可讀
	RECOVERABLE,

	## 存檔損壞、版本不相容或存在未處理資料
	DAMAGED
}


# ============================================================
# 5. Inspector 設定
# ============================================================

@export_group("除錯設定")

## 是否在輸出面板顯示詳細紀錄
@export var debug_log: bool = true


# ============================================================
# 6. 目前存檔的記憶體資料
# ============================================================

## 0 表示尚未選擇任何存檔
var current_slot_id: int = 0

## 目前使用中的完整存檔資料
##
## 外部應透過 get_current_data()
## 取得深層副本，不直接修改此 Dictionary。
var _current_data: Dictionary = {}


# ============================================================
# 7. 初始化 SaveManager
#
# 啟動時只建立資料夾及檢查現有存檔。
# 不會自動建立任何新遊戲。
# ============================================================

func _ready() -> void:

	if not _ensure_directory():

		push_error(
			"【SaveManager】無法建立存檔資料夾"
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

		for slot_id in range(
			1,
			SLOT_COUNT + 1
		):

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
# 8. 確保存檔資料夾存在
#
# 使用 ProjectSettings.globalize_path()
# 將 user:// 轉成作業系統的實際路徑。
# ============================================================

func _ensure_directory() -> bool:

	var absolute_path: String = (
		ProjectSettings.globalize_path(
			SAVE_DIRECTORY
		)
	)

	var result: Error = (
		DirAccess.make_dir_recursive_absolute(
			absolute_path
		)
	)

	return result == OK


# ============================================================
# 9. 驗證欄位編號
#
# 只能使用 Slot 01～04。
# ============================================================

func _is_valid_slot_id(
	slot_id: int
) -> bool:

	return (
		slot_id >= 1
		and slot_id <= SLOT_COUNT
	)


# ============================================================
# 10. 產生各個存檔路徑
# ============================================================

func _get_slot_path(
	slot_id: int
) -> String:

	return (
		"%s/slot_%02d.json"
		% [SAVE_DIRECTORY, slot_id]
	)


func _get_backup_path(
	slot_id: int
) -> String:

	return _get_slot_path(slot_id) + ".bak"


func _get_temp_path(
	slot_id: int
) -> String:

	return _get_slot_path(slot_id) + ".tmp"


# ============================================================
# 11. 取得指定欄位的狀態
#
# 檢查順序：
# 1. 是否有主要存檔
# 2. 主要存檔是否有效
# 3. 是否有可用備份
# 4. 是否有未處理暫存檔
#
# 不能只因為主檔不存在，就認定是空白欄位。
# ============================================================

func get_slot_state(
	slot_id: int
) -> SlotState:

	if not _is_valid_slot_id(slot_id):

		return SlotState.DAMAGED

	var main_path: String = (
		_get_slot_path(slot_id)
	)

	var backup_path: String = (
		_get_backup_path(slot_id)
	)

	var temp_path: String = (
		_get_temp_path(slot_id)
	)

	var has_main: bool = (
		FileAccess.file_exists(main_path)
	)

	var has_backup: bool = (
		FileAccess.file_exists(backup_path)
	)

	var has_temp: bool = (
		FileAccess.file_exists(temp_path)
	)

	# 三種檔案都不存在，才是空白欄位
	if (
		not has_main
		and not has_backup
		and not has_temp
	):

		return SlotState.EMPTY

	# 優先檢查主要存檔
	if has_main:

		var main_data: Dictionary = (
			_read_slot_file(
				main_path,
				slot_id
			)
		)

		if not main_data.is_empty():

			return SlotState.READY

	# 主要存檔無效時檢查備份
	if has_backup:

		var backup_data: Dictionary = (
			_read_slot_file(
				backup_path,
				slot_id
			)
		)

		if not backup_data.is_empty():

			return SlotState.RECOVERABLE

	# 有檔案存在，但無法作為有效存檔
	return SlotState.DAMAGED


# ============================================================
# 12. 建立全新遊戲
#
# 提供主選單使用的正式入口。
#
# UI 只需傳入欄位編號。
# 地圖及畫架 ID 由 SaveManager 管理。
#
# 回傳：
# true  = 成功建立
# false = 建立失敗
# ============================================================

func create_new_game(
	slot_id: int
) -> bool:

	# 防止新遊戲起點未設定
	if (
		INITIAL_MAP_ID.is_empty()
		or INITIAL_EASEL_ID.is_empty()
	):

		return _fail(
			"建立新遊戲",
			slot_id,
			"初始地圖或畫架 ID 尚未設定"
		)

	# 使用統一建立流程
	return create_slot(
		slot_id,
		INITIAL_MAP_ID,
		INITIAL_EASEL_ID,
		INITIAL_MAP_DISPLAY_NAME
	)


# ============================================================
# 13. 建立指定欄位
#
# 安全規則：
# - 不允許超出四個欄位
# - 不允許無效的地圖／畫架 ID
# - 不允許覆蓋已有存檔
# - 不允許覆蓋異常或暫存資料
# - 成功寫入硬碟後才更新目前存檔
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
			"存檔編號超出 1～4"
		)

	if (
		map_id.strip_edges().is_empty()
		or easel_id.strip_edges().is_empty()
	):

		return _fail(
			"建立存檔",
			slot_id,
			"地圖或畫架 ID 不可為空"
		)

	# 必須完全沒有現有資料
	if (
		get_slot_state(slot_id)
		!= SlotState.EMPTY
	):

		return _fail(
			"建立存檔",
			slot_id,
			"欄位已有資料，禁止覆蓋"
		)

	# 產生初始遊戲資料
	var new_data: Dictionary = (
		_create_initial_data(
			slot_id,
			map_id,
			easel_id,
			map_display_name
		)
	)

	# true 表示新檔案，禁止覆蓋舊資料
	if not _write_slot(
		slot_id,
		new_data,
		true
	):

		return false

	# --------------------------------------------------------
	# 寫入成功後，才變更記憶體中的目前存檔
	# --------------------------------------------------------

	current_slot_id = slot_id

	_current_data = new_data.duplicate(true)

	# 通知 UI：欄位已建立
	slot_created.emit(slot_id)

	if debug_log:

		print(
			"【SaveManager】成功建立 Slot %02d"
			% slot_id
		)

	return true


# ============================================================
# 14. 建立初始存檔資料
#
# 全新存檔都使用統一資料結構。
#
# 特別注意：
# 玩家能力、背包、裝備及世界紀錄
# 目前只是預留資料欄位。
#
# 不在此填入沒有確定的遊戲數值。
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

		# ----------------------------------------------------
		# 存檔格式版本與欄位編號
		# ----------------------------------------------------

		"schema_version": SCHEMA_VERSION,

		"slot_id": slot_id,

		# ----------------------------------------------------
		# 存檔基本資訊
		#
		# created_at_unix：建立時間
		# updated_at_unix：最後儲存時間
		# play_seconds：累積遊玩秒數
		# ----------------------------------------------------

		"meta": {

			"created_at_unix": now,

			"updated_at_unix": now,

			"play_seconds": 0.0,

			"map_display_name": map_display_name
		},

		# ----------------------------------------------------
		# 畫架重生資訊
		#
		# 之後死亡時會讀取這兩個 ID，
		# 找到地圖與指定畫架的重生位置。
		# ----------------------------------------------------

		"checkpoint": {

			"map_id": map_id,

			"easel_id": easel_id
		},

		# ----------------------------------------------------
		# 玩家永久資料
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
		# 使用穩定 ID 記錄：
		# 已擊敗 Boss、捷徑、特殊道具、
		# 任務及 NPC 事件。
		#
		# 普通敵人逐隻死亡資料不放在這裡。
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
# 15. 載入已有存檔
#
# 目前保留給後續讀檔系統使用。
#
# 如果主檔有效，讀取主檔。
# 如果主檔損壞但備份有效，讀取備份。
#
# 備份只載入記憶體，不自動覆蓋主檔。
# ============================================================

func load_slot(
	slot_id: int
) -> bool:

	if not _is_valid_slot_id(slot_id):

		return _fail(
			"讀取存檔",
			slot_id,
			"存檔編號不正確"
		)

	var state: SlotState = (
		get_slot_state(slot_id)
	)

	if (
		state != SlotState.READY
		and state != SlotState.RECOVERABLE
	):

		return _fail(
			"讀取存檔",
			slot_id,
			"沒有可使用的有效存檔"
		)

	var source_path: String = (
		_get_slot_path(slot_id)
	)

	# 主要存檔無效時，暫時從備份載入
	if state == SlotState.RECOVERABLE:

		source_path = (
			_get_backup_path(slot_id)
		)

		push_warning(
			"【SaveManager】Slot %02d 暫時從備份讀取"
			% slot_id
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
			"資料讀取或驗證失敗"
		)

	# 成功後才更新目前使用中的存檔
	current_slot_id = slot_id

	_current_data = loaded_data.duplicate(true)

	slot_loaded.emit(slot_id)

	return true


# ============================================================
# 16. 取得目前存檔資料
#
# 回傳深層副本，避免外部修改原始資料。
# ============================================================

func get_current_data() -> Dictionary:

	return _current_data.duplicate(true)


# ============================================================
# 17. 更新目前存檔
#
# 這個函式將來提供給畫架、玩家及世界狀態系統。
#
# 目前先保留完整接口，
# 本階段 UI 不會呼叫它。
#
# 安全規則：
# 只更新正常且已載入的存檔。
# ============================================================

func save_current_data(
	updated_data: Dictionary
) -> bool:

	if current_slot_id == 0:

		return _fail(
			"更新存檔",
			0,
			"目前尚未載入任何存檔"
		)

	if (
		get_slot_state(current_slot_id)
		!= SlotState.READY
	):

		return _fail(
			"更新存檔",
			current_slot_id,
			"目前存檔無法安全更新"
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
			"資料結構驗證失敗"
		)

	# 更新最後儲存時間
	var meta: Dictionary = candidate["meta"]

	meta["updated_at_unix"] = int(
		Time.get_unix_time_from_system()
	)

	candidate["meta"] = meta

	# false 表示更新既有存檔
	if not _write_slot(
		current_slot_id,
		candidate,
		false
	):

		return false

	_current_data = candidate.duplicate(true)

	slot_saved.emit(current_slot_id)

	return true


# ============================================================
# 18. 提供存檔選擇 UI 的摘要資料
#
# UI 不需要知道玩家完整背包與世界資料。
#
# 只回傳：
# - 存檔狀態
# - 地圖名稱
# - 遊玩時間
# - 儲存日期所需時間戳
# - 地圖 ID
# - 畫架 ID
# ============================================================

func get_slot_summary(
	slot_id: int
) -> Dictionary:

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

	var source_path: String = (
		_get_slot_path(slot_id)
	)

	if state == SlotState.RECOVERABLE:

		source_path = _get_backup_path(slot_id)

	var data: Dictionary = (
		_read_slot_file(
			source_path,
			slot_id
		)
	)

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
# 19. 讀取並解析 JSON 存檔
#
# 安全檢查：
#
# 1. 檔案必須存在
# 2. 大小必須在允許範圍內
# 3. JSON 必須能正常解析
# 4. 最外層必須是 Dictionary
# 5. 必須通過存檔結構驗證
#
# 讀取失敗時不修改任何原始檔案。
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

	var file_size: int = file.get_length()

	if (
		file_size <= 0
		or file_size > MAX_SAVE_BYTES
	):

		file = null
		return {}

	var content: String = file.get_as_text()

	# 關閉檔案
	file = null

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
# 20. 檢查 JSON 數值類型
#
# JSON 讀取時數字可能是 int 或 float。
# 因此不能只接受 TYPE_INT。
# ============================================================

func _is_json_number(
	value: Variant
) -> bool:

	return (
		typeof(value) == TYPE_INT
		or typeof(value) == TYPE_FLOAT
	)


# ============================================================
# 21. 驗證存檔資料結構
#
# 防止損壞或不同版本資料被當成正常存檔。
#
# 第一版檢查：
# - 存檔版本
# - 欄位編號
# - 主要資料區塊
# - 時間資料
# - 畫架 ID
# - 玩家及世界資料類型
#
# 後續加入實際玩家數值後，
# 再擴充各欄位的內容驗證。
# ============================================================

func _validate_slot_data(
	data: Dictionary,
	expected_slot_id: int
) -> bool:

	# --------------------------------------------------------
	# A. 檢查資料格式版本與欄位
	# --------------------------------------------------------

	if not data.has("schema_version"):
		return false

	if not data.has("slot_id"):
		return false

	if not _is_json_number(data["schema_version"]):
		return false

	if not _is_json_number(data["slot_id"]):
		return false

	if (
		float(data["schema_version"])
		!= float(SCHEMA_VERSION)
	):

		return false

	if (
		float(data["slot_id"])
		!= float(expected_slot_id)
	):

		return false

	# --------------------------------------------------------
	# B. 檢查主要資料區塊
	# --------------------------------------------------------

	for key in [
		"meta",
		"checkpoint",
		"player",
		"world"
	]:

		if not data.has(key):
			return false

		if typeof(data[key]) != TYPE_DICTIONARY:
			return false

	# --------------------------------------------------------
	# C. 檢查基本時間資訊
	# --------------------------------------------------------

	var meta: Dictionary = data["meta"]

	for key in [
		"created_at_unix",
		"updated_at_unix",
		"play_seconds"
	]:

		if not meta.has(key):
			return false

		if not _is_json_number(meta[key]):
			return false

		if float(meta[key]) < 0.0:
			return false

	if not meta.has("map_display_name"):
		return false

	if (
		typeof(meta["map_display_name"])
		!= TYPE_STRING
	):

		return false

	# --------------------------------------------------------
	# D. 檢查畫架資料
	# --------------------------------------------------------

	var checkpoint: Dictionary = data["checkpoint"]

	for key in [
		"map_id",
		"easel_id"
	]:

		if not checkpoint.has(key):
			return false

		if typeof(checkpoint[key]) != TYPE_STRING:
			return false

		if (
			String(checkpoint[key]).strip_edges().is_empty()
		):

			return false

	# --------------------------------------------------------
	# E. 檢查玩家資料
	# --------------------------------------------------------

	var player: Dictionary = data["player"]

	for key in [
		"stats",
		"inventory",
		"equipment"
	]:

		if not player.has(key):
			return false

		if typeof(player[key]) != TYPE_DICTIONARY:
			return false

	if not player.has("unlocked_skills"):
		return false

	if (
		typeof(player["unlocked_skills"])
		!= TYPE_ARRAY
	):

		return false

	# --------------------------------------------------------
	# F. 檢查世界進度資料
	# --------------------------------------------------------

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
# 22. 將資料寫入磁碟
#
# new_file = true：
# 建立新存檔，禁止覆蓋任何現有資料。
#
# new_file = false：
# 更新正常存檔，會先備份上一份有效資料。
#
# ------------------------------------------------------------
# 流程：
#
# A. 驗證資料
# B. 確認沒有殘留暫存檔
# C. 寫入 .tmp
# D. 關閉檔案並重新讀取驗證
# E. 更新存檔時先建立 .bak
# F. 將 .tmp 改名成正式 .json
#
# 注意：
# 這是降低風險的基本寫入流程。
# 並非所有裝置／硬體故障情況的絕對保證。
# ============================================================

func _write_slot(
	slot_id: int,
	data: Dictionary,
	new_file: bool
) -> bool:

	# --------------------------------------------------------
	# A. 資料驗證
	# --------------------------------------------------------

	if not _is_valid_slot_id(slot_id):

		return _fail(
			"寫入存檔",
			slot_id,
			"存檔編號無效"
		)

	if not _validate_slot_data(
		data,
		slot_id
	):

		return _fail(
			"寫入存檔",
			slot_id,
			"資料驗證失敗"
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

	var backup_path: String = (
		_get_backup_path(slot_id)
	)

	var temp_path: String = (
		_get_temp_path(slot_id)
	)

	# --------------------------------------------------------
	# B. 保護殘留暫存檔
	#
	# 如果上次寫入中斷，.tmp 可能包含待復原資料。
	# 未實作復原流程前，不應直接覆蓋。
	# --------------------------------------------------------

	if FileAccess.file_exists(temp_path):

		return _fail(
			"寫入存檔",
			slot_id,
			"存在尚未處理的暫存檔"
		)

	# --------------------------------------------------------
	# C. 區分建立與更新
	# --------------------------------------------------------

	if new_file:

		# 建立全新存檔時，禁止覆蓋主檔與備份
		if (
			FileAccess.file_exists(main_path)
			or FileAccess.file_exists(backup_path)
		):

			return _fail(
				"寫入存檔",
				slot_id,
				"欄位已有檔案，禁止覆蓋"
			)

	else:

		# 更新時要求舊存檔正常
		if (
			get_slot_state(slot_id)
			!= SlotState.READY
		):

			return _fail(
				"寫入存檔",
				slot_id,
				"既有存檔不是可安全更新的狀態"
			)

	# --------------------------------------------------------
	# D. 寫入暫存檔
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

	# 將緩衝內容要求寫出
	file.flush()

	var write_error: Error = file.get_error()

	# 關閉檔案
	file = null

	if write_error != OK:

		return _fail(
			"寫入存檔",
			slot_id,
			"暫存檔寫入失敗"
		)

	# --------------------------------------------------------
	# E. 重新讀取及驗證暫存檔
	#
	# 不只檢查檔案存在，
	# 也確認整份文字與原資料一致。
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
			"暫存檔資料驗證失敗"
		)

	var read_back_text: String = (
		FileAccess.get_file_as_string(
			temp_path
		)
	)

	if read_back_text != json_text:

		return _fail(
			"寫入存檔",
			slot_id,
			"暫存檔內容比對失敗"
		)

	# --------------------------------------------------------
	# F. 更新存檔時，備份上一份有效資料
	#
	# 新遊戲是全新檔案，因此沒有上一版可備份。
	# --------------------------------------------------------

	if not new_file:

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
				"舊存檔備份失敗"
			)

	# --------------------------------------------------------
	# G. 暫存檔取代正式檔案
	#
	# .tmp 與 .json 位於相同資料夾。
	# 重新命名失敗時保留舊資料，
	# 並回報錯誤。
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
			"無法完成正式檔案替換"
		)

	if debug_log:

		print(
			"【SaveManager】存檔寫入成功：",
			slot_id
		)

	return true


# ============================================================
# 23. 統一錯誤處理
#
# 所有操作失敗都使用相同訊號及輸出格式。
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
# 24. 將存檔狀態轉為文字
#
# 僅供開發階段輸出紀錄。
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
			return "可從備份復原"

		SlotState.DAMAGED:
			return "損壞或版本不相容"

	return "未知狀態"

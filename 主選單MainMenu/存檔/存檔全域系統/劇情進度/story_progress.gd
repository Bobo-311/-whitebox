
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# StoryProgress V1｜劇情永久進度管理器
#
# 適用版本：Godot 4.5.1
# Autoload 名稱：StoryProgress
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 監聽存檔建立及載入事件
# 2. 還原指定存檔的永久劇情進度
# 3. 隔離不同存檔的劇情記憶
# 4. 接收 Dialogic 的正式劇情完成暗號
# 5. 保存經過確認的劇情完成資料
# 6. 避免重複寫入相同劇情紀錄
# 7. 相容尚未包含劇情欄位的舊存檔
# 8. 保護格式異常的劇情資料
#
# ============================================================
# 系統分工
# ============================================================
#
# Dialogic：
# 負責劇本播放及演出暗號。
#
# CutsceneDirector：
# 負責劇情觸發、角色演出及玩家控制。
#
# DataManager：
# 負責遊戲運行期間的劇情記憶。
#
# StoryProgress：
# 負責劇情永久進度的保存及還原。
#
# SaveManager：
# 負責 JSON 驗證、備份及磁碟讀寫。
#
# ============================================================
# V1 實作範圍
# ============================================================
#
# 目前僅正式接入 AM001 的初始開場劇情。
#
# 其他劇情、任務、NPC 狀態與戰鬥解鎖，
# 將在完整世界狀態保存階段逐步整合。
#
# 不直接保存 DataManager 的全部劇情陣列，
# 避免舊版 CutsceneDirector 在演出開始時，
# 就提前將尚未完成的劇情寫入磁碟。
#
# ============================================================


# ============================================================
# 1. 對外訊號
# ============================================================

## 劇情進度已從指定存檔還原。
signal progress_restored(slot_id: int)

## 指定劇情已成功寫入磁碟。
signal cutscene_saved(
	slot_id: int,
	timeline_id: String
)

## 劇情保存失敗。
signal progress_save_failed(
	slot_id: int,
	reason: String
)


# ============================================================
# 2. 常數設定
# ============================================================

## 世界資料中使用的劇情完成欄位名稱。
const SAVE_FIELD: String = "completed_cutscenes"

## AM001 初始地圖路徑。
const OPENING_MAP_PATH: String = (
	"res://Maps/AM001.tscn"
)

## AM001 初始劇情導演節點名稱。
const OPENING_DIRECTOR_PATH: String = (
	"CutsceneDirector"
)

## Dialogic 正式劇情完成暗號。
##
## 必須放在 AM001 開場劇本的最後面。
const OPENING_COMMIT_SIGNAL: String = (
	"story_commit:AM001_opening"
)


# ============================================================
# 3. 除錯設定
# ============================================================

@export_group("除錯設定")

## 是否輸出詳細劇情保存紀錄。
@export var debug_log: bool = true


# ============================================================
# 4. 內部狀態
# ============================================================

## 目前已正式還原劇情資料的存檔編號。
##
## 0 代表目前沒有有效的讀檔工作階段。
var _loaded_slot_id: int = 0

## 是否正在執行劇情存檔。
##
## 防止相同事件重複要求寫入。
var _is_saving: bool = false

## 劇情欄位是否通過格式驗證。
##
## 若存檔中已有異常格式，不擅自覆蓋。
var _progress_valid: bool = true


# ============================================================
# 5. 初始化
# ============================================================

func _ready() -> void:

	# --------------------------------------------------------
	# A. 監聽新存檔建立
	#
	# 建立新夢境時清除上一份存檔的劇情記憶。
	# --------------------------------------------------------

	if not SaveManager.slot_created.is_connected(
		_on_slot_created
	):

		SaveManager.slot_created.connect(
			_on_slot_created
		)

	# --------------------------------------------------------
	# B. 監聽正式讀檔
	#
	# SaveManager.load_slot() 成功後，
	# 會立即發送 slot_loaded。
	#
	# 使用一般同步訊號連接，不使用 deferred。
	#
	# 確保 WorldEntry 開始切換地圖之前，
	# 劇情進度已經完成還原。
	# --------------------------------------------------------

	if not SaveManager.slot_loaded.is_connected(
		_on_slot_loaded
	):

		SaveManager.slot_loaded.connect(
			_on_slot_loaded
		)

	# --------------------------------------------------------
	# C. 監聽 Dialogic 的劇情完成暗號
	#
	# 不需要修改 Dialogic 插件本身。
	# --------------------------------------------------------

	if not Dialogic.signal_event.is_connected(
		_on_dialogic_signal
	):

		Dialogic.signal_event.connect(
			_on_dialogic_signal
		)

	if debug_log:

		print(
			"【StoryProgress】劇情進度管理器初始化完成"
		)


# ============================================================
# 6. 建立新存檔
#
# 新夢境不能繼承其他存檔的劇情完成紀錄。
#
# 建立成功後仍需經過正式 load_slot()，
# 才能進入遊戲並保存劇情。
# ============================================================

func _on_slot_created(slot_id: int) -> void:

	_loaded_slot_id = 0

	_progress_valid = true

	# 清除上一份存檔的運行時劇情記憶。
	DataManager.completed_cutscenes.clear()

	if debug_log:

		print(
			"【StoryProgress】Slot %02d 新夢境，已清空劇情記憶"
			% slot_id
		)


# ============================================================
# 7. 載入指定存檔
#
# SaveManager 已完成 JSON 驗證及讀取，
# StoryProgress 只負責還原劇情部分。
# ============================================================

func _on_slot_loaded(slot_id: int) -> void:

	_loaded_slot_id = 0

	_progress_valid = true

	# --------------------------------------------------------
	# A. 清除上一份存檔的劇情進度
	#
	# 不能使用 append 直接疊加舊紀錄。
	# 否則 Slot 01 與 Slot 02 可能互相污染。
	# --------------------------------------------------------

	DataManager.completed_cutscenes.clear()

	# --------------------------------------------------------
	# B. 取得目前存檔的深層副本
	# --------------------------------------------------------

	var save_data: Dictionary = (
		SaveManager.get_current_data()
	)

	# --------------------------------------------------------
	# C. 驗證並解析劇情完成資料
	# --------------------------------------------------------

	var restored_data: Variant = (
		_read_completed_cutscenes(save_data)
	)

	if restored_data == null:

		_progress_valid = false

		push_error(
			"【StoryProgress】Slot %02d 劇情資料格式異常"
			% slot_id
		)

		return

	# --------------------------------------------------------
	# D. 將 JSON 陣列轉為 Array[String]
	#
	# JSON 解析得到的陣列不一定具有型別資訊，
	# 因此逐筆安全還原。
	# --------------------------------------------------------

	var restored_ids: Array[String] = []

	restored_ids.assign(restored_data)

	for timeline_id in restored_ids:

		DataManager.mark_cutscene_completed(
			timeline_id
		)

	# --------------------------------------------------------
	# E. 登記目前有效的存檔工作階段
	# --------------------------------------------------------

	_loaded_slot_id = slot_id

	progress_restored.emit(slot_id)

	if debug_log:

		print(
			"【StoryProgress】已還原 Slot %02d 劇情進度"
			% slot_id
		)

		print(
			"【StoryProgress】永久完成劇情：",
			restored_ids
		)


# ============================================================
# 8. 解析及驗證劇情資料
#
# 回傳：
#
# Array[String]：
# 格式正常，包含已完成劇情。
#
# 空陣列：
# 舊存檔沒有劇情欄位，
# 或目前沒有完成任何劇情。
#
# null：
# 劇情資料格式異常。
#
# 異常資料不可直接覆蓋成空陣列後保存。
# ============================================================

func _read_completed_cutscenes(
	save_data: Dictionary
) -> Variant:

	# 確認 world 區塊存在。
	if not save_data.has("world"):
		return null

	if typeof(save_data["world"]) != TYPE_DICTIONARY:
		return null

	var world: Dictionary = save_data["world"]

	var result: Array[String] = []

	# --------------------------------------------------------
	# 舊存檔相容處理
	#
	# 尚未包含新欄位屬於正常情況。
	# --------------------------------------------------------

	if not world.has(SAVE_FIELD):

		return result

	# --------------------------------------------------------
	# 驗證劇情資料是否為陣列
	# --------------------------------------------------------

	var raw_data: Variant = world[SAVE_FIELD]

	if typeof(raw_data) != TYPE_ARRAY:

		return null

	# --------------------------------------------------------
	# 逐筆驗證劇情 ID
	#
	# 必須為非空白字串，
	# 並自動排除重複紀錄。
	# --------------------------------------------------------

	for value in raw_data:

		if typeof(value) != TYPE_STRING:

			return null

		var timeline_id: String = (
			String(value).strip_edges()
		)

		if timeline_id.is_empty():

			return null

		if not result.has(timeline_id):

			result.append(timeline_id)

	return result


# ============================================================
# 9. 接收 Dialogic 劇情暗號
#
# 只處理 StoryProgress 自己負責的暗號。
#
# 不影響原本的：
# - anim
# - shake
# - move
# - book
# - complete
# - unlock_combat
# - fade_out_cinematic
# ============================================================

func _on_dialogic_signal(argument: String) -> void:

	if argument != OPENING_COMMIT_SIGNAL:

		return

	_commit_opening_cutscene()


# ============================================================
# 10. 確認 AM001 初始劇情已完成
#
# 由劇本最後一個正式暗號觸發。
#
# 不使用 timeline_started。
# 不單靠 timeline_ended 判斷完成。
#
# 因為部分劇情可能被強制結束，
# 強制結束不一定代表玩家完整看完劇情。
# ============================================================

func _commit_opening_cutscene() -> void:

	# --------------------------------------------------------
	# A. 驗證目前場景
	# --------------------------------------------------------

	var current_map: Node = (
		get_tree().current_scene
	)

	if not is_instance_valid(current_map):

		return

	if current_map.scene_file_path != OPENING_MAP_PATH:

		push_warning(
			"【StoryProgress】開場完成暗號不屬於 AM001"
		)

		return

	# --------------------------------------------------------
	# B. 取得既有 CutsceneDirector
	#
	# 不猜測劇本名稱，
	# 使用原本 Inspector 設定的 Target Timeline。
	# --------------------------------------------------------

	var director: CutsceneDirector = (
		current_map.get_node_or_null(
			OPENING_DIRECTOR_PATH
		) as CutsceneDirector
	)

	if not is_instance_valid(director):

		push_error(
			"【StoryProgress】找不到 AM001 CutsceneDirector"
		)

		return

	# 必須是目前正在進行的地圖開場劇情。
	if not director.is_active:

		push_warning(
			"【StoryProgress】開場劇情目前未處於播放狀態"
		)

		return

	if not director.trigger_on_map_enter:

		push_warning(
			"【StoryProgress】指定導演不是地圖開場劇情"
		)

		return

	# --------------------------------------------------------
	# C. 保護具有自動跨地圖功能的劇本
	#
	# V1 僅支援原地結束的開場劇情。
	#
	# 如果劇情結束後會自動傳送，
	# 必須等正式檢查點整合後再保存，
	# 避免讀檔時跳過必要的地圖傳送。
	# --------------------------------------------------------

	if not director.next_scene_after_cutscene.is_empty():

		push_warning(
			"【StoryProgress】跨地圖劇情暫不允許獨立保存"
		)

		return

	# --------------------------------------------------------
	# D. 取得正式劇本 ID
	# --------------------------------------------------------

	var timeline_id: String = (
		director.target_timeline.strip_edges()
	)

	if timeline_id.is_empty():

		push_error(
			"【StoryProgress】Target Timeline 尚未設定"
		)

		return

	# --------------------------------------------------------
	# E. 正式保存劇情完成紀錄
	# --------------------------------------------------------

	_save_completed_cutscene(timeline_id)


# ============================================================
# 11. 正式保存劇情完成紀錄
#
# 此函式只保存已經經過正式確認的劇情。
#
# 不直接將 DataManager.completed_cutscenes
# 整份寫入存檔。
#
# 原因：
# 目前舊版 CutsceneDirector 會提前登記劇情，
# 若整份保存可能把尚未完成的劇情一起寫入。
# ============================================================

func _save_completed_cutscene(
	timeline_id: String
) -> bool:

	# --------------------------------------------------------
	# A. 防止重複寫入
	# --------------------------------------------------------

	if _is_saving:

		return false

	if timeline_id.strip_edges().is_empty():

		return false

	# --------------------------------------------------------
	# B. 確認劇情欄位格式正常
	# --------------------------------------------------------

	if not _progress_valid:

		return _fail(
			"劇情資料格式異常，禁止覆蓋"
		)

	# --------------------------------------------------------
	# C. 驗證目前存檔工作階段
	#
	# 直接使用 F6 測試 AM001 時，
	# 可能沒有選擇任何正式存檔。
	#
	# 此時不可自動建立檔案，
	# 也不能寫入其他欄位。
	# --------------------------------------------------------

	if _loaded_slot_id <= 0:

		if debug_log:

			print(
				"【StoryProgress】目前未載入正式存檔，略過保存"
			)

		return false

	if (
		SaveManager.current_slot_id
		!= _loaded_slot_id
	):

		return _fail(
			"目前存檔與劇情工作階段不一致"
		)

	# --------------------------------------------------------
	# D. 取得目前存檔資料副本
	#
	# 保留其他玩家、畫架及世界資料。
	# 不重新建立整份 JSON。
	# --------------------------------------------------------

	var candidate: Dictionary = (
		SaveManager.get_current_data()
	)

	var existing_data: Variant = (
		_read_completed_cutscenes(candidate)
	)

	if existing_data == null:

		return _fail(
			"無法驗證既有劇情資料"
		)

	var completed_ids: Array[String] = []

	completed_ids.assign(existing_data)

	# --------------------------------------------------------
	# E. 檢查是否已經永久保存
	#
	# 相同劇情不需要再次寫入硬碟。
	# --------------------------------------------------------

	if completed_ids.has(timeline_id):

		DataManager.mark_cutscene_completed(
			timeline_id
		)

		return true

	# --------------------------------------------------------
	# F. 將本次完成的劇情加入存檔副本
	# --------------------------------------------------------

	completed_ids.append(timeline_id)

	var world: Dictionary = candidate["world"]

	world[SAVE_FIELD] = completed_ids

	candidate["world"] = world

	# --------------------------------------------------------
	# G. 交給既有 SaveManager 正式寫入
	#
	# 沿用原本：
	# - 存檔驗證
	# - 暫存檔
	# - 備份
	# - 正式檔案替換
	# - 更新時間
	# --------------------------------------------------------

	_is_saving = true

	var success: bool = (
		SaveManager.save_current_data(candidate)
	)

	_is_saving = false

	# --------------------------------------------------------
	# H. 寫入失敗
	#
	# 不宣告永久保存成功。
	# 不阻止正常劇情繼續播放。
	# 不擅自刪除原始存檔。
	# --------------------------------------------------------

	if not success:

		return _fail(
			"SaveManager 寫入劇情進度失敗"
		)

	# --------------------------------------------------------
	# I. 正式保存成功
	#
	# 既有 DataManager 登記函式具有去重保護。
	# --------------------------------------------------------

	DataManager.mark_cutscene_completed(
		timeline_id
	)

	cutscene_saved.emit(
		_loaded_slot_id,
		timeline_id
	)

	if debug_log:

		print(
			"【StoryProgress】Slot %02d 劇情永久保存成功：%s"
			% [
				_loaded_slot_id,
				timeline_id
			]
		)

		print(
			"【StoryProgress】目前永久完成劇情：",
			completed_ids
		)

	return true


# ============================================================
# 12. 統一錯誤處理
# ============================================================

func _fail(reason: String) -> bool:

	push_error(
		"【StoryProgress】Slot %02d 保存失敗：%s"
		% [
			_loaded_slot_id,
			reason
		]
	)

	progress_save_failed.emit(
		_loaded_slot_id,
		reason
	)

	return false

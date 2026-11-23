
extends MainMenuPage
class_name SaveSelectPage

# ============================================================
# 《眠境 RE:RECOLOR》
# 夢境紀錄頁面 V6｜新遊戲正式建立版
# Godot 4.5.1
#
# 功能：
# 1. 四格存檔資料顯示
# 2. 空白／正常／可復原／損壞狀態處理
# 3. 新遊戲確認視窗
# 4. 清除紀錄確認視窗
# 5. 真正呼叫 SaveManager 建立新遊戲
# 6. 成功後即時更新 UI
# 7. 保留原本 Hover、音效及返回功能
#
# 尚未實作：
# - 真正刪除存檔
# - 載入遊戲場景
# - 玩家死亡重生
#
# 不修改任何場景排版與 Skin。
# ============================================================


# ============================================================
# 1. 常數及確認視窗類型
# ============================================================

const SLOT_COUNT: int = 4

enum DialogKind {
	NEW_GAME,
	DELETE_SAVE
}


# ============================================================
# 2. Inspector 設定
# ============================================================

@export_group("確認視窗")

## 指定共用 confirm_dialog.tscn
@export var confirm_dialog_scene: PackedScene

@export_group("除錯設定")

## 是否輸出操作紀錄
@export var debug_log: bool = true


# ============================================================
# 3. 節點及內部資料
# ============================================================

@onready var slots_container: VBoxContainer = $Slots

## 四個存檔欄位 UI 的引用
var _slots: Dictionary[int, SaveSlotRow] = {}

## 目前開啟的確認視窗
var _active_dialog: ConfirmDialog = null


# ============================================================
# 4. 初始化
#
# 保留 MainMenuPage 的原本功能。
# ============================================================

func _ready() -> void:
	super._ready()
	_setup_slots()
	_connect_save_manager_signals()
	_refresh_all_slots()


# ============================================================
# 5. 設定四個 SaveSlotRow
#
# 每個欄位只連接一次訊號。
# ============================================================

func _setup_slots() -> void:

	_slots.clear()

	for slot_id in range(1, SLOT_COUNT + 1):

		var node_name: String = "Slot%02d" % slot_id

		var row: SaveSlotRow = (
			slots_container.get_node_or_null(node_name)
			as SaveSlotRow
		)

		if row == null:
			push_error("【夢境紀錄】找不到：" + node_name)
			continue

		row.set_slot_id(slot_id)
		_slots[slot_id] = row

		row.slot_selected.connect(_on_slot_selected)
		row.delete_requested.connect(_on_delete_requested)
		row.hover_requested.connect(_on_hover)


# ============================================================
# 6. 監聽 SaveManager
#
# 真正建立存檔後會收到 slot_created，
# 因此不需要重新開啟頁面。
# ============================================================

func _connect_save_manager_signals() -> void:

	SaveManager.slot_created.connect(_on_save_slot_changed)
	SaveManager.slot_loaded.connect(_on_save_slot_changed)
	SaveManager.slot_saved.connect(_on_save_slot_changed)


func _on_save_slot_changed(slot_id: int) -> void:
	_refresh_slot(slot_id)


# ============================================================
# 7. 更新四個存檔欄位
# ============================================================

func _refresh_all_slots() -> void:

	for slot_id in range(1, SLOT_COUNT + 1):
		_refresh_slot(slot_id)


# ============================================================
# 8. 讀取真實存檔狀態並更新單一欄位
#
# 不直接操作 JSON。
# 所有資訊都來自 SaveManager。
# ============================================================

func _refresh_slot(slot_id: int) -> void:

	var row: SaveSlotRow = get_slot(slot_id)

	if row == null:
		return

	var summary: Dictionary = (
		SaveManager.get_slot_summary(slot_id)
	)

	var state: int = int(
		summary.get(
			"state",
			SaveManager.SlotState.DAMAGED
		)
	)

	match state:

		# 空白欄位
		SaveManager.SlotState.EMPTY:

			row.show_empty()
			_set_row_interaction(row, true, false)

		# 正常存檔
		SaveManager.SlotState.READY:

			_show_saved_summary(row, summary)
			_set_row_interaction(row, true, true)

		# 主要存檔無效，但備份可讀
		SaveManager.SlotState.RECOVERABLE:

			_show_saved_summary(row, summary)
			_set_row_warning(row, "可從備份復原")
			_set_row_interaction(row, false, false)

		# 損壞或未知狀態
		_:

			_show_damaged_slot(row)

	if debug_log:

		print(
			"【夢境紀錄】更新 Slot %02d，狀態：%d"
			% [slot_id, state]
		)


# ============================================================
# 9. 顯示已有存檔的基本資訊
#
# 使用原本的 SaveSlotRow.show_saved()。
# 不更改場景排版。
# ============================================================

func _show_saved_summary(
	row: SaveSlotRow,
	summary: Dictionary
) -> void:

	var map_name: String = str(
		summary.get("map_name", "未知地區")
	)

	var play_seconds: int = maxi(
		int(summary.get("play_seconds", 0.0)),
		0
	)

	var timestamp: int = int(
		summary.get("updated_at_unix", 0)
	)

	var saved_date: String = (
		_format_save_date(timestamp)
	)

	row.show_saved(
		map_name,
		play_seconds,
		saved_date
	)


# ============================================================
# 10. 日期格式
#
# Unix 時間轉換為系統本地日期。
# 顯示格式：YYYY/MM/DD
#
# 目前使用系統當下的 UTC 偏移。
# ============================================================

func _format_save_date(
	unix_timestamp: int
) -> String:

	if unix_timestamp <= 0:
		return "未知日期"

	var time_zone: Dictionary = (
		Time.get_time_zone_from_system()
	)

	var offset_minutes: int = int(
		time_zone.get("bias", 0)
	)

	var local_timestamp: int = (
		unix_timestamp + offset_minutes * 60
	)

	var date: Dictionary = (
		Time.get_datetime_dict_from_unix_time(
			local_timestamp
		)
	)

	return "%04d/%02d/%02d" % [
		int(date["year"]),
		int(date["month"]),
		int(date["day"])
	]


# ============================================================
# 11. 備份狀態提示
#
# 暫時使用現有 DetailLabel 顯示狀態。
# ============================================================

func _set_row_warning(
	row: SaveSlotRow,
	message: String
) -> void:

	var label: Label = (
		row.get_node_or_null(
			"Actions/SlotButton/SlotContent/"
			+ "InfoRow/InfoColumn/DetailLabel"
		) as Label
	)

	if label != null:
		label.text = message


# ============================================================
# 12. 損壞存檔顯示
#
# 不能將損壞存檔當作空白存檔。
# 禁止直接選擇及覆蓋。
# ============================================================

func _show_damaged_slot(row: SaveSlotRow) -> void:

	row.show_empty()

	row.slot_state = SaveSlotRow.SlotState.DAMAGED

	var map_label: Label = (
		row.get_node_or_null(
			"Actions/SlotButton/SlotContent/"
			+ "InfoRow/InfoColumn/MapNameLabel"
		) as Label
	)

	var detail_label: Label = (
		row.get_node_or_null(
			"Actions/SlotButton/SlotContent/"
			+ "InfoRow/InfoColumn/DetailLabel"
		) as Label
	)

	if map_label != null:
		map_label.text = "夢境紀錄異常"

	if detail_label != null:
		detail_label.text = "損壞或版本不相容"

	_set_row_interaction(row, false, false)


# ============================================================
# 13. 控制欄位按鈕是否可以操作
#
# 不改變 Skin、位置及大小。
# ============================================================

func _set_row_interaction(
	row: SaveSlotRow,
	slot_enabled: bool,
	delete_enabled: bool
) -> void:

	var slot_button: Button = (
		row.get_node_or_null("Actions/SlotButton")
		as Button
	)

	var delete_button: Button = (
		row.get_node_or_null("Actions/DeleteButton")
		as Button
	)

	if slot_button != null:
		slot_button.disabled = not slot_enabled

	if delete_button != null:
		delete_button.disabled = not delete_enabled


# ============================================================
# 14. 玩家點擊存檔欄位
#
# 每次點擊都重新查詢真實狀態。
# ============================================================

func _on_slot_selected(slot_id: int) -> void:

	if not _slots.has(slot_id):
		return

	if is_instance_valid(_active_dialog):
		return

	var state: int = (
		SaveManager.get_slot_state(slot_id)
	)

	match state:

		SaveManager.SlotState.EMPTY:

			_open_slot_dialog(
				slot_id,
				DialogKind.NEW_GAME
			)

		SaveManager.SlotState.READY:

			# TODO：
			# 下一階段接上真正讀檔及地圖切換。
			option_requested.emit(
				StringName("SaveSlot%02d" % slot_id)
			)

		_:

			_refresh_slot(slot_id)


# ============================================================
# 15. 玩家點擊清除紀錄
#
# 只有正常存檔能進入清除確認視窗。
# 本階段不執行真正刪除。
# ============================================================

func _on_delete_requested(slot_id: int) -> void:

	if not _slots.has(slot_id):
		return

	if is_instance_valid(_active_dialog):
		return

	if (
		SaveManager.get_slot_state(slot_id)
		!= SaveManager.SlotState.READY
	):
		_refresh_slot(slot_id)
		return

	_open_slot_dialog(
		slot_id,
		DialogKind.DELETE_SAVE
	)


# ============================================================
# 16. 建立共用確認視窗
#
# 先設定內容，再 add_child。
# 保留現在使用的 Skin 與動畫。
# ============================================================

func _open_slot_dialog(
	slot_id: int,
	kind: DialogKind
) -> void:

	if is_instance_valid(_active_dialog):
		return

	if confirm_dialog_scene == null:
		push_error("【夢境紀錄】未指定確認視窗場景")
		return

	var instance: Node = (
		confirm_dialog_scene.instantiate()
	)

	var dialog: ConfirmDialog = (
		instance as ConfirmDialog
	)

	if dialog == null:
		instance.free()
		push_error("【夢境紀錄】確認視窗類型不正確")
		return

	match kind:

		DialogKind.NEW_GAME:

			dialog.configure(
				"開始新的夢境",
				"確定要在第 %02d 格開始新的夢境嗎？"
					% slot_id,
				"一段嶄新的旅程，即將展開。",
				"開始夢境",
				"取消"
			)

		DialogKind.DELETE_SAVE:

			dialog.configure(
				"清除夢境紀錄",
				"確定要清除第 %02d 格的夢境紀錄嗎？"
					% slot_id,
				"清除後，該紀錄將無法復原。",
				"確認清除",
				"取消"
			)

	# 共用音效
	dialog.hover_requested.connect(_on_hover)

	dialog.confirm_sound_requested.connect(
		_on_dialog_sound_requested
	)

	# 確認及取消事件
	dialog.confirmed.connect(
		_on_dialog_confirmed.bind(slot_id, kind)
	)

	dialog.cancelled.connect(
		_on_dialog_cancelled.bind(slot_id, kind)
	)

	_active_dialog = dialog

	add_child(dialog)

	dialog.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	dialog.move_to_front()

	_on_dialog_sound_requested()


# ============================================================
# 17. 玩家確認視窗操作
#
# 新遊戲：真正建立存檔
# 清除紀錄：暫時只顯示測試訊息
# ============================================================

func _on_dialog_confirmed(
	slot_id: int,
	kind: DialogKind
) -> void:

	_active_dialog = null

	match kind:

		DialogKind.NEW_GAME:

			_create_new_game(slot_id)

		DialogKind.DELETE_SAVE:

			if debug_log:
				print(
					"【UI 測試】第 %02d 格確認清除，但目前不刪檔"
					% slot_id
				)

	# 再次以真實磁碟狀態刷新
	_refresh_slot(slot_id)


# ============================================================
# 18. 正式建立新遊戲
#
# 安全流程：
# 1. 再次確認欄位為 EMPTY
# 2. 呼叫 SaveManager.create_new_game()
# 3. 檢查是否成功
# 4. 成功後 UI 透過 slot_created 自動更新
#
# 不在存檔失敗時建立玩家或切換地圖。
# ============================================================

func _create_new_game(slot_id: int) -> void:

	# 再次確認欄位仍是空白
	if (
		SaveManager.get_slot_state(slot_id)
		!= SaveManager.SlotState.EMPTY
	):

		push_warning(
			"【夢境紀錄】第 %02d 格不再是空白，停止建立"
			% slot_id
		)

		_refresh_slot(slot_id)
		return

	# 正式要求 SaveManager 建立資料
	var success: bool = (
		SaveManager.create_new_game(slot_id)
	)

	# 寫入失敗，不修改 UI 為已有紀錄
	if not success:

		push_warning(
			"【夢境紀錄】建立失敗，請檢查 SaveManager 輸出"
		)

		_refresh_slot(slot_id)
		return

	# 成功寫入後，SaveManager 已發送 slot_created
	if debug_log:

		print(
			"【夢境紀錄】成功建立第 %02d 格，尚未切換遊戲場景"
			% slot_id
		)

	# TODO：
	# 實際地圖、玩家初始化與畫架生成
	# 將在下一階段接入。


# ============================================================
# 19. 取消確認視窗
# ============================================================

func _on_dialog_cancelled(
	slot_id: int,
	kind: DialogKind
) -> void:

	_active_dialog = null

	if debug_log:

		print(
			"【夢境紀錄】取消操作：Slot %02d，類型 %d"
			% [slot_id, kind]
		)


# ============================================================
# 20. 共用確認音效
#
# 保留既有 MenuActions 訊號接口。
# ============================================================

func _on_dialog_sound_requested() -> void:

	option_requested.emit(&"Confirm")


# ============================================================
# 21. 取得指定存檔欄位 UI
# ============================================================

func get_slot(slot_id: int) -> SaveSlotRow:

	return _slots.get(slot_id) as SaveSlotRow

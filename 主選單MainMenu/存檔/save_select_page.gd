
extends MainMenuPage
class_name SaveSelectPage

# ============================================================
# 《眠境 RE:RECOLOR》
# SaveSelectPage V7｜夢境紀錄與正式遊戲進場
#
# Godot 4.5.1
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 四格真實存檔資料顯示
# 2. 空白／正常／可復原／損壞狀態處理
# 3. 新遊戲確認視窗
# 4. 清除紀錄確認視窗
# 5. 呼叫 SaveManager 正式建立存檔
# 6. 存檔建立後自動更新 UI
# 7. 已有存檔正式讀取進場
# 8. 新遊戲建立成功後直接進場
# 9. 防止場景切換期間重複操作
# 10. 保留 Hover、確認音效及返回功能
#
# ============================================================
# 系統分工
# ============================================================
#
# SaveSelectPage：
# 顯示存檔、確認玩家操作、發送進場要求。
#
# SaveManager：
# 真正建立、讀取及寫入存檔。
#
# MenuActions：
# 接收選擇結果、控制主選單操作鎖。
#
# WorldEntry：
# 解析地圖及出生點，提出遊戲進場要求。
#
# SceneTransition：
# 實際執行地圖切換及黑幕動畫。
#
# ============================================================
# 尚未實作
# ============================================================
#
# - 真正刪除存檔
# - 備份復原介面
# - 畫架存檔
# - 玩家死亡重生
#
# 本版本不修改 UI 排版、Skin 或節點名稱。
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

## 共用確認視窗場景
@export var confirm_dialog_scene: PackedScene

@export_group("除錯設定")

## 是否輸出存檔頁面操作紀錄
@export var debug_log: bool = true


# ============================================================
# 3. 節點及內部資料
# ============================================================

@onready var slots_container: VBoxContainer = $Slots

## 四個存檔欄位的 UI 引用
var _slots: Dictionary[int, SaveSlotRow] = {}

## 目前開啟的確認視窗
var _active_dialog: ConfirmDialog = null

## 防止新遊戲建立期間重複操作
var _is_creating_save: bool = false


# ============================================================
# 4. 初始化
# ============================================================

func _ready() -> void:

	# 保留 MainMenuPage 原本的初始化。
	super._ready()

	_setup_slots()

	_connect_save_manager_signals()

	_refresh_all_slots()


# ============================================================
# 5. 設定四個存檔欄位
#
# 統一設定欄位編號及連接訊號。
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

			push_error(
				"【夢境紀錄】找不到：" + node_name
			)

			continue

		row.set_slot_id(slot_id)

		_slots[slot_id] = row

		row.slot_selected.connect(_on_slot_selected)

		row.delete_requested.connect(_on_delete_requested)

		row.hover_requested.connect(_on_hover)


# ============================================================
# 6. 監聽 SaveManager
#
# 存檔建立、載入及保存時，
# 自動更新對應欄位。
# ============================================================

func _connect_save_manager_signals() -> void:

	SaveManager.slot_created.connect(
		_on_save_slot_changed
	)

	SaveManager.slot_loaded.connect(
		_on_save_slot_changed
	)

	SaveManager.slot_saved.connect(
		_on_save_slot_changed
	)


func _on_save_slot_changed(slot_id: int) -> void:

	_refresh_slot(slot_id)


# ============================================================
# 7. 更新全部存檔欄位
# ============================================================

func _refresh_all_slots() -> void:

	for slot_id in range(1, SLOT_COUNT + 1):

		_refresh_slot(slot_id)


# ============================================================
# 8. 讀取真實存檔狀態
#
# 不直接讀取 JSON。
# 所有顯示資訊皆來自 SaveManager。
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

		# ----------------------------------------------------
		# 空白欄位
		# ----------------------------------------------------

		SaveManager.SlotState.EMPTY:

			row.show_empty()

			_set_row_interaction(
				row,
				true,
				false
			)

		# ----------------------------------------------------
		# 正常存檔
		# ----------------------------------------------------

		SaveManager.SlotState.READY:

			_show_saved_summary(
				row,
				summary
			)

			_set_row_interaction(
				row,
				true,
				true
			)

		# ----------------------------------------------------
		# 存檔異常，但備份可復原
		# ----------------------------------------------------

		SaveManager.SlotState.RECOVERABLE:

			_show_saved_summary(
				row,
				summary
			)

			_set_row_warning(
				row,
				"可從備份復原"
			)

			_set_row_interaction(
				row,
				false,
				false
			)

		# ----------------------------------------------------
		# 損壞或未知狀態
		# ----------------------------------------------------

		_:

			_show_damaged_slot(row)

	if debug_log:

		print(
			"【夢境紀錄】更新 Slot %02d，狀態：%d"
			% [slot_id, state]
		)


# ============================================================
# 9. 顯示正常存檔摘要
#
# 保留原本的 SaveSlotRow.show_saved()。
# ============================================================

func _show_saved_summary(
	row: SaveSlotRow,
	summary: Dictionary
) -> void:

	var map_name: String = str(
		summary.get(
			"map_name",
			"未知地區"
		)
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
# 10. 存檔日期格式
#
# Unix 時間轉換為系統當前本地日期。
# 顯示格式：YYYY/MM/DD
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
# 暫時沿用 DetailLabel。
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
# 不得將損壞資料視為空白存檔。
# 避免玩家不小心覆蓋原本紀錄。
# ============================================================

func _show_damaged_slot(
	row: SaveSlotRow
) -> void:

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

	_set_row_interaction(
		row,
		false,
		false
	)


# ============================================================
# 13. 控制欄位按鈕操作狀態
#
# 不修改 Skin、位置或尺寸。
# ============================================================

func _set_row_interaction(
	row: SaveSlotRow,
	slot_enabled: bool,
	delete_enabled: bool
) -> void:

	var slot_button: Button = (
		row.get_node_or_null(
			"Actions/SlotButton"
		) as Button
	)

	var delete_button: Button = (
		row.get_node_or_null(
			"Actions/DeleteButton"
		) as Button
	)

	if slot_button != null:

		slot_button.disabled = not slot_enabled

	if delete_button != null:

		delete_button.disabled = not delete_enabled


# ============================================================
# 14. 共用操作檢查
#
# 確認視窗開啟、存檔建立中或場景切換中，
# 不允許再次選擇其他欄位。
# ============================================================

func _can_interact_with_slots() -> bool:

	if _is_creating_save:
		return false

	if SceneTransition.is_transitioning:
		return false

	if is_instance_valid(_active_dialog):
		return false

	return true


# ============================================================
# 15. 玩家選擇存檔欄位
# ============================================================

func _on_slot_selected(slot_id: int) -> void:

	if not _slots.has(slot_id):
		return

	if not _can_interact_with_slots():
		return

	var state: int = (
		SaveManager.get_slot_state(slot_id)
	)

	match state:

		# ----------------------------------------------------
		# 空白存檔
		#
		# 開啟新遊戲確認視窗。
		# ----------------------------------------------------

		SaveManager.SlotState.EMPTY:

			_open_slot_dialog(
				slot_id,
				DialogKind.NEW_GAME
			)

		# ----------------------------------------------------
		# 已有存檔
		#
		# 直接提出正式進場要求。
		# ----------------------------------------------------

		SaveManager.SlotState.READY:

			_request_world_entry(slot_id)

		# ----------------------------------------------------
		# 異常存檔
		# ----------------------------------------------------

		_:

			_refresh_slot(slot_id)


# ============================================================
# 16. 玩家選擇清除紀錄
#
# 目前只保留確認視窗。
# 尚未執行實際刪檔。
# ============================================================

func _on_delete_requested(slot_id: int) -> void:

	if not _slots.has(slot_id):
		return

	if not _can_interact_with_slots():
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
# 17. 建立共用確認視窗
#
# 保留既有文字、Skin 及動畫。
# ============================================================

func _open_slot_dialog(
	slot_id: int,
	kind: DialogKind
) -> void:

	if not _can_interact_with_slots():
		return

	if confirm_dialog_scene == null:

		push_error(
			"【夢境紀錄】未指定確認視窗場景"
		)

		return

	var instance: Node = (
		confirm_dialog_scene.instantiate()
	)

	var dialog: ConfirmDialog = (
		instance as ConfirmDialog
	)

	if dialog == null:

		instance.free()

		push_error(
			"【夢境紀錄】確認視窗類型不正確"
		)

		return

	# --------------------------------------------------------
	# A. 設定確認視窗內容
	# --------------------------------------------------------

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

	# --------------------------------------------------------
	# B. 共用音效訊號
	# --------------------------------------------------------

	dialog.hover_requested.connect(
		_on_hover
	)

	dialog.confirm_sound_requested.connect(
		_on_dialog_sound_requested
	)

	# --------------------------------------------------------
	# C. 確認與取消訊號
	# --------------------------------------------------------

	dialog.confirmed.connect(
		_on_dialog_confirmed.bind(
			slot_id,
			kind
		)
	)

	dialog.cancelled.connect(
		_on_dialog_cancelled.bind(
			slot_id,
			kind
		)
	)

	# --------------------------------------------------------
	# D. 顯示確認視窗
	# --------------------------------------------------------

	_active_dialog = dialog

	add_child(dialog)

	dialog.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	dialog.move_to_front()

	_on_dialog_sound_requested()


# ============================================================
# 18. 確認視窗操作
#
# 新遊戲：
# 建立成功後立即提出正式進場要求。
#
# 清除紀錄：
# 暫時保留測試行為。
# ============================================================

func _on_dialog_confirmed(
	slot_id: int,
	kind: DialogKind
) -> void:

	_active_dialog = null

	match kind:

		# ----------------------------------------------------
		# A. 開始新的夢境
		# ----------------------------------------------------

		DialogKind.NEW_GAME:

			var success: bool = (
				_create_new_game(slot_id)
			)

			_refresh_slot(slot_id)

			# 只有成功建立真實存檔後，
			# 才允許正式進入遊戲。

			if success:

				_request_world_entry(slot_id)

		# ----------------------------------------------------
		# B. 清除夢境紀錄
		#
		# 尚未接入正式刪檔。
		# ----------------------------------------------------

		DialogKind.DELETE_SAVE:

			if debug_log:

				print(
					"【UI 測試】第 %02d 格確認清除，但目前不刪檔"
					% slot_id
				)

			_refresh_slot(slot_id)


# ============================================================
# 19. 正式建立新遊戲
#
# 安全流程：
#
# 1. 防止重複建立
# 2. 確認欄位仍為 EMPTY
# 3. 呼叫 SaveManager.create_new_game()
# 4. 確認寫入成功
# 5. 回傳建立結果
#
# 本函式不直接切換場景。
# ============================================================

func _create_new_game(slot_id: int) -> bool:

	# 防止建立期間重複觸發。
	if _is_creating_save:
		return false

	if SceneTransition.is_transitioning:
		return false

	# 再次確認欄位仍是空白。
	if (
		SaveManager.get_slot_state(slot_id)
		!= SaveManager.SlotState.EMPTY
	):

		push_warning(
			"【夢境紀錄】第 %02d 格不再是空白，停止建立"
			% slot_id
		)

		return false

	_is_creating_save = true

	# 正式建立並寫入存檔。
	var success: bool = (
		SaveManager.create_new_game(slot_id)
	)

	_is_creating_save = false

	# 建立失敗時，不進入遊戲世界。
	if not success:

		push_warning(
			"【夢境紀錄】建立失敗，請檢查 SaveManager 輸出"
		)

		return false

	if debug_log:

		print(
			"【夢境紀錄】成功建立第 %02d 格"
			% slot_id
		)

	return true


# ============================================================
# 20. 統一發送遊戲進場要求
#
# V7 核心新增功能。
#
# 不論是新遊戲建立成功，
# 或是選擇已有存檔，
# 皆使用 MenuActions 原本的 SaveSlotXX 介面。
#
# 不另外建立新遊戲轉場管理器。
# 不直接呼叫 SceneTransition。
# ============================================================

func _request_world_entry(slot_id: int) -> void:

	if SceneTransition.is_transitioning:
		return

	# 確認磁碟上已有正常存檔。
	if (
		SaveManager.get_slot_state(slot_id)
		!= SaveManager.SlotState.READY
	):

		push_warning(
			"【夢境紀錄】Slot %02d 不符合進場條件"
			% slot_id
		)

		return

	if debug_log:

		print(
			"【夢境紀錄】提出 Slot %02d 進場要求"
			% slot_id
		)

	# 交給既有 MenuActions 處理。
	#
	# SaveSlot01
	# SaveSlot02
	# SaveSlot03
	# SaveSlot04

	option_requested.emit(
		StringName(
			"SaveSlot%02d" % slot_id
		)
	)


# ============================================================
# 21. 取消確認視窗
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
# 22. 共用確認音效
#
# 保留 MenuActions 的原有訊號介面。
# ============================================================

func _on_dialog_sound_requested() -> void:

	option_requested.emit(&"Confirm")


# ============================================================
# 23. 取得指定存檔欄位
# ============================================================

func get_slot(slot_id: int) -> SaveSlotRow:

	return _slots.get(slot_id) as SaveSlotRow

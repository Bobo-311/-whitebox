
extends MainMenuPage
class_name SaveSelectPage

# ============================================================
# 《眠境 RE:RECOLOR》
# 夢境紀錄選擇頁面 V5｜正式存檔資料顯示
#
# Godot 4.5.1
#
# 功能：
# 1. 管理四個存檔欄位的 UI
# 2. 從 SaveManager 讀取真實存檔摘要
# 3. 顯示空白、正常、可復原、損壞狀態
# 4. 將 Unix 時間轉為存檔顯示日期
# 5. 監聽存檔建立、讀取及更新訊號
# 6. 保留開始新遊戲確認視窗
# 7. 保留清除紀錄確認視窗
# 8. 防止損壞存檔被誤認為空白存檔
# 9. 保留共用音效及原有頁面訊號
#
# 重要：
# 本版本移除全部假存檔預覽功能。
#
# 本階段只讀取與顯示資料，
# 不會建立、更新或刪除任何存檔檔案。
# ============================================================


# ============================================================
# 1. 基本常數
# ============================================================

const SLOT_COUNT: int = 4


# ============================================================
# 2. 確認視窗種類
# ============================================================

enum DialogKind {
	NEW_GAME,
	DELETE_SAVE
}


# ============================================================
# 3. Inspector 設定
# ============================================================

@export_group("確認視窗")

## 指定目前共用的 confirm_dialog.tscn
@export var confirm_dialog_scene: PackedScene


@export_group("除錯設定")

## 是否輸出存檔欄位與操作訊息
@export var debug_log: bool = false


# ============================================================
# 4. 節點引用
# ============================================================

@onready var slots_container: VBoxContainer = $Slots


# ============================================================
# 5. 內部資料
# ============================================================

## 欄位編號 → SaveSlotRow 節點
var _slots: Dictionary[int, SaveSlotRow] = {}

## 目前開啟的確認視窗
var _active_dialog: ConfirmDialog = null


# ============================================================
# 6. 頁面初始化
# ============================================================

func _ready() -> void:

	# 保留 MainMenuPage 的返回按鈕等功能
	super._ready()

	# 初始化四格存檔欄位
	_setup_slots()

	# 監聽全域存檔資料變動
	_connect_save_manager_signals()

	# 從真正的存檔資料建立 UI
	_refresh_all_slots()


# ============================================================
# 7. 初始化四格存檔欄位
# ============================================================

func _setup_slots() -> void:

	_slots.clear()

	for slot_id in range(1, SLOT_COUNT + 1):

		var node_name: String = (
			"Slot%02d" % slot_id
		)

		var row: SaveSlotRow = (
			slots_container.get_node_or_null(
				node_name
			) as SaveSlotRow
		)

		if row == null:

			push_error(
				"【夢境紀錄】找不到存檔欄位："
				+ node_name
			)

			continue

		# 設定欄位編號
		row.set_slot_id(slot_id)

		# 保存引用
		_slots[slot_id] = row

		# 玩家點擊存檔欄位
		row.slot_selected.connect(
			_on_slot_selected
		)

		# 玩家點擊清除紀錄
		row.delete_requested.connect(
			_on_delete_requested
		)

		# 保留原本 Hover 音效
		row.hover_requested.connect(
			_on_hover
		)

		if debug_log:

			print(
				"【夢境紀錄】欄位初始化：",
				node_name
			)


# ============================================================
# 8. 連接 SaveManager 訊號
#
# 未來在遊戲內建立或儲存紀錄時，
# 如果此頁面仍存在，
# 就能自動更新對應的存檔欄位。
#
# 不需要每一幀持續讀取硬碟。
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


# ============================================================
# 9. 更新全部存檔欄位
#
# 每次進入夢境紀錄頁面時執行一次。
# ============================================================

func _refresh_all_slots() -> void:

	for slot_id in range(1, SLOT_COUNT + 1):

		_refresh_slot(slot_id)


# ============================================================
# 10. 依 SaveManager 資料更新指定欄位
#
# UI 不直接讀取磁碟檔案。
#
# 所有存檔資料透過 SaveManager
# 的 get_slot_summary() 取得。
# ============================================================

func _refresh_slot(slot_id: int) -> void:

	var row: SaveSlotRow = get_slot(slot_id)

	if row == null:
		return

	# 取得真實存檔摘要
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

		SaveManager.SlotState.EMPTY:

			# 沒有存檔
			# 顯示開始新的夢境
			row.show_empty()

			_set_row_interaction(
				row,
				true,
				false
			)

		SaveManager.SlotState.READY:

			# 有效存檔
			# 顯示真實地圖、遊玩時間、日期
			_show_saved_summary(
				row,
				summary
			)

			_set_row_interaction(
				row,
				true,
				true
			)

		SaveManager.SlotState.RECOVERABLE:

			# 主要檔案無效，但備份有效
			# 保留資料供後續復原
			_show_saved_summary(
				row,
				summary
			)

			_set_row_warning(
				row,
				"可從備份復原"
			)

			# 尚未實作備份復原流程
			# 暫時禁止讀取或刪除
			_set_row_interaction(
				row,
				false,
				false
			)

		SaveManager.SlotState.DAMAGED:

			# 存檔損壞或版本不相容
			# 絕對不能視為空白存檔
			_show_damaged_slot(row)

		_:

			# 未知狀態採取保守處理
			_show_damaged_slot(row)

	if debug_log:

		print(
			"【夢境紀錄】更新 Slot %02d，狀態：%d"
			% [slot_id, state]
		)


# ============================================================
# 11. 顯示正常存檔摘要
#
# 使用 SaveSlotRow 原本的 show_saved()
# 不修改原本的 Skin、字型及排版。
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
		int(
			summary.get(
				"play_seconds",
				0.0
			)
		),
		0
	)

	var saved_timestamp: int = int(
		summary.get(
			"updated_at_unix",
			0
		)
	)

	var saved_date: String = (
		_format_save_date(
			saved_timestamp
		)
	)

	# 沿用原本已有的存檔顯示方法
	row.show_saved(
		map_name,
		play_seconds,
		saved_date
	)


# ============================================================
# 12. 轉換存檔日期
#
# SaveManager 儲存 Unix UTC 時間戳記。
#
# 這裡換算為電腦目前設定的本地時區日期，
# 讓 UI 顯示 YYYY/MM/DD。
#
# 注意：
# 目前是按系統當下的 UTC 偏移計算。
# 對台灣時區適用；若未來支援跨 DST 的
# 歷史日期顯示，可再加入時區資料庫處理。
# ============================================================

func _format_save_date(
	unix_timestamp: int
) -> String:

	if unix_timestamp <= 0:

		return "未知日期"

	var time_zone: Dictionary = (
		Time.get_time_zone_from_system()
	)

	var bias_minutes: int = int(
		time_zone.get("bias", 0)
	)

	var local_timestamp: int = (
		unix_timestamp
		+ bias_minutes * 60
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
# 13. 顯示「可從備份復原」狀態
#
# 為保留目前已完成的 SaveSlotRow 動畫，
# 這裡只更改說明文字。
#
# 不修改任何場景節點的位置或大小。
#
# TODO：
# 未來製作備份復原介面時，
# 再將此狀態移至 SaveSlotRow 的公開方法。
# ============================================================

func _set_row_warning(
	row: SaveSlotRow,
	message: String
) -> void:

	var detail_label: Label = (
		row.get_node_or_null(
			"Actions/SlotButton/SlotContent/"
			+ "InfoRow/InfoColumn/DetailLabel"
		) as Label
	)

	if detail_label != null:

		detail_label.text = message


# ============================================================
# 14. 顯示損壞存檔
#
# 不允許損壞檔案被誤判為 NEW GAME。
#
# 不自動覆寫或刪除任何檔案。
# ============================================================

func _show_damaged_slot(
	row: SaveSlotRow
) -> void:

	# 先恢復基本顯示結構
	row.show_empty()

	# 正確標記為異常狀態
	row.slot_state = (
		SaveSlotRow.SlotState.DAMAGED
	)

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

	# 禁止點擊存檔
	# 禁止直接刪除
	_set_row_interaction(
		row,
		false,
		false
	)


# ============================================================
# 15. 控制欄位是否允許操作
#
# 這裡只控制 Button 的 disabled，
# 不改動原本的 Layout 或 Skin。
#
# EMPTY：
# 可以點擊開始夢境，但沒有刪除功能。
#
# READY：
# 可以選擇存檔或開啟清除確認視窗。
#
# RECOVERABLE / DAMAGED：
# 暫時禁止操作，保護檔案。
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

		slot_button.disabled = (
			not slot_enabled
		)

	if delete_button != null:

		delete_button.disabled = (
			not delete_enabled
		)


# ============================================================
# 16. SaveManager 資料變動通知
#
# 只更新發生變動的欄位。
# ============================================================

func _on_save_slot_changed(
	slot_id: int
) -> void:

	_refresh_slot(slot_id)


# ============================================================
# 17. 玩家點擊存檔欄位
#
# 必須重新確認磁碟上的存檔狀態，
# 不能只相信 UI 顯示。
# ============================================================

func _on_slot_selected(
	slot_id: int
) -> void:

	if not _slots.has(slot_id):
		return

	if is_instance_valid(_active_dialog):
		return

	var state: int = (
		SaveManager.get_slot_state(
			slot_id
		)
	)

	match state:

		SaveManager.SlotState.EMPTY:

			# 空白存檔：
			# 開啟新遊戲確認視窗
			_open_slot_dialog(
				slot_id,
				DialogKind.NEW_GAME
			)

		SaveManager.SlotState.READY:

			# 有效存檔：
			# 保留原本對 MenuActions 的訊號
			#
			# TODO：
			# 下一階段接上正式讀檔流程。
			option_requested.emit(
				StringName(
					"SaveSlot%02d" % slot_id
				)
			)

		_:

			# 異常或可復原欄位
			# 不允許啟動新遊戲
			_refresh_slot(slot_id)

			if debug_log:

				print(
					"【夢境紀錄】欄位不可操作：",
					slot_id
				)


# ============================================================
# 18. 玩家點擊「清除紀錄」
#
# 只有正常存檔才允許開啟清除確認。
#
# 此階段確認後仍不會刪除任何檔案。
# ============================================================

func _on_delete_requested(
	slot_id: int
) -> void:

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
# 19. 建立共用確認視窗
#
# 沿用前一版已完成的 ConfirmDialog。
#
# 不修改：
# - 視窗 Skin
# - 按鈕 Hover
# - 確認視窗動畫
# - 主選單音效路由
# ============================================================

func _open_slot_dialog(
	slot_id: int,
	kind: DialogKind
) -> void:

	if is_instance_valid(_active_dialog):
		return

	if confirm_dialog_scene == null:

		push_error(
			"【夢境紀錄】尚未指定確認視窗場景"
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
			"【夢境紀錄】確認視窗根節點腳本錯誤"
		)

		return

	# --------------------------------------------------------
	# 設定不同操作的提示文字
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
	# 保留音效訊號
	# --------------------------------------------------------

	dialog.hover_requested.connect(
		_on_hover
	)

	dialog.confirm_sound_requested.connect(
		_on_dialog_sound_requested
	)

	# --------------------------------------------------------
	# 確認與取消訊號
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

	_active_dialog = dialog

	# --------------------------------------------------------
	# 顯示在目前頁面最上層
	# --------------------------------------------------------

	add_child(dialog)

	dialog.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	dialog.move_to_front()

	# 保留原本音效路由
	_on_dialog_sound_requested()

	if debug_log:

		print(
			"【夢境紀錄】開啟確認視窗：",
			slot_id,
			"，類型：",
			kind
		)


# ============================================================
# 20. 玩家確認操作
#
# 目前只記錄操作結果。
#
# 注意：
# 絕對不在本階段呼叫 SaveManager.create_slot()
# 或執行真正刪除。
# ============================================================

func _on_dialog_confirmed(
	slot_id: int,
	kind: DialogKind
) -> void:

	_active_dialog = null

	match kind:

		DialogKind.NEW_GAME:

			if debug_log:

				print(
					"【UI 測試】確認開始第 ",
					slot_id,
					" 格的新夢境"
				)

			# TODO：
			# STEP 10.3 接上建立新存檔。

		DialogKind.DELETE_SAVE:

			if debug_log:

				print(
					"【UI 測試】確認清除第 ",
					slot_id,
					" 格夢境紀錄"
				)

			# TODO：
			# 後續加入正式刪除存檔功能。

	# 確保畫面反映真實磁碟狀態
	_refresh_slot(slot_id)


# ============================================================
# 21. 玩家取消操作
# ============================================================

func _on_dialog_cancelled(
	slot_id: int,
	kind: DialogKind
) -> void:

	_active_dialog = null

	if debug_log:

		print(
			"【夢境紀錄】取消操作：",
			slot_id,
			"，類型：",
			kind
		)


# ============================================================
# 22. 共用確認音效請求
#
# 保留原本的 MenuActions 接口。
# ============================================================

func _on_dialog_sound_requested() -> void:

	option_requested.emit(&"Confirm")


# ============================================================
# 23. 取得指定存檔欄位
# ============================================================

func get_slot(
	slot_id: int
) -> SaveSlotRow:

	return _slots.get(slot_id) as SaveSlotRow

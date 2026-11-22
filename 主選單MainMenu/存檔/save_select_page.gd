extends MainMenuPage
class_name SaveSelectPage

# ============================================================
# 《眠境 RE:RECOLOR》夢境紀錄選擇頁面
#
# 負責：
# 1. 管理四個獨立存檔欄位
# 2. 轉發存檔選擇訊號
# 3. 轉發存檔刪除請求
# 4. 共用主選單音效系統
# 5. 提供存檔資料更新介面
# 6. 開發階段 UI 外觀預覽
#
# 不負責：
# - 直接讀寫存檔文件
# - 直接切換遊戲地圖
# - 直接修改玩家資料
# ============================================================


# ============================================================
# 基礎設定
# ============================================================

## 存檔欄位總數
const SLOT_COUNT: int = 4


# ============================================================
# Inspector 設定
# ============================================================

@export_group("除錯設定")

## 是否輸出操作紀錄
@export var debug_log: bool = false


@export_group("介面測試")

# TODO：正式接上 SaveManager 後移除此設定

## 僅供開發階段預覽存檔介面
## 0 = 關閉預覽
## 1～4 = 指定預覽欄位
@export_range(0, 4)
var preview_slot_id: int = 0


# ============================================================
# 節點引用
# ============================================================

@onready var slots_container: VBoxContainer = $Slots


# ============================================================
# 內部資料
#
# Key：存檔編號
# Value：SaveSlotRow 節點
# ============================================================

var _slots: Dictionary[int, SaveSlotRow] = {}


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 執行共用頁面初始化
	# 保留返回按鈕及共用音效功能
	super._ready()

	# 初始化四個存檔欄位
	_setup_slots()

	# TODO：正式接上 SaveManager 後移除此行
	_apply_debug_preview()


# ============================================================
# 初始化存檔欄位
# ============================================================

func _setup_slots() -> void:

	_slots.clear()

	for slot_id in range(1, SLOT_COUNT + 1):

		# 依序取得 Slot01～Slot04
		var node_name: String = "Slot%02d" % slot_id

		var row := slots_container.get_node_or_null(
			node_name
		) as SaveSlotRow

		# 防止節點遺失或類型錯誤
		if row == null:

			push_error(
				"【夢境紀錄】找不到存檔欄位：" + node_name
			)

			continue

		# 確保存檔編號正確
		row.set_slot_id(slot_id)

		# 登記存檔欄位
		_slots[slot_id] = row

		# 連接存檔選擇訊號
		row.slot_selected.connect(
			_on_slot_selected
		)

		# 連接刪除請求訊號
		row.delete_requested.connect(
			_on_delete_requested
		)

		# 共用主選單懸停音效
		row.hover_requested.connect(
			_on_hover
		)

		if debug_log:

			print(
				"【夢境紀錄】完成欄位初始化：",
				node_name
			)


# ============================================================
# 選擇存檔
# ============================================================

func _on_slot_selected(slot_id: int) -> void:

	# 確認存檔編號有效
	if not _slots.has(slot_id):
		return

	if debug_log:

		print(
			"【夢境紀錄】選擇存檔：",
			slot_id
		)

	# 通知主選單管理器
	# 例如 SaveSlot01、SaveSlot02
	option_requested.emit(
		StringName("SaveSlot%02d" % slot_id)
	)


# ============================================================
# 刪除存檔請求
#
# 目前僅發送請求
# 不會直接刪除任何存檔
# ============================================================

func _on_delete_requested(slot_id: int) -> void:

	# 確認存檔編號有效
	if not _slots.has(slot_id):
		return

	if debug_log:

		print(
			"【夢境紀錄】請求刪除存檔：",
			slot_id
		)

	# 通知主選單管理器
	# 未來接入刪除確認視窗
	option_requested.emit(
		StringName("DeleteSlot%02d" % slot_id)
	)


# ============================================================
# 取得指定存檔欄位
#
# 提供未來 SaveManager 更新介面使用
# ============================================================

func get_slot(slot_id: int) -> SaveSlotRow:

	return _slots.get(slot_id) as SaveSlotRow


# ============================================================
# 開發專用 UI 預覽
#
# TODO：正式接上 SaveManager 後完整移除此函式
#
# 注意：
# 1. 以下資料皆為美術測試用假資料
# 2. 不建立任何存檔文件
# 3. 不修改玩家真實紀錄
# 4. Release 版本不執行
# ============================================================

func _apply_debug_preview() -> void:

	# 僅允許 Debug 版本使用
	if not OS.is_debug_build():
		return

	# 0 代表關閉預覽
	if preview_slot_id == 0:
		return

	# 取得指定的預覽欄位
	var row := get_slot(preview_slot_id)

	if row == null:
		return

	# --------------------------------------------------------
	# 測試資料
	# --------------------------------------------------------

	row.show_saved(
		"最初之地・櫻花庭園",
		9378,
		"2026/11/23"
	)

	if debug_log:

		print(
			"【UI 測試】目前預覽欄位：",
			preview_slot_id,
			"（非真實存檔）"
		)

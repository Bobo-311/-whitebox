extends Control
class_name SaveSlotRow

# ============================================================
# 《眠境 RE:RECOLOR》單一存檔欄位控制器 V2
#
# 負責：
# 1. 存檔欄位資訊顯示
# 2. 空白、已有存檔、損毀三種狀態
# 3. C 款琉璃夢羽造型
# 4. B 款月光薄紗選取特效
# 5. 平滑高亮與月光呼吸動畫
# 6. 滑鼠、鍵盤及控制器操作
# 7. 發送操作與音效請求
#
# 不負責：
# - 實際讀寫存檔
# - 切換遊戲場景
# - 直接刪除存檔文件
# ============================================================


# ============================================================
# 對外訊號
# ============================================================

signal slot_selected(slot_id: int)
signal delete_requested(slot_id: int)
signal hover_requested


# ============================================================
# 存檔狀態
# ============================================================

enum SlotState {
	EMPTY,
	OCCUPIED,
	DAMAGED
}

var slot_state: SlotState = SlotState.EMPTY


# ============================================================
# Inspector 設定
# ============================================================

@export_group("存檔設定")

## 存檔欄位編號
@export_range(1, 4)
var slot_id: int = 1

## 是否輸出除錯訊息
@export var debug_log: bool = false


@export_group("Skin 外觀")

## 自訂基礎造型
## 留空時使用 Skin 節點指定的圖片
@export var skin_override: Texture2D

## 一般狀態的 Skin 顏色
@export var normal_tint: Color = Color(
	1.0, 1.0, 1.0, 0.72
)

## 選取狀態的 Skin 顏色
@export var hover_tint: Color = Color.WHITE

## 一般狀態的文字透明度
@export_range(0.0, 1.0)
var normal_text_opacity: float = 0.85

## 選取狀態的文字透明度
@export_range(0.0, 1.0)
var hover_text_opacity: float = 1.0


@export_group("高亮動畫")

## 選取與取消選取的動畫時間
@export_range(0.05, 1.0, 0.01)
var hover_duration: float = 0.25


@export_group("月光薄紗")

## 選取時的薄紗基礎透明度
@export_range(0.0, 1.0, 0.01)
var hover_glow_opacity: float = 0.35

## 是否啟用月光呼吸
@export var breathing_enabled: bool = true

## 呼吸動畫的透明度變化幅度
@export_range(0.0, 0.2, 0.01)
var breathing_strength: float = 0.04

## 完成一次呼吸動畫所需時間
@export_range(0.5, 10.0, 0.1)
var breathing_cycle: float = 3.6


# ============================================================
# 節點引用
# ============================================================

@onready var skin: TextureRect = $Skin

@onready var hover_glow: TextureRect = $HoverGlow

@onready var actions: HBoxContainer = $Actions

@onready var slot_button: Button = \
	$Actions/SlotButton

@onready var delete_button: Button = \
	$Actions/DeleteButton

@onready var slot_content: MarginContainer = \
	$Actions/SlotButton/SlotContent

@onready var number_label: Label = \
	$Actions/SlotButton/SlotContent/InfoRow/NumberLabel

@onready var map_name_label: Label = \
	$Actions/SlotButton/SlotContent/InfoRow/InfoColumn/MapNameLabel

@onready var detail_label: Label = \
	$Actions/SlotButton/SlotContent/InfoRow/InfoColumn/DetailLabel


# ============================================================
# 動畫內部變數
# ============================================================

## 目前選取動畫進度
var _highlight: float = 0.0

## 動畫目標進度
var _target_highlight: float = 0.0

## 高亮動畫 Tween
var _hover_tween: Tween

## 呼吸動畫累積時間
var _breath_time: float = 0.0

# 所有 SaveSlotRow 共用操作模式
#
# false：依照滑鼠停留位置
# true：依照鍵盤或控制器焦點
#
# 避免四個欄位各自判斷不同的操作模式
static var _keyboard_mode: bool = false


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	_setup_skin()

	_setup_hover_glow()

	_setup_buttons()

	_connect_signals()

	# 初始化一般狀態
	_apply_highlight(0.0)

	# 尚未接上 SaveManager
	# 暫時維持所有欄位為空白
	show_empty()


# ============================================================
# 基礎 Skin 設定
# ============================================================

func _setup_skin() -> void:

	if skin_override != null:
		skin.texture = skin_override

	# 裝飾圖片不攔截滑鼠
	skin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 不影響欄位最小尺寸
	skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# 保持素材比例
	skin.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)


# ============================================================
# 月光薄紗初始化
# ============================================================

func _setup_hover_glow() -> void:

	# 特效圖片不得攔截按鈕
	hover_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hover_glow.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	hover_glow.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	# 保留 Inspector 設定的 RGB 顏色
	# 啟動時只將透明度歸零
	hover_glow.modulate.a = 0.0


# ============================================================
# 按鈕設定
# ============================================================

func _setup_buttons() -> void:

	var empty_style := StyleBoxEmpty.new()

	for button in [
		slot_button,
		delete_button
	]:

		button.flat = true

		button.focus_mode = Control.FOCUS_ALL

		# 移除 Godot 預設底框
		for style_name in [
			"normal",
			"hover",
			"pressed",
			"hover_pressed",
			"disabled",
			"focus"
		]:

			button.add_theme_stylebox_override(
				style_name,
				empty_style
			)

	# 刪除按鈕使用柔和警示色
	delete_button.add_theme_color_override(
		"font_hover_color",
		Color("#FFB6C8")
	)

	delete_button.add_theme_color_override(
		"font_focus_color",
		Color("#FFB6C8")
	)

	# 避免文字及排版容器攔截滑鼠
	_ignore_mouse_recursive(slot_content)


# ============================================================
# 排除文字節點的滑鼠攔截
# ============================================================

func _ignore_mouse_recursive(node: Node) -> void:

	if node is Control:

		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in node.get_children():

		_ignore_mouse_recursive(child)


# ============================================================
# 訊號連接
# ============================================================

func _connect_signals() -> void:

	slot_button.pressed.connect(
		_on_slot_pressed
	)

	delete_button.pressed.connect(
		_on_delete_pressed
	)

	for button in [
		slot_button,
		delete_button
	]:

		button.mouse_entered.connect(
			_on_button_hover.bind(button)
		)

		button.focus_entered.connect(
			_on_button_focus.bind(button)
		)


# ============================================================
# 更新動畫
# ============================================================

func _process(delta: float) -> void:

	if not is_visible_in_tree():
		return

	# 每幀確認目前實際選取的欄位
	# 只有目標狀態發生改變時才建立 Tween
	_refresh_highlight()

	# --------------------------------------------------------
	# 更新月光呼吸
	# --------------------------------------------------------

	if breathing_enabled and _highlight > 0.0:

		_breath_time = fposmod(
			_breath_time + delta,
			maxf(breathing_cycle, 0.5)
		)

	else:

		_breath_time = 0.0

	_update_hover_glow()


# ============================================================
# 更新存檔編號
# ============================================================

func set_slot_id(new_id: int) -> void:

	slot_id = clampi(new_id, 1, 4)

	if is_instance_valid(number_label):

		number_label.text = "%02d" % slot_id


# ============================================================
# 狀態一：空白存檔
# ============================================================

func show_empty() -> void:

	slot_state = SlotState.EMPTY

	number_label.text = "%02d" % slot_id

	map_name_label.text = "開始新的夢境"

	detail_label.text = "N E W   G A M E"

	slot_button.disabled = false

	slot_button.focus_mode = Control.FOCUS_ALL

	_set_delete_available(false)

	_refresh_highlight()


# ============================================================
# 狀態二：已有存檔
#
# 未來由 SaveManager 傳入真實存檔資料
# ============================================================

func show_saved(
	map_name: String,
	play_seconds: int,
	saved_date: String
) -> void:

	slot_state = SlotState.OCCUPIED

	number_label.text = "%02d" % slot_id

	# 最後一次互動畫架所在的地圖
	map_name_label.text = map_name

	detail_label.text = "%s　｜　%s" % [
		_format_play_time(play_seconds),
		saved_date
	]

	slot_button.disabled = false

	slot_button.focus_mode = Control.FOCUS_ALL

	_set_delete_available(true)

	_refresh_highlight()


# ============================================================
# 狀態三：存檔損毀
# ============================================================

func show_damaged() -> void:

	slot_state = SlotState.DAMAGED

	number_label.text = "%02d" % slot_id

	map_name_label.text = "紀錄無法讀取"

	detail_label.text = "此存檔可能已損毀"

	slot_button.disabled = true

	slot_button.focus_mode = Control.FOCUS_NONE

	_set_delete_available(true)

	_refresh_highlight()


# ============================================================
# 刪除按鈕控制
# ============================================================

func _set_delete_available(available: bool) -> void:

	delete_button.disabled = not available

	# 不使用 hide()
	# 保留 HBoxContainer 的排列空間
	delete_button.modulate.a = (
		1.0 if available else 0.0
	)

	delete_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if available
		else Control.MOUSE_FILTER_IGNORE
	)

	delete_button.focus_mode = (
		Control.FOCUS_ALL
		if available
		else Control.FOCUS_NONE
	)


# ============================================================
# 遊玩時間格式化
#
# 例如：9378 秒 → 02:36:18
# ============================================================

func _format_play_time(seconds: int) -> String:

	seconds = maxi(seconds, 0)

	var hours: int = floori(seconds / 3600.0)

	var minutes: int = floori(
		(seconds % 3600) / 60.0
	)

	var remaining_seconds: int = seconds % 60

	return "%02d:%02d:%02d" % [
		hours,
		minutes,
		remaining_seconds
	]


# ============================================================
# 滑鼠、鍵盤及控制器操作模式
# ============================================================

func _input(event: InputEvent) -> void:

	if not is_visible_in_tree():
		return

	# 滑鼠操作
	if (
		event is InputEventMouseMotion
		or event is InputEventMouseButton
	):

		_keyboard_mode = false

	# 鍵盤或控制器操作
	elif (
		event is InputEventKey
		or event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	):

		if (
			event.is_action_pressed("ui_up")
			or event.is_action_pressed("ui_down")
			or event.is_action_pressed("ui_left")
			or event.is_action_pressed("ui_right")
			or event.is_action_pressed("ui_accept")
			or event.is_action_pressed("ui_focus_next")
			or event.is_action_pressed("ui_focus_prev")
		):

			_keyboard_mode = true


# ============================================================
# 滑鼠懸停音效
# ============================================================

func _on_button_hover(button: Button) -> void:

	if button.disabled:
		return

	# 鍵盤模式不播放滑鼠懸停音效
	if _keyboard_mode:
		return

	hover_requested.emit()


# ============================================================
# 鍵盤焦點音效
# ============================================================

func _on_button_focus(button: Button) -> void:

	if button.disabled:
		return

	# 滑鼠模式已處理 Hover 音效
	# 避免點擊時重複播放
	if not _keyboard_mode:
		return

	hover_requested.emit()


# ============================================================
# 判斷目前實際選取的欄位
# ============================================================

func _refresh_highlight() -> void:

	var active: bool = false

	if _keyboard_mode:

		# Viewport 只有一個目前的焦點節點
		var focused: Control = (
			get_viewport().gui_get_focus_owner()
		)

		active = (
			(focused == slot_button
			and not slot_button.disabled)

			or

			(focused == delete_button
			and not delete_button.disabled)
		)

	else:

		# 取得滑鼠實際停留的 UI 節點
		var hovered: Control = (
			get_viewport().gui_get_hovered_control()
		)

		active = (
			(hovered == slot_button
			and not slot_button.disabled)

			or

			(hovered == delete_button
			and not delete_button.disabled)
		)

	var target: float = 1.0 if active else 0.0

	_play_highlight(target)


# ============================================================
# 播放選取淡入淡出動畫
# ============================================================

func _play_highlight(target: float) -> void:

	# 避免每幀重複建立 Tween
	if is_equal_approx(
		_target_highlight,
		target
	):
		return

	_target_highlight = target

	# 快速切換欄位時中止舊動畫
	if _hover_tween and _hover_tween.is_valid():

		_hover_tween.kill()

	_hover_tween = create_tween()

	_hover_tween.set_trans(Tween.TRANS_SINE)

	_hover_tween.set_ease(Tween.EASE_IN_OUT)

	_hover_tween.tween_method(
		_apply_highlight,
		_highlight,
		target,
		hover_duration
	)


# ============================================================
# 更新 Skin 及文字動畫
# ============================================================

func _apply_highlight(value: float) -> void:

	_highlight = clampf(value, 0.0, 1.0)

	# 琉璃羽飾由一般狀態漸亮
	skin.self_modulate = normal_tint.lerp(
		hover_tint,
		_highlight
	)

	# 文字同步漸亮
	slot_content.modulate.a = lerpf(
		normal_text_opacity,
		hover_text_opacity,
		_highlight
	)

	# 同步更新月光薄紗
	_update_hover_glow()


# ============================================================
# 更新月光薄紗及左右星光
# ============================================================

func _update_hover_glow() -> void:

	# 一般狀態完全透明
	if _highlight <= 0.0:

		hover_glow.modulate.a = 0.0

		return

	var breath: float = 0.0

	# --------------------------------------------------------
	# 計算緩慢呼吸效果
	# --------------------------------------------------------

	if breathing_enabled:

		var phase: float = (
			_breath_time
			/ maxf(breathing_cycle, 0.5)
		) * TAU

		breath = sin(phase) * breathing_strength

	# --------------------------------------------------------
	# 計算最終透明度
	#
	# 同時受到：
	# 1. 選取動畫進度
	# 2. 基礎透明度
	# 3. 呼吸動畫影響
	# --------------------------------------------------------

	hover_glow.modulate.a = clampf(
		_highlight * (
			hover_glow_opacity + breath
		),
		0.0,
		1.0
	)


# ============================================================
# 選擇存檔欄位
# ============================================================

func _on_slot_pressed() -> void:

	if slot_button.disabled:
		return

	if debug_log:

		print(
			"【存檔介面】選擇欄位：",
			slot_id
		)

	slot_selected.emit(slot_id)


# ============================================================
# 請求刪除存檔
#
# 目前只發送訊號
# 不會真的刪除任何存檔
# ============================================================

func _on_delete_pressed() -> void:

	if slot_state == SlotState.EMPTY:
		return

	if delete_button.disabled:
		return

	if debug_log:

		print(
			"【存檔介面】請求刪除欄位：",
			slot_id
		)

	delete_requested.emit(slot_id)

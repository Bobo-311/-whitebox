extends Control
class_name ConfirmDialog

# ============================================================
# 《眠境 RE:RECOLOR》共用確認視窗控制器 V2
#
# 功能：
# 1. 自訂標題、訊息及按鈕文字
# 2. 背景淡入與淡出
# 3. 視窗柔和縮放動畫
# 4. 滑鼠 Hover 動畫
# 5. 確認及取消操作
# 6. Esc 關閉視窗
# 7. 阻擋背景介面的鍵盤操作
# 8. 關閉後恢復原本的按鈕焦點
#
# 本視窗不負責實際刪除或讀寫存檔
# ============================================================


# ============================================================
# 對外訊號
# ============================================================

signal confirmed
signal cancelled
signal hover_requested
signal confirm_sound_requested


# ============================================================
# 視窗狀態
# ============================================================

enum DialogState {
	OPENING,
	OPEN,
	CLOSING
}

var _state: DialogState = DialogState.OPENING


# ============================================================
# Inspector 設定
# ============================================================

@export_group("動畫設定")

## 視窗開啟動畫時間
@export_range(0.05, 1.0, 0.01)
var open_duration: float = 0.25

## 視窗關閉動畫時間
@export_range(0.05, 1.0, 0.01)
var close_duration: float = 0.18

## 視窗初始縮放倍率
@export_range(0.8, 1.0, 0.01)
var initial_scale: float = 0.95


@export_group("除錯設定")

## 是否輸出除錯訊息
@export var debug_log: bool = false


# ============================================================
# 節點引用
# ============================================================

@onready var dialog_panel: Panel = $DialogPanel

@onready var cancel_button: Button = \
	$DialogPanel/Actions/CancelButton

@onready var confirm_button: Button = \
	$DialogPanel/Actions/ConfirmButton


# ============================================================
# 內部變數
# ============================================================

var _animation_tween: Tween

# 記錄開啟確認視窗前的按鈕焦點
var _previous_focus: Control


# ============================================================
# 自訂確認視窗內容
#
# 必須在 add_child() 以前呼叫
# 讓按鈕動畫正確取得文字內容
# ============================================================

func configure(
	title_text: String,
	message_text: String,
	hint_text: String,
	confirm_text: String,
	cancel_text: String = "取消"
) -> void:

	if is_inside_tree():

		push_warning(
			"【確認視窗】請在加入場景前設定視窗內容"
		)

		return

	$DialogPanel/Title.text = title_text

	$DialogPanel/Message.text = message_text

	$DialogPanel/Hint.text = hint_text

	$DialogPanel/Actions/ConfirmButton.text = confirm_text

	$DialogPanel/Actions/CancelButton.text = cancel_text


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 記錄原本背景介面的焦點
	_previous_focus = get_viewport().gui_get_focus_owner()

	# 暫時釋放背景按鈕焦點
	if is_instance_valid(_previous_focus):

		_previous_focus.release_focus()

	# 阻擋滑鼠穿透確認視窗
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 設定視窗縮放中心
	dialog_panel.pivot_offset = dialog_panel.size * 0.5

	_setup_focus()

	_connect_signals()

	_play_open_animation()


# ============================================================
# 焦點設定
#
# 此視窗目前僅使用滑鼠選取按鈕
# 不使用左右方向鍵及預設焦點
# ============================================================

func _setup_focus() -> void:

	cancel_button.focus_mode = Control.FOCUS_NONE

	confirm_button.focus_mode = Control.FOCUS_NONE


# ============================================================
# 連接按鈕訊號
# ============================================================

func _connect_signals() -> void:

	cancel_button.pressed.connect(
		_on_cancel_pressed
	)

	confirm_button.pressed.connect(
		_on_confirm_pressed
	)

	cancel_button.mouse_entered.connect(
		_on_hover
	)

	confirm_button.mouse_entered.connect(
		_on_hover
	)


# ============================================================
# 播放視窗開啟動畫
# ============================================================

func _play_open_animation() -> void:

	_state = DialogState.OPENING

	# 動畫尚未完成前禁止按鈕操作
	_set_buttons_enabled(false)

	# 初始透明及縮放狀態
	modulate.a = 0.0

	dialog_panel.scale = (
		Vector2.ONE * initial_scale
	)

	# 建立開啟動畫
	_animation_tween = create_tween()

	_animation_tween.set_parallel(true)

	_animation_tween.set_trans(Tween.TRANS_SINE)

	_animation_tween.set_ease(Tween.EASE_OUT)

	# 背景及視窗逐漸浮現
	_animation_tween.tween_property(
		self,
		"modulate:a",
		1.0,
		open_duration
	)

	# 視窗柔和放大
	_animation_tween.tween_property(
		dialog_panel,
		"scale",
		Vector2.ONE,
		open_duration
	)

	await _animation_tween.finished

	# 開啟操作
	_state = DialogState.OPEN

	_set_buttons_enabled(true)

	# 不預設選取任何按鈕
	# 花藤只會在滑鼠懸停時顯示

	if debug_log:

		print("【確認視窗】視窗已開啟")


# ============================================================
# 播放視窗關閉動畫
# ============================================================

func _play_close_animation(
	is_confirmed: bool
) -> void:

	# 避免重複觸發關閉
	if _state != DialogState.OPEN:

		return

	_state = DialogState.CLOSING

	_set_buttons_enabled(false)

	# 發送確認音效請求
	confirm_sound_requested.emit()

	# 建立關閉動畫
	_animation_tween = create_tween()

	_animation_tween.set_parallel(true)

	_animation_tween.set_trans(Tween.TRANS_SINE)

	_animation_tween.set_ease(Tween.EASE_IN)

	# 整體逐漸淡出
	_animation_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		close_duration
	)

	# 視窗柔和縮小
	_animation_tween.tween_property(
		dialog_panel,
		"scale",
		Vector2.ONE * initial_scale,
		close_duration
	)

	await _animation_tween.finished

	hide()

	# 恢復背景介面原本的焦點
	if is_instance_valid(_previous_focus):

		if (
			_previous_focus.is_visible_in_tree()
			and _previous_focus.focus_mode != Control.FOCUS_NONE
		):

			_previous_focus.grab_focus()

	# 根據操作發送對應訊號
	if is_confirmed:

		if debug_log:

			print("【確認視窗】玩家已確認操作")

		confirmed.emit()

	else:

		if debug_log:

			print("【確認視窗】玩家已取消操作")

		cancelled.emit()

	# 動畫結束後釋放視窗
	queue_free()


# ============================================================
# 按鈕啟用狀態
# ============================================================

func _set_buttons_enabled(
	enabled: bool
) -> void:

	cancel_button.disabled = not enabled

	confirm_button.disabled = not enabled


# ============================================================
# 取消按鈕
# ============================================================

func _on_cancel_pressed() -> void:

	await _play_close_animation(false)


# ============================================================
# 確認按鈕
# ============================================================

func _on_confirm_pressed() -> void:

	await _play_close_animation(true)


# ============================================================
# 滑鼠懸停音效
# ============================================================

func _on_hover() -> void:

	if _state != DialogState.OPEN:

		return

	hover_requested.emit()


# ============================================================
# 鍵盤及控制器輸入
#
# 允許 Esc 關閉視窗
# 阻擋背景介面的選取及確認操作
# 不影響滑鼠操作
# ============================================================

func _input(event: InputEvent) -> void:

	if not is_visible_in_tree():

		return

	# 僅處理鍵盤及控制器事件
	if not (
		event is InputEventKey
		or event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	):

		return

	# Esc 或 ui_cancel 關閉視窗
	if event.is_action("ui_cancel"):

		get_viewport().set_input_as_handled()

		if (
			_state == DialogState.OPEN
			and event.is_action_pressed("ui_cancel")
		):

			_on_cancel_pressed()

		return

	# 視窗存在期間阻擋背景選單操作
	if (
		event.is_action("ui_up")
		or event.is_action("ui_down")
		or event.is_action("ui_left")
		or event.is_action("ui_right")
		or event.is_action("ui_accept")
		or event.is_action("ui_focus_next")
		or event.is_action("ui_focus_prev")
	):

		get_viewport().set_input_as_handled()

extends ColorRect

# ==================================================
# 主選單開場動畫控制器
# 負責黑幕淡出、Logo 淡入、選單依序出現
# 開場期間暫時禁止玩家操作選單
# ==================================================

signal intro_finished


@export_group("背景動畫設定")

## 開場黑幕停留時間
@export var black_hold_time: float = 0.2

## 黑幕淡出時間
@export var background_fade_time: float = 1.4


@export_group("標題動畫設定")

## Logo 開始淡入的時間
@export var logo_delay: float = 0.7

## Logo 淡入所需時間
@export var logo_fade_time: float = 1.2


@export_group("選單動畫設定")

## 第一個按鈕開始出現的時間
@export var menu_delay: float = 1.4

## 單一按鈕的淡入時間
@export var button_fade_time: float = 0.55

## 每個按鈕之間的出現間隔
@export var button_interval: float = 0.15


# ==================================================
# 取得場景節點
# ==================================================

@onready var logo: TextureRect = $"../Design/Logo"

@onready var buttons: Array[Button] = [
	$"../Design/MenuButtons/StartButton",
	$"../Design/MenuButtons/SettingsButton",
	$"../Design/MenuButtons/CreditsButton",
	$"../Design/MenuButtons/ExitButton"
]


# 儲存按鈕原本的鍵盤焦點設定
var _saved_focus_modes: Array[int] = []

# 開場動畫 Tween
var _intro_tween: Tween

# 記錄開場動畫是否已完成
var is_finished: bool = false


# ==================================================
# 1. 初始化
# ==================================================

func _ready() -> void:
	_prepare_intro()
	_play_intro()


# ==================================================
# 2. 設定開場初始狀態
# ==================================================

func _prepare_intro() -> void:

	# 顯示全黑遮罩
	show()
	color = Color.BLACK

	# 防止動畫期間點擊選單
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 隱藏遊戲標題
	logo.modulate.a = 0.0

	# 隱藏所有按鈕
	_saved_focus_modes.clear()

	for button in buttons:
		button.modulate.a = 0.0

		# 保存原本的焦點設定
		_saved_focus_modes.append(button.focus_mode)

		# 暫時禁止鍵盤選取按鈕
		button.release_focus()
		button.focus_mode = Control.FOCUS_NONE

	is_finished = false


# ==================================================
# 3. 播放開場淡入動畫
# ==================================================

func _play_intro() -> void:

	# 建立動畫，允許多個效果同時播放
	_intro_tween = create_tween()
	_intro_tween.set_parallel(true)

	# 使用柔和的動畫曲線
	_intro_tween.set_trans(Tween.TRANS_SINE)
	_intro_tween.set_ease(Tween.EASE_IN_OUT)

	# ----------------------------------------------
	# A. 黑幕逐漸消失
	# ----------------------------------------------

	_intro_tween.tween_property(
		self,
		"color:a",
		0.0,
		background_fade_time
	).set_delay(black_hold_time)

	# ----------------------------------------------
	# B. 遊戲 Logo 逐漸出現
	# ----------------------------------------------

	_intro_tween.tween_property(
		logo,
		"modulate:a",
		1.0,
		logo_fade_time
	).set_delay(logo_delay)

	# ----------------------------------------------
	# C. 四個選單按鈕依序出現
	# ----------------------------------------------

	for i in range(buttons.size()):

		var delay: float = menu_delay + i * button_interval

		_intro_tween.tween_property(
			buttons[i],
			"modulate:a",
			1.0,
			button_fade_time
		).set_delay(delay)

	# 等待所有動畫完成
	await _intro_tween.finished

	_finish_intro()


# ==================================================
# 4. 開場動畫完成
# ==================================================

func _finish_intro() -> void:

	# 恢復所有按鈕原本的焦點設定
	for i in range(buttons.size()):
		buttons[i].focus_mode = (
			_saved_focus_modes[i] as Control.FocusMode
		)

	# 移除黑幕對滑鼠操作的阻擋
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 隱藏黑幕
	hide()

	# 標記動畫完成
	is_finished = true

	# 發送開場完成訊號
	intro_finished.emit()

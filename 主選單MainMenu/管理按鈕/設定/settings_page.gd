extends Control
class_name MainMenuPage

# ==================================================
# 主選單共用子頁面
#
# 負責：
# 1. 返回首頁的請求
# 2. 按鈕懸停通知
# 3. 子選單功能選擇通知
#
# 不直接切換場景，也不直接管理音效
# ==================================================

# 請求返回主選單
signal back_requested

# 請求播放懸停音效
signal hover_requested

# 通知選擇了哪個功能
signal option_requested(option: StringName)


@export_group("按鈕設定")

## 返回按鈕
@export var back_button: Button

## 此頁面的其他功能按鈕
@export var option_buttons: Array[Button] = []


# ==================================================
# 1. 初始化訊號
# ==================================================

func _ready() -> void:

	# 連接返回按鈕
	if back_button != null:

		back_button.pressed.connect(_on_back_pressed)
		back_button.mouse_entered.connect(_on_hover)

	# 連接其他功能按鈕
	for button in option_buttons:

		if button == null:
			continue

		button.mouse_entered.connect(_on_hover)

		button.pressed.connect(
			_on_option_pressed.bind(button.name)
		)


# ==================================================
# 2. 滑鼠懸停
# ==================================================

func _on_hover() -> void:

	hover_requested.emit()


# ==================================================
# 3. 返回按鈕
# ==================================================

func _on_back_pressed() -> void:

	back_requested.emit()


# ==================================================
# 4. 功能按鈕
# ==================================================

func _on_option_pressed(option: StringName) -> void:

	option_requested.emit(option)

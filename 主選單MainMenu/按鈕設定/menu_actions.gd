
extends Node

# ============================================================
# 眠境 RE:RECOLOR - 主選單頁面管理器
#
# 負責：
# 1. 主選單按鈕操作
# 2. 子頁面建立與切換
# 3. 頁面返回與歷史紀錄
# 4. 共用 Hover / Confirm 音效
# 5. 頁面淡入淡出
#
# 不負責：
# - 音效素材管理（交給 MainMenuAudio）
# - 各設定頁內部功能
# ============================================================


# ============================================================
# 子頁面場景
# ============================================================

@export_group("子頁面場景")

# 開始遊戲頁面
@export var start_page_scene: PackedScene

# 設定頁面
@export var settings_page_scene: PackedScene

# 製作團隊頁面
@export var credits_page_scene: PackedScene

# 音量設定頁面
@export var audio_settings_page_scene: PackedScene

# 按鍵設定頁面
@export var controls_settings_page_scene: PackedScene


# ============================================================
# 頁面動畫設定
# ============================================================

@export_group("頁面動畫設定")

@export_range(0.1, 2.0, 0.05)
var transition_time: float = 0.15

@export_range(0.0, 1.0, 0.05)
var background_dim: float = 0.35


# ============================================================
# 取得主選單節點
# ============================================================

@onready var logo: TextureRect = $"../Design/Logo"

@onready var menu_buttons: VBoxContainer = \
	$"../Design/MenuButtons"

@onready var start_button: Button = \
	$"../Design/MenuButtons/StartButton"

@onready var settings_button: Button = \
	$"../Design/MenuButtons/SettingsButton"

@onready var credits_button: Button = \
	$"../Design/MenuButtons/CreditsButton"

@onready var exit_button: Button = \
	$"../Design/MenuButtons/ExitButton"


# ============================================================
# 轉場與音訊節點
# ============================================================

@onready var dim_overlay: ColorRect = \
	$"../Design/DimOverlay"

@onready var page_host: Control = \
	$"../Design/PageHost"

@onready var intro_fade: ColorRect = \
	$"../IntroFade"

@onready var menu_audio: MainMenuAudio = \
	$"../MenuAudio"


# ============================================================
# 頁面狀態
# ============================================================

# 目前顯示的頁面
var _active_page: MainMenuPage

# 目前頁面所使用的場景
var _active_page_scene: PackedScene

# 紀錄上一層頁面
var _page_history: Array[PackedScene] = []

# 防止動畫期間重複操作
var _is_busy: bool = false


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 主選單背景遮罩初始透明
	dim_overlay.color.a = 0.0

	# --------------------------------------------------------
	# 主選單按鈕訊號
	# --------------------------------------------------------

	start_button.pressed.connect(
		_on_start_pressed
	)

	settings_button.pressed.connect(
		_on_settings_pressed
	)

	credits_button.pressed.connect(
		_on_credits_pressed
	)

	exit_button.pressed.connect(
		_on_exit_pressed
	)

	# --------------------------------------------------------
	# 主選單 Hover 音效
	# --------------------------------------------------------

	for button in [
		start_button,
		settings_button,
		credits_button,
		exit_button
	]:

		button.mouse_entered.connect(
			_on_button_hover
		)


# ============================================================
# 共用 Hover 音效
# ============================================================

func _on_button_hover() -> void:

	if not _can_execute():
		return

	menu_audio.play_hover()


# ============================================================
# 主選單按鈕
# ============================================================

func _on_start_pressed() -> void:

	await _open_page(
		start_page_scene,
		"開始遊戲"
	)


func _on_settings_pressed() -> void:

	await _open_page(
		settings_page_scene,
		"設定"
	)


func _on_credits_pressed() -> void:

	await _open_page(
		credits_page_scene,
		"製作團隊"
	)


# ============================================================
# 離開遊戲
# ============================================================

func _on_exit_pressed() -> void:

	if not _can_execute():
		return

	_is_busy = true

	# 儲存目前設定
	SettingsManager.save_settings()

	# 播放確認音效並等待結束
	await menu_audio.play_confirm_and_wait()

	get_tree().quit()


# ============================================================
# 建立子頁面
# ============================================================

func _create_page(
	scene: PackedScene,
	page_name: String
) -> MainMenuPage:

	if scene == null:

		push_warning(
			"尚未設定頁面：" + page_name
		)

		return null

	var instance: Node = scene.instantiate()

	var page := instance as MainMenuPage

	if page == null:

		instance.free()

		push_error(
			"頁面未繼承 MainMenuPage：" + page_name
		)

		return null

	return page


# ============================================================
# 從主選單進入第一層子頁面
# ============================================================

func _open_page(
	scene: PackedScene,
	page_name: String
) -> void:

	if not _can_execute() or _active_page != null:
		return

	var page := _create_page(
		scene,
		page_name
	)

	if page == null:
		return

	_is_busy = true

	# 播放確認音效
	menu_audio.play_confirm()

	_page_history.clear()

	# --------------------------------------------------------
	# 主選單淡出
	# --------------------------------------------------------

	var tween := create_tween()

	tween.set_parallel(true)

	tween.set_trans(
		Tween.TRANS_SINE
	)

	tween.set_ease(
		Tween.EASE_IN_OUT
	)

	tween.tween_property(
		logo,
		"modulate:a",
		0.0,
		transition_time
	)

	tween.tween_property(
		menu_buttons,
		"modulate:a",
		0.0,
		transition_time
	)

	tween.tween_property(
		dim_overlay,
		"color:a",
		background_dim,
		transition_time
	)

	await tween.finished

	logo.hide()
	menu_buttons.hide()

	# 安裝頁面
	_install_page(
		page,
		scene
	)

	# 子頁面淡入
	await _fade_page(
		page,
		1.0
	)

	_is_busy = false


# ============================================================
# 進入下一層子頁面
#
# 例如：
# 設定 → 音量設定
# 設定 → 按鍵設定
# ============================================================

func _open_sub_page(
	scene: PackedScene,
	page_name: String
) -> void:

	if not _can_execute() or _active_page == null:
		return

	var page := _create_page(
		scene,
		page_name
	)

	if page == null:
		return

	_is_busy = true

	# 子頁面切換統一播放確認音效
	menu_audio.play_confirm()

	# 記錄目前頁面
	_page_history.append(
		_active_page_scene
	)

	# 執行頁面替換
	await _replace_page(
		page,
		scene
	)

	_is_busy = false


# ============================================================
# 頁面替換
# ============================================================

func _replace_page(
	page: MainMenuPage,
	scene: PackedScene
) -> void:

	# 舊頁面淡出
	await _fade_page(
		_active_page,
		0.0
	)

	# 移除舊頁面
	_remove_active_page()

	# 安裝新頁面
	_install_page(
		page,
		scene
	)

	# 新頁面淡入
	await _fade_page(
		page,
		1.0
	)


# ============================================================
# 安裝頁面與連接共用訊號
# ============================================================

func _install_page(
	page: MainMenuPage,
	scene: PackedScene
) -> void:

	page.modulate.a = 0.0

	# --------------------------------------------------------
	# 返回訊號
	# --------------------------------------------------------

	page.back_requested.connect(
		_on_page_back_requested
	)

	# --------------------------------------------------------
	# Hover 音效訊號
	# --------------------------------------------------------

	page.hover_requested.connect(
		_on_button_hover
	)

	# --------------------------------------------------------
	# 子頁面功能選擇訊號
	# --------------------------------------------------------

	page.option_requested.connect(
		_on_page_option_requested
	)

	# 記錄目前頁面
	_active_page = page

	_active_page_scene = scene

	# 加入頁面容器
	page_host.add_child(page)

	page.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	page.show()


# ============================================================
# 移除目前頁面
# ============================================================

func _remove_active_page() -> void:

	if is_instance_valid(_active_page):

		_active_page.hide()

		_active_page.queue_free()

	_active_page = null

	_active_page_scene = null


# ============================================================
# 返回上一層
# ============================================================

func _on_page_back_requested() -> void:

	if not _can_execute() or _active_page == null:
		return

	# --------------------------------------------------------
	# 有歷史頁面時，返回上一層
	# --------------------------------------------------------

	if not _page_history.is_empty():

		var previous_scene: PackedScene = \
			_page_history.back()

		var previous_page := _create_page(
			previous_scene,
			"上一層頁面"
		)

		if previous_page == null:
			return

		_is_busy = true

		# 返回播放確認音效
		menu_audio.play_confirm()

		_page_history.pop_back()

		await _replace_page(
			previous_page,
			previous_scene
		)

		_is_busy = false

		return

	# --------------------------------------------------------
	# 沒有歷史頁面時，返回主選單
	# --------------------------------------------------------

	_is_busy = true

	menu_audio.play_confirm()

	await _fade_page(
		_active_page,
		0.0
	)

	_remove_active_page()

	logo.show()

	menu_buttons.show()

	# 主選單淡入
	var tween := create_tween()

	tween.set_parallel(true)

	tween.set_trans(
		Tween.TRANS_SINE
	)

	tween.set_ease(
		Tween.EASE_IN_OUT
	)

	tween.tween_property(
		logo,
		"modulate:a",
		1.0,
		transition_time
	)

	tween.tween_property(
		menu_buttons,
		"modulate:a",
		1.0,
		transition_time
	)

	tween.tween_property(
		dim_overlay,
		"color:a",
		0.0,
		transition_time
	)

	await tween.finished

	_is_busy = false


# ============================================================
# 子頁面功能選擇
#
# AudioButton：
# 進入音量設定
#
# ControlsButton：
# 進入按鍵設定
#
# Confirm：
# 播放通用確認音效
# ============================================================

func _on_page_option_requested(
	option: StringName
) -> void:

	if not _can_execute():
		return

	match option:

		# ----------------------------------------------------
		# 音量設定
		# ----------------------------------------------------

		&"AudioButton":

			await _open_sub_page(
				audio_settings_page_scene,
				"音量設定"
			)

		# ----------------------------------------------------
		# 按鍵設定
		# ----------------------------------------------------

		&"ControlsButton":

			await _open_sub_page(
				controls_settings_page_scene,
				"按鍵設定"
			)

		# ----------------------------------------------------
		# 通用確認音效
		# ----------------------------------------------------

		&"Confirm":

			menu_audio.play_confirm()

		# ----------------------------------------------------
		# 其他功能
		# ----------------------------------------------------

		_:

			menu_audio.play_confirm()

			print(
				"選擇功能：",
				option
			)


# ============================================================
# 共用頁面淡入淡出
# ============================================================

func _fade_page(
	page: Control,
	target_alpha: float
) -> void:

	var tween := create_tween()

	tween.set_trans(
		Tween.TRANS_SINE
	)

	tween.set_ease(
		Tween.EASE_IN_OUT
	)

	tween.tween_property(
		page,
		"modulate:a",
		target_alpha,
		transition_time
	)

	await tween.finished


# ============================================================
# 操作鎖定
# ============================================================

func _can_execute() -> bool:

	if _is_busy:
		return false

	if intro_fade.visible:
		return false

	return true

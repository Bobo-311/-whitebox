extends MainMenuPage

# ========================================
# 眠境 RE:RECOLOR - 音量設定頁面
# 負責介面操作、數值同步與儲存提示
# ========================================

@export_group("恢復預設動畫")
@export var reset_animation_time: float = 0.3

@export_group("儲存提示")
@export var status_display_time: float = 2.0

@onready var master_slider: HSlider = \
	$VolumeRows/MasterRow/VolumeSlider

@onready var music_slider: HSlider = \
	$VolumeRows/MusicRow/VolumeSlider

@onready var sfx_slider: HSlider = \
	$VolumeRows/SFXRow/VolumeSlider

@onready var master_value: Label = \
	$VolumeRows/MasterRow/ValueLabel

@onready var music_value: Label = \
	$VolumeRows/MusicRow/ValueLabel

@onready var sfx_value: Label = \
	$VolumeRows/SFXRow/ValueLabel

@onready var reset_button: Button = $Actions/ResetButton
@onready var auto_save_label: Label = $AutoSaveLabel

const BUS_NAMES: Array[StringName] = [
	&"Master",
	&"Music",
	&"SFX"
]

const IDLE_COLOR := Color("#AFA0B9")
const SAVING_COLOR := Color("#E5C7E3")
const SAVED_COLOR := Color("#D5E8D8")
const ERROR_COLOR := Color("#E9A4B2")

var _sliders: Dictionary = {}
var _labels: Dictionary = {}
var _resetting: bool = false
var _status_timer: Timer


func _ready() -> void:
	# 保留共用頁面的返回及按鈕功能
	super._ready()

	_sliders = {
		&"Master": master_slider,
		&"Music": music_slider,
		&"SFX": sfx_slider
	}

	_labels = {
		&"Master": master_value,
		&"Music": music_value,
		&"SFX": sfx_value
	}

	# 建立提示文字計時器
	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.wait_time = status_display_time

	add_child(_status_timer)

	_status_timer.timeout.connect(_show_idle_status)

	# 初始化滑桿及百分比
	for bus_name in BUS_NAMES:
		_set_row_visual(
			SettingsManager.get_volume(bus_name),
			bus_name
		)

		var slider: HSlider = _sliders[bus_name]

		slider.value_changed.connect(
			_on_slider_value_changed.bind(bus_name)
		)

	# 接收全域設定管理器訊號
	SettingsManager.volume_changed.connect(_on_volume_changed)
	SettingsManager.settings_saved.connect(_on_settings_saved)
	SettingsManager.settings_save_failed.connect(_on_save_failed)

	reset_button.pressed.connect(_on_reset_pressed)
	reset_button.mouse_entered.connect(_on_reset_hovered)

	back_requested.connect(_flush_settings)

	_show_idle_status()


# ========================================
# 即時音量調整
# ========================================

func _on_slider_value_changed(
	value: float,
	bus_name: StringName
) -> void:
	if _resetting:
		return

	SettingsManager.set_volume(bus_name, value)


func _on_volume_changed(
	bus_name: StringName,
	value: int
) -> void:

	if not _resetting:
		_set_row_visual(value, bus_name)

	_show_saving_status()


func _set_row_visual(
	value: float,
	bus_name: StringName
) -> void:

	var slider: HSlider = _sliders[bus_name]
	var label: Label = _labels[bus_name]

	# 更新畫面但不重複觸發音量設定
	slider.set_value_no_signal(value)

	label.text = "%d%%" % roundi(slider.value)


# ========================================
# 恢復預設動畫
# ========================================

func _on_reset_pressed() -> void:
	if _resetting:
		return

	var needs_reset: bool = false

	for bus_name in BUS_NAMES:
		if SettingsManager.get_volume(bus_name) != 100:
			needs_reset = true
			break

	if not needs_reset:
		if SettingsManager.has_unsaved_changes():
			SettingsManager.save_settings()
		else:
			_show_temporary_status(
				"目前已是預設值",
				IDLE_COLOR
			)
		return

	_resetting = true
	reset_button.disabled = true

	# 動畫期間暫停滑桿操作，避免數值衝突
	for bus_name in BUS_NAMES:
		var slider: HSlider = _sliders[bus_name]
		slider.editable = false

	# 立即恢復實際音量及儲存設定
	SettingsManager.reset_audio_settings()

	# 三個滑桿同時平滑回到預設值
	var tween := create_tween()

	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	for bus_name in BUS_NAMES:
		var slider: HSlider = _sliders[bus_name]

		tween.tween_method(
			_set_row_visual.bind(bus_name),
			slider.value,
			100.0,
			reset_animation_time
		)

	await tween.finished

	for bus_name in BUS_NAMES:
		var slider: HSlider = _sliders[bus_name]
		slider.editable = true

	reset_button.disabled = false
	_resetting = false


func _on_reset_hovered() -> void:
	hover_requested.emit()


# ========================================
# 儲存狀態提示
# ========================================

func _show_idle_status() -> void:
	auto_save_label.text = "設定將自動儲存"

	auto_save_label.add_theme_color_override(
		"font_color",
		IDLE_COLOR
	)


func _show_saving_status() -> void:
	_status_timer.stop()

	auto_save_label.text = "正在儲存..."

	auto_save_label.add_theme_color_override(
		"font_color",
		SAVING_COLOR
	)


func _on_settings_saved() -> void:
	_show_temporary_status(
		"設定已儲存",
		SAVED_COLOR
	)


func _on_save_failed(_error: Error) -> void:
	_status_timer.stop()

	auto_save_label.text = "儲存失敗，請重新嘗試"

	auto_save_label.add_theme_color_override(
		"font_color",
		ERROR_COLOR
	)


func _show_temporary_status(
	message: String,
	color: Color
) -> void:

	auto_save_label.text = message

	auto_save_label.add_theme_color_override(
		"font_color",
		color
	)

	_status_timer.start()


func _flush_settings() -> void:
	SettingsManager.save_settings()

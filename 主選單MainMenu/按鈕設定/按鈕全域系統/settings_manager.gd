extends Node

# ========================================
# 眠境 RE:RECOLOR - 全域設定管理
# 負責音量控制、讀取及永久儲存
# ========================================

signal volume_changed(bus_name: StringName, value: int)
signal settings_saved
signal settings_save_failed(error: Error)

const CONFIG_PATH: String = "user://recolor_settings.cfg"
const AUDIO_SECTION: String = "audio"

const AUDIO_BUSES: Array[StringName] = [
	&"Master",
	&"Music",
	&"SFX"
]

const DEFAULT_VOLUME: int = 100
const SAVE_DELAY: float = 0.4

var _volumes: Dictionary = {
	&"Master": DEFAULT_VOLUME,
	&"Music": DEFAULT_VOLUME,
	&"SFX": DEFAULT_VOLUME
}

var _config := ConfigFile.new()
var _save_timer: Timer
var _dirty: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 避免拖曳滑桿時頻繁寫入檔案
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.ignore_time_scale = true

	add_child(_save_timer)

	_save_timer.timeout.connect(_on_save_timeout)

	load_settings()

	if OS.is_debug_build():
		print("[SettingsManager] 初始化完成")
		print("[SettingsManager] 音量設定：", _volumes)
		print("[SettingsManager] 設定檔：",
			ProjectSettings.globalize_path(CONFIG_PATH))


# ========================================
# 讀取設定
# ========================================

func load_settings() -> void:
	var error: Error = _config.load(CONFIG_PATH)

	if error == OK:
		for bus_name in AUDIO_BUSES:
			var raw_value: Variant = _config.get_value(
				AUDIO_SECTION,
				String(bus_name),
				DEFAULT_VOLUME
			)

			var volume: int = DEFAULT_VOLUME

			if raw_value is int or raw_value is float:
				if is_finite(float(raw_value)):
					volume = roundi(
						clampf(float(raw_value), 0.0, 100.0)
					)

			_volumes[bus_name] = volume

	else:
		for bus_name in AUDIO_BUSES:
			_volumes[bus_name] = DEFAULT_VOLUME

		if error == ERR_FILE_NOT_FOUND:
			_dirty = true
			save_settings()
		else:
			push_warning("設定檔讀取失敗，使用預設值。")

	_apply_all_volumes()


# ========================================
# 音量控制
# ========================================

func get_volume(bus_name: StringName) -> int:
	return int(_volumes.get(bus_name, DEFAULT_VOLUME))


func set_volume(bus_name: StringName, value: float) -> void:
	if bus_name not in AUDIO_BUSES:
		push_warning("無效的音訊匯流排：" + String(bus_name))
		return

	var new_volume: int = roundi(
		clampf(value, 0.0, 100.0)
	)

	if get_volume(bus_name) == new_volume:
		return

	_volumes[bus_name] = new_volume

	# 立即套用音量，不等待儲存
	_apply_volume(bus_name)

	_dirty = true
	_save_timer.start()

	volume_changed.emit(bus_name, new_volume)


func _apply_volume(bus_name: StringName) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		push_warning("找不到音訊匯流排：" + String(bus_name))
		return

	var volume: int = get_volume(bus_name)

	# 0% 時完全靜音
	if volume == 0:
		AudioServer.set_bus_mute(bus_index, true)
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	else:
		var linear_volume: float = float(volume) / 100.0

		AudioServer.set_bus_volume_db(
			bus_index,
			linear_to_db(linear_volume)
		)

		AudioServer.set_bus_mute(bus_index, false)


func _apply_all_volumes() -> void:
	for bus_name in AUDIO_BUSES:
		_apply_volume(bus_name)


# ========================================
# 恢復預設
# ========================================

func reset_audio_settings() -> bool:
	for bus_name in AUDIO_BUSES:
		set_volume(bus_name, DEFAULT_VOLUME)

	return save_settings()


# ========================================
# 永久儲存
# ========================================

func has_unsaved_changes() -> bool:
	return _dirty


func save_settings() -> bool:
	if not _dirty:
		return true

	for bus_name in AUDIO_BUSES:
		_config.set_value(
			AUDIO_SECTION,
			String(bus_name),
			get_volume(bus_name)
		)

	var error: Error = _config.save(CONFIG_PATH)

	if error != OK:
		push_warning("設定儲存失敗：" + error_string(error))
		settings_save_failed.emit(error)
		return false

	_dirty = false

	if is_instance_valid(_save_timer):
		_save_timer.stop()

	# 確認真正寫入成功後才發送訊號
	settings_saved.emit()

	if OS.is_debug_build():
		print("[SettingsManager] 設定儲存成功：", _volumes)

	return true


func _on_save_timeout() -> void:
	save_settings()


func _exit_tree() -> void:
	# 離開遊戲時，確保尚未儲存的設定寫入
	if _dirty:
		save_settings()

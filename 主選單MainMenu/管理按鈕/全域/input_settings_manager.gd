
extends Node


# ============================================================
# 眠境 RE:RECOLOR - 按鍵設定管理器
#
# 負責：
# 1. 記錄原始預設按鍵
# 2. 修改玩家按鍵
# 3. 偵測按鍵衝突
# 4. 儲存與讀取玩家設定
# 5. 恢復預設按鍵
#
# 設計原則：
# - 一個操作只能使用一個鍵盤或滑鼠按鍵
# - 不允許兩個操作使用相同按鍵
# - 不提供自動交換功能
# - 儲存成功後才正式套用
# ============================================================


# ============================================================
# 訊號 SIGNALS
# ============================================================

signal bindings_changed
signal settings_saved
signal settings_save_failed(error: Error)


# ============================================================
# 儲存設定 SAVE CONFIGURATION
# ============================================================

const SAVE_PATH := "user://recolor_input_settings.cfg"
const SAVE_SECTION := "bindings"
const SAVE_VERSION := 1


# ============================================================
# 玩家可以修改的操作
# ============================================================

const ACTIONS: Array[StringName] = [
	&"up",
	&"down",
	&"left",
	&"right",
	&"dash",

	&"cat_move",
	&"cat_recall",

	&"attack",
	&"skill_01",
	&"switch_weapon",

	&"USESKILL",
	&"slot_left",
	&"slot_right",

	&"TAB"
]


# ============================================================
# 固定操作
# ============================================================

# 這些操作不提供玩家修改
# 但仍然參與按鍵衝突檢查

const FIXED_ACTIONS: Array[StringName] = [
	&"interact",
	&"ESC",
	&"enter"
]


# ============================================================
# 內部資料
# ============================================================

# 遊戲最初的預設按鍵
var _default_bindings: Dictionary = {}

# 玩家目前使用的按鍵
var _bindings: Dictionary = {}

# 是否完成初始化
var _initialized: bool = false


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 記錄遊戲原始預設按鍵
	if not _cache_default_bindings():

		push_error(
			"【按鍵管理器】初始化失敗，請檢查 Input Map"
		)

		return

	# 建立預設按鍵副本
	_bindings = _duplicate_bindings(
		_default_bindings
	)

	_initialized = true

	# 載入玩家之前儲存的設定
	_load_settings()
	# 開發診斷：檢查目前所有使用 F 的操作
	_debug_print_f_bindings()
	print("【按鍵管理器】初始化完成")


# ============================================================
# 複製按鍵設定
# ============================================================

# 每個 InputEvent 都建立獨立副本
# 避免修改暫存資料時影響原始設定

func _duplicate_bindings(
	source: Dictionary
) -> Dictionary:

	var result: Dictionary = {}

	for action in ACTIONS:

		var event: InputEvent = source.get(action)

		if event != null:

			result[action] = (
				event.duplicate() as InputEvent
			)

		else:

			result[action] = null

	return result


# ============================================================
# 記錄原始預設按鍵
# ============================================================

func _cache_default_bindings() -> bool:

	_default_bindings.clear()

	for action in ACTIONS:

		# 確認 Input Map 存在
		if not InputMap.has_action(action):

			push_error(
				"找不到 Input Map 動作："
				+ String(action)
			)

			return false

		var events := InputMap.action_get_events(
			action
		)

		var binding_events: Array[InputEvent] = []

		# 只記錄鍵盤及滑鼠事件
		for event in events:

			if (
				event is InputEventKey
				or event is InputEventMouseButton
			):

				binding_events.append(event)

		# 每個操作必須有一個預設按鍵
		if binding_events.size() != 1:

			push_error(
				"預設按鍵數量不正確："
				+ String(action)
			)

			return false

		var binding: InputEvent = binding_events[0]

		if _encode_binding(binding).is_empty():

			push_error(
				"預設按鍵不受支援："
				+ String(action)
			)

			return false

		_default_bindings[action] = (
			binding.duplicate() as InputEvent
		)

	return true


# ============================================================
# 取得目前按鍵
# ============================================================

func get_binding(
	action: StringName
) -> InputEvent:

	var event: InputEvent = _bindings.get(action)

	if event == null:
		return null

	return event.duplicate() as InputEvent


# ============================================================
# 取得按鍵顯示文字
# ============================================================

func get_binding_text(
	action: StringName
) -> String:

	return get_event_text(
		get_binding(action)
	)


func get_event_text(
	event: InputEvent
) -> String:

	if event == null:
		return "未設定"

	# ----------------------------
	# 鍵盤按鍵
	# ----------------------------

	if event is InputEventKey:

		var code: Key = event.keycode

		if event.physical_keycode != 0:

			var translated: Key = (
				DisplayServer.keyboard_get_keycode_from_physical(
					event.physical_keycode
				)
			)

			if translated != 0:
				code = translated
			else:
				code = event.physical_keycode

		if code == 0:
			return "未設定"

		return OS.get_keycode_string(code)

	# ----------------------------
	# 滑鼠按鍵
	# ----------------------------

	if event is InputEventMouseButton:

		match event.button_index:

			MOUSE_BUTTON_LEFT:
				return "滑鼠左鍵"

			MOUSE_BUTTON_RIGHT:
				return "滑鼠右鍵"

			MOUSE_BUTTON_MIDDLE:
				return "滑鼠中鍵"

			MOUSE_BUTTON_XBUTTON1:
				return "滑鼠側鍵 1"

			MOUSE_BUTTON_XBUTTON2:
				return "滑鼠側鍵 2"

			MOUSE_BUTTON_WHEEL_UP:
				return "滑鼠滾輪 ↑"

			MOUSE_BUTTON_WHEEL_DOWN:
				return "滑鼠滾輪 ↓"

	return "未知按鍵"


# ============================================================
# 判斷是否為單獨的修飾鍵
# ============================================================

# 允許單獨綁定 Shift、Ctrl、Alt、Meta
# 不允許 Shift + W 這種組合鍵

func _is_modifier_key(
	event: InputEventKey
) -> bool:

	return (
		event.keycode in [
			KEY_SHIFT,
			KEY_CTRL,
			KEY_ALT,
			KEY_META
		]
		or event.physical_keycode in [
			KEY_SHIFT,
			KEY_CTRL,
			KEY_ALT,
			KEY_META
		]
	)


# ============================================================
# 輸入事件標準化
# ============================================================

# 將玩家輸入轉換成乾淨的 InputEvent
# 只保留真正綁定的按鍵，不保留按下狀態

func normalize_event(
	event: InputEvent
) -> InputEvent:

	# ----------------------------
	# 鍵盤
	# ----------------------------

	if event is InputEventKey:

		# 不允許組合鍵
		if not _is_modifier_key(event):

			if (
				event.ctrl_pressed
				or event.alt_pressed
				or event.meta_pressed
				or event.shift_pressed
			):

				return null

		var key := InputEventKey.new()

		# 優先使用實體鍵盤位置
		if event.physical_keycode != 0:

			key.physical_keycode = (
				event.physical_keycode
			)

		else:

			key.keycode = event.keycode

		if _encode_binding(key).is_empty():
			return null

		return key

	# ----------------------------
	# 滑鼠
	# ----------------------------

	if event is InputEventMouseButton:

		var mouse := InputEventMouseButton.new()

		mouse.button_index = event.button_index

		if _encode_binding(mouse).is_empty():
			return null

		return mouse

	return null


# ============================================================
# 取得實際鍵盤鍵碼
# ============================================================

func _get_logical_keycode(
	event: InputEventKey
) -> Key:

	if event.physical_keycode != 0:

		var translated: Key = (
			DisplayServer.keyboard_get_keycode_from_physical(
				event.physical_keycode
			)
		)

		if translated != 0:
			return translated

		return event.physical_keycode

	return event.keycode


# ============================================================
# 比較兩個按鍵是否相同
# ============================================================

func _same_binding(
	first: InputEvent,
	second: InputEvent
) -> bool:

	if first == null or second == null:
		return false

	# 鍵盤
	if (
		first is InputEventKey
		and second is InputEventKey
	):

		if (
			first.physical_keycode != 0
			and second.physical_keycode != 0
		):

			return (
				first.physical_keycode
				== second.physical_keycode
			)

		return (
			_get_logical_keycode(first)
			== _get_logical_keycode(second)
		)

	# 滑鼠
	if (
		first is InputEventMouseButton
		and second is InputEventMouseButton
	):

		return (
			first.button_index
			== second.button_index
		)

	return false


# ============================================================
# 判斷操作是否允許修改
# ============================================================

func is_rebindable_action(
	action: StringName
) -> bool:

	return ACTIONS.has(action)


# ============================================================
# 衝突偵測
# ============================================================

# 對外使用的衝突檢查
# 沒有衝突時回傳空 StringName

func find_conflict(
	action: StringName,
	event: InputEvent
) -> StringName:

	return _find_conflict(
		action,
		event,
		_bindings
	)


# ------------------------------------------------------------
# 內部衝突檢查
# ------------------------------------------------------------

func _find_conflict(
	action: StringName,
	event: InputEvent,
	bindings: Dictionary
) -> StringName:

	if event == null:
		return &""

	# ESC 永遠保留給系統取消與返回
	if event is InputEventKey:

		if _get_logical_keycode(event) == KEY_ESCAPE:
			return &"ESC"

	# ----------------------------
	# 檢查固定操作
	# ----------------------------

	for fixed_action in FIXED_ACTIONS:

		if not InputMap.has_action(fixed_action):
			continue

		var fixed_events := (
			InputMap.action_get_events(fixed_action)
		)

		for fixed_event in fixed_events:

			if not (
				fixed_event is InputEventKey
				or fixed_event is InputEventMouseButton
			):
				continue

			if _same_binding(event, fixed_event):
				return fixed_action

	# ----------------------------
	# 檢查其他玩家操作
	# ----------------------------

	for other_action in ACTIONS:

		if other_action == action:
			continue

		var other_event: InputEvent = (
			bindings.get(other_action)
		)

		if _same_binding(event, other_event):
			return other_action

	return &""


# ============================================================
# 修改按鍵
# ============================================================

# 採用禁止重複的簡單方式
#
# 如果按鍵已被其他操作使用：
# 直接拒絕修改
#
# 保留第三個參數是為了相容舊程式呼叫
# 但不再提供交換功能

func rebind(
	action: StringName,
	event: InputEvent,
	_legacy_swap_with: StringName = &""
) -> bool:

	if not _initialized:
		return false

	if not ACTIONS.has(action):
		return false

	# 不再接受交換請求
	if _legacy_swap_with != &"":
		return false

	var new_event := normalize_event(event)

	if new_event == null:
		return false

	var old_event: InputEvent = (
		_bindings.get(action)
	)

	# 按鍵沒有變更
	if _same_binding(old_event, new_event):
		return true

	# 檢查是否與其他操作衝突
	var conflict := find_conflict(
		action,
		new_event
	)

	if conflict != &"":
		return false

	# 建立暫存設定
	var candidate := _duplicate_bindings(
		_bindings
	)

	candidate[action] = (
		new_event.duplicate() as InputEvent
	)

	# 正式提交
	return _commit_bindings(candidate)


# ============================================================
# 驗證整組按鍵
# ============================================================

func _validate_bindings(
	bindings: Dictionary
) -> bool:

	for action in ACTIONS:

		var event: InputEvent = (
			bindings.get(action)
		)

		# 每個操作都必須有有效按鍵
		if _encode_binding(event).is_empty():
			return false

		# 檢查是否與其他操作衝突
		if (
			_find_conflict(
				action,
				event,
				bindings
			) != &""
		):

			return false

	return true


# ============================================================
# 套用至 Godot Input Map
# ============================================================

func _apply_bindings(
	bindings: Dictionary
) -> void:

	for action in ACTIONS:

		var old_event: InputEvent = (
			_bindings.get(action)
		)

		var new_event: InputEvent = (
			bindings.get(action)
		)

		# 沒有變更就不重新套用
		if (
			_encode_binding(old_event)
			== _encode_binding(new_event)
		):

			continue

		# 清除殘留的按下狀態
		Input.action_release(action)

		var current_events := (
			InputMap.action_get_events(action)
		)

		# 只移除鍵盤及滑鼠事件
		# 保留其他輸入類型，例如手把
		for current_event in current_events:

			if (
				current_event is InputEventKey
				or current_event is InputEventMouseButton
			):

				InputMap.action_erase_event(
					action,
					current_event
				)

		# 加入新的按鍵
		InputMap.action_add_event(
			action,
			new_event.duplicate() as InputEvent
		)

	# 更新內部設定
	_bindings = _duplicate_bindings(bindings)


# ============================================================
# 恢復預設按鍵
# ============================================================

func reset_to_defaults() -> bool:

	if not _initialized:
		return false

	# 使用遊戲最初記錄的預設設定
	var defaults := _duplicate_bindings(
		_default_bindings
	)

	# 驗證、儲存及套用
	return _commit_bindings(defaults)


# ============================================================
# 正式提交設定
# ============================================================

func _commit_bindings(
	candidate: Dictionary
) -> bool:

	if not _initialized:
		return false

	# 第一步：驗證
	if not _validate_bindings(candidate):

		push_warning(
			"【按鍵管理器】設定驗證失敗，保留原設定"
		)

		return false

	# 第二步：先儲存
	var save_error := _save_settings(candidate)

	if save_error != OK:

		settings_save_failed.emit(save_error)

		push_error(
			"【按鍵管理器】儲存失敗："
			+ str(save_error)
		)

		return false

	# 第三步：套用
	_apply_bindings(candidate)

	# 第四步：通知介面
	bindings_changed.emit()

	# 第五步：通知儲存成功
	settings_saved.emit()

	return true


# ============================================================
# 按鍵資料編碼
# ============================================================

# 將 InputEvent 轉換成可以儲存的 Dictionary

func _encode_binding(
	event: InputEvent
) -> Dictionary:

	if event == null:
		return {}

	# ----------------------------
	# 鍵盤
	# ----------------------------

	if event is InputEventKey:

		# 不儲存組合鍵
		if (
			event.ctrl_pressed
			or event.alt_pressed
			or event.meta_pressed
			or event.shift_pressed
		):

			return {}

		if event.physical_keycode != 0:

			return {
				"type": "physical_key",
				"code": int(event.physical_keycode)
			}

		if event.keycode != 0:

			return {
				"type": "key",
				"code": int(event.keycode)
			}

	# ----------------------------
	# 滑鼠
	# ----------------------------

	if event is InputEventMouseButton:

		if event.button_index in [
			MOUSE_BUTTON_LEFT,
			MOUSE_BUTTON_RIGHT,
			MOUSE_BUTTON_MIDDLE,
			MOUSE_BUTTON_XBUTTON1,
			MOUSE_BUTTON_XBUTTON2,
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN
		]:

			return {
				"type": "mouse",
				"code": int(event.button_index)
			}

	return {}


# ============================================================
# 按鍵資料解碼
# ============================================================

func _decode_binding(
	value: Variant
) -> InputEvent:

	if typeof(value) != TYPE_DICTIONARY:
		return null

	var data: Dictionary = value

	var code_value: Variant = data.get(
		"code",
		0
	)

	if typeof(code_value) != TYPE_INT:
		return null

	var code: int = code_value

	if code <= 0:
		return null

	match String(data.get("type", "")):

		"physical_key":

			var key := InputEventKey.new()

			key.physical_keycode = code as Key

			if _encode_binding(key).is_empty():
				return null

			return key

		"key":

			var key := InputEventKey.new()

			key.keycode = code as Key

			if _encode_binding(key).is_empty():
				return null

			return key

		"mouse":

			var mouse := InputEventMouseButton.new()

			mouse.button_index = code as MouseButton

			if _encode_binding(mouse).is_empty():
				return null

			return mouse

	return null


# ============================================================
# 儲存玩家設定
# ============================================================

func _save_settings(
	bindings: Dictionary
) -> Error:

	var config := ConfigFile.new()

	config.set_value(
		"general",
		"version",
		SAVE_VERSION
	)

	for action in ACTIONS:

		var event: InputEvent = (
			bindings.get(action)
		)

		var default_event: InputEvent = (
			_default_bindings.get(action)
		)

		var data := _encode_binding(event)

		var default_data := _encode_binding(
			default_event
		)

		# 與預設相同就不需要重複記錄
		if data == default_data:
			continue

		config.set_value(
			SAVE_SECTION,
			String(action),
			data
		)

	return config.save(SAVE_PATH)


# ============================================================
# 載入玩家設定
# ============================================================

func _load_settings() -> void:

	var config := ConfigFile.new()

	var error := config.load(SAVE_PATH)

	# 第一次遊玩沒有設定檔是正常的
	if error == ERR_FILE_NOT_FOUND:
		return

	if error != OK:

		push_warning(
			"按鍵設定讀取失敗，使用預設按鍵"
		)

		return

	# 檢查版本
	var version: int = int(
		config.get_value(
			"general",
			"version",
			SAVE_VERSION
		)
	)

	if version != SAVE_VERSION:

		push_warning(
			"按鍵設定版本不相容，使用預設按鍵"
		)

		return

	# 先建立預設設定副本
	var candidate := _duplicate_bindings(
		_default_bindings
	)

	# 逐一讀取玩家設定
	for action in ACTIONS:

		if not config.has_section_key(
			SAVE_SECTION,
			String(action)
		):

			continue

		var data: Variant = config.get_value(
			SAVE_SECTION,
			String(action)
		)

		var event := _decode_binding(data)

		if event == null:

			push_warning(
				"按鍵資料錯誤："
				+ String(action)
				+ "，使用預設設定"
			)

			return

		candidate[action] = event

	# 確認整組設定沒有衝突
	if not _validate_bindings(candidate):

		push_warning(
			"玩家按鍵設定存在衝突，使用預設設定"
		)

		return

	# 正式套用
	_apply_bindings(candidate)

	print(
		"【按鍵管理器】成功載入玩家設定"
	)


# ============================================================
# 開發診斷：檢查 F 按鍵使用狀況
#
# 用途：
# 1. 檢查目前 Input Map 哪些動作使用 F
# 2. 檢查遊戲原始預設是否有 F
# 3. 檢查玩家目前儲存的設定是否有 F
#
# 僅供開發測試，不會修改任何設定
# ============================================================

func _debug_print_f_bindings() -> void:

	print("\n========== F KEY DIAGNOSTIC ==========")

	# 檢查 Godot 目前實際的 Input Map
	for action in InputMap.get_actions():

		for event in InputMap.action_get_events(action):

			if event is InputEventKey:

				if (
					event.keycode == KEY_F
					or event.physical_keycode == KEY_F
				):

					print(
						"[Input Map] ",
						action,
						" | ",
						event.as_text()
					)

	# 檢查遊戲原始預設按鍵
	for action in ACTIONS:

		var event: InputEvent = _default_bindings.get(action)

		if event is InputEventKey:

			if (
				event.keycode == KEY_F
				or event.physical_keycode == KEY_F
			):

				print(
					"[Default] ",
					action,
					" | ",
					event.as_text()
				)

	# 檢查玩家目前的按鍵設定
	for action in ACTIONS:

		var event: InputEvent = _bindings.get(action)

		if event is InputEventKey:

			if (
				event.keycode == KEY_F
				or event.physical_keycode == KEY_F
			):

				print(
					"[Current] ",
					action,
					" | ",
					event.as_text()
				)

	print("========== END DIAGNOSTIC ==========\n")

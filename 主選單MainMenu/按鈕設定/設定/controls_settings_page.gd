
extends MainMenuPage


# ============================================================
# 眠境 RE:RECOLOR - 按鍵設定頁面
#
# 負責：
# 1. 建立操作分類及按鍵列
# 2. 偵測鍵盤與滑鼠輸入
# 3. 顯示按鍵衝突
# 4. 顯示儲存結果
# 5. 恢復預設按鍵
# 6. 連接返回及恢復預設按鈕音效
#
# 不負責：
# - 直接修改 Input Map
# - 直接儲存設定檔
# - 管理全域音效播放器
#
# 按鍵資料由 InputSettingsManager 管理
# 音效由 MainMenuAudio 管理
# ============================================================


# ============================================================
# 共用介面資源
# ============================================================

@export_group("共用介面資源")

# 按鍵列場景
@export var key_row_scene: PackedScene

# 共用介面字體
@export var ui_font: Font


# ============================================================
# 分類動畫設定
# ============================================================

@export_group("分類動畫設定")

@export var divider_duration: float = 0.55

@export var group_delay: float = 0.08

@export var divider_color: Color = Color("#C9B4D080")


# ============================================================
# 提示文字顏色
# ============================================================

@export_group("提示文字顏色")

@export var normal_text_color: Color = Color("#C9B4D0")

@export var waiting_text_color: Color = Color("#F5D7F2")

@export var success_text_color: Color = Color("#C1DFC9")

@export var conflict_text_color: Color = Color("#E9A4B2")


# ============================================================
# 取得場景節點
# ============================================================

@onready var left_column: VBoxContainer = (
	get_node_or_null("ControlsColumns/LeftColumn")
	as VBoxContainer
)

@onready var right_column: VBoxContainer = (
	get_node_or_null("ControlsColumns/RightColumn")
	as VBoxContainer
)

# 底部儲存提示
@onready var status_label: Label = (
	get_node_or_null("Actions/AutoSaveLabel")
	as Label
)

# 恢復預設按鈕
@onready var reset_button: Button = (
	get_node_or_null("Actions/ResetButton")
	as Button
)


# ============================================================
# 左側分類資料
# ============================================================

const LEFT_GROUPS: Array[Dictionary] = [

	{
		"title": "移動　MOVEMENT",

		"rows": [
			[&"up", "向上移動"],
			[&"down", "向下移動"],
			[&"left", "向左移動"],
			[&"right", "向右移動"],
			[&"dash", "閃避"]
		]
	},

	{
		"title": "白貓　COMPANION",

		"rows": [
			[&"cat_move", "白貓移動"],
			[&"cat_recall", "白貓快速回位"]
		]
	}
]


# ============================================================
# 右側分類資料
# ============================================================

const RIGHT_GROUPS: Array[Dictionary] = [

	{
		"title": "戰鬥　COMBAT",

		"rows": [
			[&"attack", "近戰攻擊"],
			[&"skill_01", "遠程攻擊"],
			[&"switch_weapon", "切換魔法"]
		]
	},

	{
		"title": "道具　ITEMS",

		"rows": [
			[&"USESKILL", "使用道具"],
			[&"slot_left", "向左切換道具"],
			[&"slot_right", "向右切換道具"]
		]
	},

	{
		"title": "介面　INTERFACE",

		"rows": [
			[&"TAB", "開啟筆記本"]
		]
	}
]


# ============================================================
# 內部資料
# ============================================================

# 動作名稱對應的按鍵按鈕
var _key_buttons: Dictionary = {}

# 動作名稱對應的中文名稱
var _action_names: Dictionary = {}

# 分類動畫順序
var _group_index: int = 0


# ============================================================
# 輸入捕捉狀態
# ============================================================

# 目前正在修改的動作
var _waiting_action: StringName = &""

# 暫存已標準化的按鍵
var _pending_event: InputEvent = null

# 記錄目前按住的輸入
var _held_capture_tokens: Dictionary = {}

# 是否正在阻擋組合鍵
var _combo_blocked: bool = false


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 初始化父類別
	super._ready()

	# 確認按鍵列場景
	if key_row_scene == null:

		push_error(
			"尚未指定 Key Row Scene"
		)

		return

	# 確認左右欄位
	if left_column == null or right_column == null:

		push_error(
			"找不到 ControlsColumns 左右欄位"
		)

		return

	# --------------------------------------------------------
	# 建立操作分類
	# --------------------------------------------------------

	_build_column(
		left_column,
		LEFT_GROUPS
	)

	_build_column(
		right_column,
		RIGHT_GROUPS
	)

	# --------------------------------------------------------
	# 監聽按鍵設定變更
	# --------------------------------------------------------

	if not InputSettingsManager.bindings_changed.is_connected(
		_refresh_all_keys
	):

		InputSettingsManager.bindings_changed.connect(
			_refresh_all_keys
		)

	# --------------------------------------------------------
	# 監聽頁面顯示狀態
	# --------------------------------------------------------

	if not visibility_changed.is_connected(
		_on_page_visibility_changed
	):

		visibility_changed.connect(
			_on_page_visibility_changed
		)

	# --------------------------------------------------------
	# 連接恢復預設按鈕
	# --------------------------------------------------------

	if reset_button != null:

		# 點擊：恢復預設
		if not reset_button.pressed.is_connected(
			_on_reset_button_pressed
		):

			reset_button.pressed.connect(
				_on_reset_button_pressed
			)

		# 滑鼠移入：Hover 音效
		if not reset_button.mouse_entered.is_connected(
			_on_reset_button_hovered
		):

			reset_button.mouse_entered.connect(
				_on_reset_button_hovered
			)

	else:

		push_warning(
			"找不到 Actions/ResetButton"
		)

	# --------------------------------------------------------
	# 初始按鍵顯示
	# --------------------------------------------------------

	_refresh_all_keys()

	_set_status(
		"點擊按鍵即可修改設定",
		normal_text_color
	)

	# 平常不需要監聽全部輸入
	set_process_input(false)


# ============================================================
# 建立分類欄位
# ============================================================

func _build_column(
	column: VBoxContainer,
	groups: Array[Dictionary]
) -> void:

	for group_data in groups:

		var group := VBoxContainer.new()

		group.add_theme_constant_override(
			"separation",
			4
		)

		column.add_child(group)

		# 分類動畫延遲
		var delay: float = (
			_group_index * group_delay
		)

		# 分類標題
		_create_group_title(
			group,
			String(group_data["title"]),
			delay
		)

		# 分隔線
		_create_divider(
			group,
			delay
		)

		# 操作按鍵
		var rows: Array = group_data["rows"]

		for entry in rows:

			_create_key_row(
				group,
				entry[0],
				entry[1]
			)

		_group_index += 1


# ============================================================
# 建立分類標題
# ============================================================

func _create_group_title(
	parent: VBoxContainer,
	title_text: String,
	delay: float
) -> void:

	var label := Label.new()

	label.text = title_text

	label.custom_minimum_size.y = 28

	label.add_theme_font_size_override(
		"font_size",
		21
	)

	label.add_theme_color_override(
		"font_color",
		Color("#C9B4D0")
	)

	if ui_font != null:

		label.add_theme_font_override(
			"font",
			ui_font
		)

	parent.add_child(label)

	# 初始透明
	label.modulate.a = 0.0

	# 分類淡入
	var tween := create_tween()

	tween.tween_property(
		label,
		"modulate:a",
		1.0,
		0.35
	).set_delay(delay)


# ============================================================
# 建立分隔線動畫
# ============================================================

func _create_divider(
	parent: VBoxContainer,
	delay: float
) -> void:

	var divider := Control.new()

	divider.custom_minimum_size.y = 2

	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE

	parent.add_child(divider)

	var line := ColorRect.new()

	line.color = divider_color

	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	divider.add_child(line)

	# 填滿容器
	line.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	# 從左側開始延伸
	line.pivot_offset = Vector2.ZERO

	line.scale.x = 0.0

	# 平滑延伸動畫
	var tween := create_tween()

	tween.set_trans(
		Tween.TRANS_CUBIC
	)

	tween.set_ease(
		Tween.EASE_OUT
	)

	tween.tween_property(
		line,
		"scale:x",
		1.0,
		divider_duration
	).set_delay(delay)


# ============================================================
# 建立單一按鍵列
# ============================================================

func _create_key_row(
	parent: VBoxContainer,
	action: StringName,
	action_name: String
) -> void:

	# 建立按鍵列場景
	var row_node := key_row_scene.instantiate()

	var row := row_node as HBoxContainer

	if row == null:

		push_error(
			"KeyBindingRow 根節點必須是 HBoxContainer"
		)

		row_node.free()

		return

	# 取得操作標籤
	var action_label := (
		row.get_node_or_null("ActionLabel")
		as Label
	)

	# 取得按鍵元件
	var key_button := (
		row.get_node_or_null("KeyButton")
		as DreamKeyButton
	)

	if action_label == null or key_button == null:

		push_error(
			"KeyBindingRow 缺少 ActionLabel 或 KeyButton"
		)

		row_node.free()

		return

	parent.add_child(row)

	# 設定操作名稱
	action_label.text = action_name

	# 讀取目前實際按鍵
	key_button.text = (
		InputSettingsManager.get_binding_text(
			action
		)
	)

	# --------------------------------------------------------
	# 操作名稱外觀
	# --------------------------------------------------------

	action_label.add_theme_font_size_override(
		"font_size",
		28
	)

	action_label.add_theme_color_override(
		"font_color",
		Color("#F5E8F5")
	)

	# --------------------------------------------------------
	# 按鍵文字外觀
	# --------------------------------------------------------

	key_button.add_theme_font_size_override(
		"font_size",
		24
	)

	key_button.add_theme_color_override(
		"font_color",
		Color("#E5C7E3")
	)

	# 共用字體
	if ui_font != null:

		action_label.add_theme_font_override(
			"font",
			ui_font
		)

		key_button.add_theme_font_override(
			"font",
			ui_font
		)

	# 點擊放開後才進入修改模式
	key_button.action_mode = (
		BaseButton.ACTION_MODE_BUTTON_RELEASE
	)

	# 記錄按鈕
	_key_buttons[action] = key_button

	# 記錄中文名稱
	_action_names[action] = action_name

	# 點擊按鍵開始偵測
	key_button.pressed.connect(
		_begin_capture.bind(action)
	)


# ============================================================
# 更新所有按鍵顯示
# ============================================================

func _refresh_all_keys() -> void:

	for action in _key_buttons:

		var button: DreamKeyButton = (
			_key_buttons[action]
		)

		if not is_instance_valid(button):
			continue

		button.text = (
			InputSettingsManager.get_binding_text(
				action
			)
		)


# ============================================================
# 開始修改按鍵
# ============================================================

func _begin_capture(
	action: StringName
) -> void:

	# 同時只能修改一個操作
	if _waiting_action != &"":
		return

	if not _key_buttons.has(action):
		return

	# 清除之前的狀態
	_clear_button_states()

	_waiting_action = action

	_pending_event = null

	_held_capture_tokens.clear()

	_combo_blocked = false

	var button: DreamKeyButton = (
		_key_buttons[action]
	)

	# 解除焦點
	button.release_focus()

	# 顯示等待文字
	button.text = "請輸入..."

	# 等待動畫
	button.set_waiting(true)

	_set_status(
		"請按下新的按鍵或滑鼠按鈕　｜　ESC 取消",
		waiting_text_color
	)

	# 開始監聽輸入
	set_process_input(true)


# ============================================================
# ESC 判斷
# ============================================================

func _is_escape_key(
	event: InputEventKey
) -> bool:

	return (
		event.keycode == KEY_ESCAPE
		or event.physical_keycode == KEY_ESCAPE
	)


# ============================================================
# 取得輸入識別碼
# ============================================================

# 使用識別碼確認按下與放開的是同一個輸入

func _get_input_token(
	event: InputEvent
) -> String:

	if event is InputEventKey:

		if event.physical_keycode != 0:

			return (
				"key:physical:"
				+ str(int(event.physical_keycode))
			)

		if event.keycode != 0:

			return (
				"key:logical:"
				+ str(int(event.keycode))
			)

	if event is InputEventMouseButton:

		# 滾輪不需要等待放開
		if event.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN
		]:

			return ""

		return (
			"mouse:"
			+ str(int(event.button_index))
		)

	return ""


# ============================================================
# 偵測玩家輸入
# ============================================================

func _input(event: InputEvent) -> void:

	if _waiting_action == &"":
		return

	# --------------------------------------------------------
	# 鍵盤
	# --------------------------------------------------------

	if event is InputEventKey:

		# 忽略長按重複事件
		if event.is_echo():

			get_viewport().set_input_as_handled()

			return

		# 按下
		if event.is_pressed():

			get_viewport().set_input_as_handled()

			# ESC 取消
			if _is_escape_key(event):

				_cancel_capture()

				return

			_handle_capture_press(event)

			return

		# 放開
		if event.is_released():

			get_viewport().set_input_as_handled()

			_handle_capture_release(event)

			return

	# --------------------------------------------------------
	# 滑鼠
	# --------------------------------------------------------

	if event is InputEventMouseButton:

		# ----------------------------
		# 滑鼠滾輪
		# ----------------------------

		if event.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN
		]:

			if not event.is_pressed():
				return

			get_viewport().set_input_as_handled()

			# 不允許與其他按鍵組合
			if not _held_capture_tokens.is_empty():

				_pending_event = null

				_combo_blocked = true

				_set_status(
					"請單獨輸入滑鼠滾輪",
					conflict_text_color
				)

				return

			if _combo_blocked:
				return

			var wheel_event := (
				InputSettingsManager.normalize_event(
					event
				)
			)

			if wheel_event == null:

				_set_status(
					"不支援此滑鼠輸入",
					conflict_text_color
				)

				return

			# 滾輪為瞬間事件，直接完成捕捉
			_finish_capture(wheel_event)

			return

		# ----------------------------
		# 一般滑鼠按鍵
		# ----------------------------

		if event.is_pressed():

			get_viewport().set_input_as_handled()

			_handle_capture_press(event)

			return

		if event.is_released():

			get_viewport().set_input_as_handled()

			_handle_capture_release(event)

			return


# ============================================================
# 處理按下輸入
# ============================================================

func _handle_capture_press(
	event: InputEvent
) -> void:

	var token := _get_input_token(event)

	if token.is_empty():
		return

	# 忽略重複按下
	if _held_capture_tokens.has(token):
		return

	# 已經有其他按鍵被按住
	# 視為組合鍵
	if not _held_capture_tokens.is_empty():

		_held_capture_tokens[token] = true

		_pending_event = null

		_combo_blocked = true

		_set_status(
			"目前不支援組合鍵，請一次按下一個按鍵",
			conflict_text_color
		)

		return

	# 記錄按住的輸入
	_held_capture_tokens[token] = true

	if _combo_blocked:
		return

	# 標準化輸入
	var normalized := (
		InputSettingsManager.normalize_event(
			event
		)
	)

	if normalized == null:

		_pending_event = null

		_combo_blocked = true

		_set_status(
			"不支援此輸入，請單獨按下一個按鍵",
			conflict_text_color
		)

		return

	_pending_event = normalized


# ============================================================
# 處理放開輸入
# ============================================================

func _handle_capture_release(
	event: InputEvent
) -> void:

	var token := _get_input_token(event)

	if not token.is_empty():

		_held_capture_tokens.erase(token)

	# 組合鍵狀態
	if _combo_blocked:

		if _held_capture_tokens.is_empty():

			_combo_blocked = false

		return

	if _pending_event == null:
		return

	# 必須放開剛剛按下的同一個按鍵
	if not _same_capture_event(
		event,
		_pending_event
	):

		return

	var captured_event: InputEvent = (
		_pending_event
	)

	_finish_capture(captured_event)


# ============================================================
# 比較按下與放開的輸入
# ============================================================

func _same_capture_event(
	first: InputEvent,
	second: InputEvent
) -> bool:

	var first_token := _get_input_token(first)

	var second_token := _get_input_token(second)

	return (
		not first_token.is_empty()
		and first_token == second_token
	)


# ============================================================
# 完成按鍵輸入
# ============================================================

func _finish_capture(
	event: InputEvent
) -> void:

	if _waiting_action == &"":
		return

	var action := _waiting_action

	# 記錄修改前的按鍵
	var previous_text := (
		InputSettingsManager.get_binding_text(
			action
		)
	)

	# 再次確認輸入有效性
	var normalized := (
		InputSettingsManager.normalize_event(
			event
		)
	)

	# 停止等待輸入
	_stop_capture()

	if normalized == null:

		_set_status(
			"無效的按鍵輸入",
			conflict_text_color
		)

		return

	# --------------------------------------------------------
	# 偵測按鍵衝突
	# --------------------------------------------------------

	var conflict := (
		InputSettingsManager.find_conflict(
			action,
			normalized
		)
	)

	if conflict != &"":

		_show_conflict(
			action,
			conflict
		)

		return

	# --------------------------------------------------------
	# 沒有衝突，正式修改
	# --------------------------------------------------------

	var success: bool = (
		InputSettingsManager.rebind(
			action,
			normalized
		)
	)

	var button: DreamKeyButton = (
		_key_buttons[action]
	)

	if success:

		button.play_success()

		_refresh_all_keys()

		var current_text := (
			InputSettingsManager.get_binding_text(
				action
			)
		)

		if previous_text == current_text:

			_set_status(
				"按鍵沒有變更，已保留原設定",
				normal_text_color
			)

		else:

			_set_status(
				"按鍵已修改並成功儲存",
				success_text_color
			)

	else:

		button.set_conflict(true)

		_set_status(
			"設定儲存失敗，已保留原本按鍵",
			conflict_text_color
		)


# ============================================================
# 顯示按鍵衝突
# ============================================================

func _show_conflict(
	action: StringName,
	conflict: StringName
) -> void:

	# 清除之前的動畫
	_clear_button_states()

	# 修改中的按鍵顯示紅色
	if _key_buttons.has(action):

		var first_button: DreamKeyButton = (
			_key_buttons[action]
		)

		first_button.set_conflict(true)

	# 如果衝突對象也是可修改操作
	if _key_buttons.has(conflict):

		var second_button: DreamKeyButton = (
			_key_buttons[conflict]
		)

		second_button.set_conflict(true)

	# 取得衝突操作名稱
	var conflict_name := (
		_get_action_display_name(conflict)
	)

	_set_status(
		"此按鍵已被「"
		+ conflict_name
		+ "」使用，原設定保持不變",
		conflict_text_color
	)


# ============================================================
# 取得操作顯示名稱
# ============================================================

func _get_action_display_name(
	action: StringName
) -> String:

	# 玩家可以修改的操作
	if _action_names.has(action):

		return String(
			_action_names[action]
		)

	# 固定操作
	match action:

		&"interact":
			return "互動（固定操作）"

		&"portal_interact":
			return "傳送互動（固定操作）"

		&"ESC":
			return "系統返回與取消"

		&"enter":
			return "確認操作（固定）"

	return String(action)


# ============================================================
# 取消按鍵修改
# ============================================================

func _cancel_capture() -> void:

	if _waiting_action == &"":
		return

	_stop_capture()

	_clear_button_states()

	_set_status(
		"已取消修改，原本的按鍵保持不變",
		normal_text_color
	)


# ============================================================
# 停止等待輸入
# ============================================================

func _stop_capture() -> void:

	# 停止目前按鍵的等待動畫
	if _key_buttons.has(_waiting_action):

		var button: DreamKeyButton = (
			_key_buttons[_waiting_action]
		)

		button.set_waiting(false)

	# 清除輸入資料
	_waiting_action = &""

	_pending_event = null

	_held_capture_tokens.clear()

	_combo_blocked = false

	# 停止輸入監聽
	set_process_input(false)

	# 恢復真實按鍵文字
	_refresh_all_keys()


# ============================================================
# 清除按鍵動畫狀態
# ============================================================

func _clear_button_states() -> void:

	for action in _key_buttons:

		var button: DreamKeyButton = (
			_key_buttons[action]
		)

		if not is_instance_valid(button):
			continue

		button.clear_state()


# ============================================================
# 恢復預設按鈕：滑鼠移入
# ============================================================

# 使用 MainMenuPage 的共用 Hover 訊號。
# MenuActions 收到後會呼叫 MainMenuAudio.play_hover()。

func _on_reset_button_hovered() -> void:

	hover_requested.emit()


# ============================================================
# 恢復預設按鈕：點擊
# ============================================================

# 不開啟確認視窗。
# 點擊後直接恢復、儲存並更新所有按鍵。
#
# Confirm 音效交給 MenuActions 播放，
# 不在此處直接操作 AudioStreamPlayer。

func _on_reset_button_pressed() -> void:

	# 播放共用確認音效
	option_requested.emit(&"Confirm")

	# 如果正在修改按鍵，先取消修改
	if _waiting_action != &"":

		_cancel_capture()

	# 清除目前所有按鍵視覺狀態
	_clear_button_states()

	# 直接呼叫全域管理器恢復原始預設
	# 管理器負責驗證、儲存及套用 Input Map
	var success: bool = (
		InputSettingsManager.reset_to_defaults()
	)

	# --------------------------------------------------------
	# 恢復成功
	# --------------------------------------------------------

	if success:

		_refresh_all_keys()

		_set_status(
			"已恢復原始預設按鍵並成功儲存",
			success_text_color
		)

	# --------------------------------------------------------
	# 恢復失敗
	# --------------------------------------------------------

	else:

		_set_status(
			"恢復預設失敗，原本設定已保留",
			conflict_text_color
		)


# ============================================================
# 更新底部提示
# ============================================================

func _set_status(
	message: String,
	color: Color
) -> void:

	if status_label == null:
		return

	status_label.text = message

	status_label.add_theme_color_override(
		"font_color",
		color
	)


# ============================================================
# 處理頁面隱藏
# ============================================================

func _on_page_visibility_changed() -> void:

	if is_visible_in_tree():
		return

	# 關閉頁面時取消未完成的修改
	if _waiting_action != &"":

		_cancel_capture()

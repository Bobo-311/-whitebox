
class_name DreamKeyButton
extends Button


# ============================================================
# 眠境 RE:RECOLOR
# 動態按鍵視覺元件
#
# 本腳本只負責視覺效果
# 不直接修改 Godot Input Map
#
# 功能：
# 1. 滑鼠懸停動畫
# 2. 點擊發光回饋
# 3. 上下邊框流光
# 4. 等待輸入呼吸動畫
# 5. 按鍵衝突提示
# 6. 綁定成功動畫
# 7. 動畫結束自動停止處理
# ============================================================


# ============================================================
# 按鍵視覺狀態
# ============================================================

enum KeyVisualState {

	IDLE,
	WAITING,
	CONFLICT

}


# ============================================================
# 外觀設定
# ============================================================

@export_group("外觀設定")

# 一般邊框顏色
@export var normal_color: Color = Color("#B9A1C580")

# 滑鼠懸停顏色
@export var hover_color: Color = Color("#F5D7F2")

# 綁定成功顏色
@export var success_color: Color = Color("#C1DFC9")

# 按鍵衝突顏色
@export var conflict_color: Color = Color("#E9A4B2")


# ============================================================
# 動畫設定
# ============================================================

@export_group("動畫設定")

# 數值越高，動畫反應越快
@export_range(1.0, 40.0, 0.5)
var animation_speed: float = 16.0

# 邊框流光速度
@export_range(0.1, 3.0, 0.05)
var flow_speed: float = 0.65

# 呼吸動畫循環時間
@export_range(0.2, 5.0, 0.1)
var breath_duration: float = 1.5


# ============================================================
# 內部狀態
# ============================================================

# 目前按鍵視覺狀態
var _state: KeyVisualState = KeyVisualState.IDLE

# 共用按鍵樣式
var _frame: StyleBoxFlat

# 滑鼠是否位於按鍵上
var _hovered: bool = false

# 按鍵是否正在被按住
var _held: bool = false

# 動畫累積時間
var _time: float = 0.0

# 邊框亮度
var _strength: float = 0.0

# 流光強度
var _flow_strength: float = 0.0

# 點擊瞬間的發光強度
var _flash: float = 0.0

# 成功動畫的發光強度
var _success: float = 0.0


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 建立按鍵樣式
	_setup_style()

	# 監聽滑鼠進入
	mouse_entered.connect(
		_on_mouse_entered
	)

	# 監聽滑鼠離開
	mouse_exited.connect(
		_on_mouse_exited
	)

	# 監聽按下
	button_down.connect(
		_on_button_down
	)

	# 監聽放開
	button_up.connect(
		_on_button_up
	)

	# 監聽鍵盤焦點
	focus_entered.connect(
		_wake
	)

	focus_exited.connect(
		_wake
	)

	# 尺寸改變時重新繪製
	resized.connect(
		queue_redraw
	)

	# 顯示狀態改變時重新啟動動畫
	visibility_changed.connect(
		_wake
	)

	# 更新初始外觀
	_update_style()

	_wake()


# ============================================================
# 建立按鍵框樣式
# ============================================================

func _setup_style() -> void:

	_frame = StyleBoxFlat.new()

	# 淡紫色半透明背景
	_frame.bg_color = Color("#B9A1C512")

	# 初始邊框顏色
	_frame.border_color = normal_color

	# 邊框厚度
	_frame.set_border_width_all(1)

	# 圓角
	_frame.set_corner_radius_all(4)

	# 外圍柔和光暈
	_frame.shadow_size = 5

	_frame.shadow_color = Color.TRANSPARENT

	_frame.shadow_offset = Vector2.ZERO

	# 統一所有按鈕狀態的樣式
	for style_name in [

		"normal",
		"hover",
		"pressed",
		"hover_pressed",
		"disabled"

	]:

		add_theme_stylebox_override(
			style_name,
			_frame
		)

	# 移除 Godot 預設焦點框
	# 改由本腳本控制視覺回饋
	add_theme_stylebox_override(
		"focus",
		StyleBoxEmpty.new()
	)

	# 統一按鍵文字顏色
	for color_name in [

		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color"

	]:

		add_theme_color_override(
			color_name,
			Color("#E5C7E3")
		)


# ============================================================
# 每幀更新動畫
# ============================================================

func _process(delta: float) -> void:

	# 隱藏時停止動畫
	if not is_visible_in_tree():

		set_process(false)

		return

	_time += delta

	var target_strength: float = 0.0

	var target_flow: float = 0.0

	# --------------------------------------------------------
	# 等待輸入或衝突狀態
	# --------------------------------------------------------

	if _state != KeyVisualState.IDLE:

		# 正弦波呼吸動畫
		var breath: float = (
			sin(
				_time * TAU / breath_duration
			) * 0.5 + 0.5
		)

		target_strength = (
			0.55 + breath * 0.45
		)

		target_flow = 0.8

	# --------------------------------------------------------
	# 按住按鈕
	# --------------------------------------------------------

	elif _held:

		target_strength = 1.0

		target_flow = 1.0

	# --------------------------------------------------------
	# 滑鼠懸停
	# --------------------------------------------------------

	elif _hovered:

		target_strength = 0.85

		target_flow = 1.0

	# --------------------------------------------------------
	# 鍵盤焦點
	# --------------------------------------------------------

	elif has_focus():

		target_strength = 0.25

	# --------------------------------------------------------
	# 平滑插值
	# --------------------------------------------------------

	var weight: float = (
		1.0 - exp(
			-animation_speed * delta
		)
	)

	_strength = lerpf(
		_strength,
		target_strength,
		weight
	)

	_flow_strength = lerpf(
		_flow_strength,
		target_flow,
		weight
	)

	# --------------------------------------------------------
	# 點擊光效消退
	# --------------------------------------------------------

	_flash = move_toward(
		_flash,
		0.0,
		delta * 3.5
	)

	# --------------------------------------------------------
	# 成功光效消退
	# --------------------------------------------------------

	_success = move_toward(
		_success,
		0.0,
		delta * 2.5
	)

	# 更新外觀
	_update_style()

	# 重新繪製流光
	queue_redraw()

	# --------------------------------------------------------
	# 動畫結束後停止每幀運算
	# --------------------------------------------------------

	if _state == KeyVisualState.IDLE:

		if not _hovered and not _held:

			if _flash == 0.0 and _success == 0.0:

				if absf(
					_strength - target_strength
				) < 0.001:

					if _flow_strength < 0.001:

						_strength = target_strength

						_flow_strength = 0.0

						_update_style()

						queue_redraw()

						# 停止動畫處理
						set_process(false)


# ============================================================
# 更新按鍵框外觀
# ============================================================

func _update_style() -> void:

	# 取得目前狀態顏色
	var accent: Color = _get_accent_color()

	# 取得最強發光效果
	var power: float = maxf(
		_strength,
		maxf(
			_flash,
			_success
		)
	)

	# --------------------------------------------------------
	# 邊框顏色
	# --------------------------------------------------------

	_frame.border_color = normal_color.lerp(
		accent,
		power
	)

	# --------------------------------------------------------
	# 半透明背景
	# --------------------------------------------------------

	var background: Color = accent

	background.a = (
		0.07 + power * 0.12
	)

	_frame.bg_color = background

	# --------------------------------------------------------
	# 外圍柔和光暈
	# --------------------------------------------------------

	var glow: Color = accent

	glow.a = power * 0.28

	_frame.shadow_color = glow


# ============================================================
# 取得目前狀態顏色
# ============================================================

func _get_accent_color() -> Color:

	# 衝突：淡紅色
	if _state == KeyVisualState.CONFLICT:

		return conflict_color

	# 成功：淡綠色
	if _success > 0.0:

		return hover_color.lerp(
			success_color,
			_success
		)

	# 一般互動：粉紫色
	return hover_color


# ============================================================
# 繪製上下邊框流光
# ============================================================

func _draw() -> void:

	# 沒有流光時不繪製
	if _flow_strength < 0.01:
		return

	if size.x < 12.0:
		return

	var top_points := PackedVector2Array()

	var bottom_points := PackedVector2Array()

	var colors := PackedColorArray()

	# 計算流光循環進度
	var progress: float = fmod(
		_time * flow_speed,
		1.0
	)

	# 光芒由左側外部進入，向右側離開
	var flow_position: float = lerpf(
		-0.25,
		1.25,
		progress
	)

	var accent: Color = _get_accent_color()

	# 流光平滑度
	const SEGMENTS: int = 32

	for i in range(SEGMENTS + 1):

		var t: float = (
			float(i) / float(SEGMENTS)
		)

		# 計算目前線條位置
		var x: float = lerpf(
			5.0,
			size.x - 5.0,
			t
		)

		# 計算光芒距離
		var distance: float = (
			(t - flow_position) / 0.16
		)

		# 柔和高斯光效
		var light: float = exp(
			-distance * distance
		)

		var color: Color = accent

		color.a = (
			light * _flow_strength
		)

		# 上方光芒
		top_points.append(
			Vector2(
				x,
				1.0
			)
		)

		# 下方光芒反向移動
		bottom_points.append(
			Vector2(
				size.x - x,
				size.y - 1.0
			)
		)

		colors.append(color)

	# 繪製上方流光
	draw_polyline_colors(
		top_points,
		colors,
		2.0,
		true
	)

	# 繪製下方流光
	draw_polyline_colors(
		bottom_points,
		colors,
		2.0,
		true
	)


# ============================================================
# 滑鼠進入
# ============================================================

func _on_mouse_entered() -> void:

	_hovered = true

	_wake()


# ============================================================
# 滑鼠離開
# ============================================================

func _on_mouse_exited() -> void:

	_hovered = false

	_wake()


# ============================================================
# 按下按鈕
# ============================================================

func _on_button_down() -> void:

	_held = true

	# 點擊瞬間產生發光效果
	_flash = 1.0

	_wake()


# ============================================================
# 放開按鈕
# ============================================================

func _on_button_up() -> void:

	_held = false

	_wake()


# ============================================================
# 重新啟動動畫
# ============================================================

func _wake() -> void:

	set_process(true)


# ============================================================
# 對外提供的狀態控制功能
# ============================================================


# ------------------------------------------------------------
# 等待輸入動畫
# ------------------------------------------------------------

func set_waiting(
	active: bool
) -> void:

	if active:

		_state = KeyVisualState.WAITING

	else:

		_state = KeyVisualState.IDLE

	_wake()


# ------------------------------------------------------------
# 按鍵衝突動畫
# ------------------------------------------------------------

func set_conflict(
	active: bool
) -> void:

	if active:

		_state = KeyVisualState.CONFLICT

	else:

		_state = KeyVisualState.IDLE

	_wake()


# ------------------------------------------------------------
# 按鍵綁定成功動畫
# ------------------------------------------------------------

func play_success() -> void:

	_state = KeyVisualState.IDLE

	_success = 1.0

	_flash = 0.0

	_wake()


# ------------------------------------------------------------
# 清除所有狀態
# ------------------------------------------------------------

func clear_state() -> void:

	_state = KeyVisualState.IDLE

	_success = 0.0

	_flash = 0.0

	_wake()

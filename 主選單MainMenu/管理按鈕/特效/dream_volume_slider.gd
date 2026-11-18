extends HSlider

# ========================================
# 眠境 RE:RECOLOR - 音量滑桿視覺元件
# 負責外觀、光效及互動動畫
# 保留 Godot 原生 HSlider 操作功能
# ========================================

@export_group("滑軌外觀")
@export var track_height: float = 5.0
@export var track_color: Color = Color("#84778F")
@export var start_color: Color = Color("#A594CF")
@export var end_color: Color = Color("#EDBCD9")

@export_group("水晶外觀")
@export var crystal_width: float = 10.0
@export var crystal_height: float = 15.0
@export var crystal_color: Color = Color("#F2D9ED")
@export var crystal_border: Color = Color("#CEACDC")

@export_group("動畫設定")
@export var animation_speed: float = 12.0
@export var hover_scale: float = 1.15
@export var drag_scale: float = 1.25
@export var breath_strength: float = 0.035
@export var flow_speed: float = 0.8

const GRABBER_SIZE: int = 40

var _time: float = 0.0
var _hovered: bool = false
var _dragging: bool = false
var _current_scale: float = 1.0
var _glow: float = 0.0


func _ready() -> void:
	_setup_native_slider()

	# 滑鼠互動與拖曳事件
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	drag_started.connect(_on_drag_started)
	drag_ended.connect(_on_drag_ended)

	queue_redraw()


# ========================================
# 隱藏原生滑桿外觀，保留原生操作
# ========================================

func _setup_native_slider() -> void:
	var empty_style := StyleBoxEmpty.new()

	add_theme_stylebox_override("slider", empty_style)
	add_theme_stylebox_override("grabber_area", empty_style)
	add_theme_stylebox_override("grabber_area_highlight", empty_style)

	# 透明滑塊：保留滑鼠拖曳與點擊範圍
	var img := Image.create_empty(
		GRABBER_SIZE,
		GRABBER_SIZE,
		false,
		Image.FORMAT_RGBA8
	)

	img.fill(Color.TRANSPARENT)

	var texture := ImageTexture.create_from_image(img)

	add_theme_icon_override("grabber", texture)
	add_theme_icon_override("grabber_highlight", texture)
	add_theme_icon_override("grabber_disabled", texture)

	add_theme_constant_override("center_grabber", 0)
	add_theme_constant_override("grabber_offset", 0)

	tick_count = 0


# ========================================
# 動畫更新
# ========================================

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	_time += delta

	var target_scale: float = 1.0
	var target_glow: float = 0.0

	if _dragging:
		target_scale = drag_scale
		target_glow = 1.0

	elif _hovered or has_focus():
		target_scale = hover_scale
		target_glow = 0.6

	else:
		# 待機時輕微呼吸
		target_scale += sin(_time * 1.5) * breath_strength

	var weight: float = 1.0 - exp(-animation_speed * delta)

	_current_scale = lerpf(
		_current_scale,
		target_scale,
		weight
	)

	_glow = lerpf(_glow, target_glow, weight)

	queue_redraw()


# ========================================
# 繪製滑軌與水晶
# ========================================

func _draw() -> void:
	var left: float = GRABBER_SIZE * 0.5
	var right: float = size.x - left

	if right <= left:
		return

	var center_y: float = size.y * 0.5
	var ratio: float = get_as_ratio()
	var grabber_x: float = lerpf(left, right, ratio)

	var start := Vector2(left, center_y)
	var finish := Vector2(right, center_y)
	var grabber := Vector2(grabber_x, center_y)

	# 尚未填滿的滑軌
	draw_line(
		start,
		finish,
		track_color,
		track_height,
		true
	)

	# 已填滿的漸層滑軌
	if ratio > 0.0:
		_draw_gradient_track(start, grabber)

	# 菱形水晶滑塊
	_draw_crystal(grabber)


func _draw_gradient_track(
	start: Vector2,
	finish: Vector2
) -> void:

	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var glow_colors := PackedColorArray()

	const SEGMENTS: int = 48

	# 光芒由左至右流動
	var progress: float = fmod(_time * flow_speed, 1.0)
	var flow_position: float = lerpf(-0.25, 1.25, progress)

	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var point: Vector2 = start.lerp(finish, t)
		var color: Color = start_color.lerp(end_color, t)

		# 集中的流光，增加移動的辨識度
		var distance: float = (t - flow_position) / 0.12
		var light: float = exp(-distance * distance)

		color = color.lerp(
			Color.WHITE,
			light * _glow * 0.85
		)

		var soft_glow: Color = color
		soft_glow.a = light * _glow * 0.22

		points.append(point)
		colors.append(color)
		glow_colors.append(soft_glow)

	# 流動光暈
	draw_polyline_colors(
		points,
		glow_colors,
		track_height + 7.0,
		true
	)

	# 主滑軌
	draw_polyline_colors(
		points,
		colors,
		track_height,
		true
	)


# ========================================
# 雙層菱形水晶
# ========================================

func _draw_crystal(center: Vector2) -> void:
	var w: float = crystal_width * _current_scale
	var h: float = crystal_height * _current_scale

	var outer := PackedVector2Array([
		center + Vector2(0, -h),
		center + Vector2(w, 0),
		center + Vector2(0, h),
		center + Vector2(-w, 0)
	])

	var outline := outer.duplicate()
	outline.append(outer[0])

	# 柔和光暈
	if _glow > 0.01:
		draw_polyline(
			outline,
			Color(0.85, 0.65, 0.9, _glow * 0.13),
			9.0,
			true
		)

		draw_polyline(
			outline,
			Color(0.95, 0.8, 0.95, _glow * 0.2),
			5.0,
			true
		)

	# 外層水晶
	draw_colored_polygon(
		outer,
		Color("#655372")
	)

	draw_polyline(
		outline,
		crystal_border,
		1.6,
		true
	)

	# 內層水晶
	var inner := PackedVector2Array([
		center + Vector2(0, -h * 0.65),
		center + Vector2(w * 0.58, 0),
		center + Vector2(0, h * 0.65),
		center + Vector2(-w * 0.58, 0)
	])

	draw_colored_polygon(
		inner,
		crystal_color.lerp(Color.WHITE, _glow * 0.35)
	)


# ========================================
# 互動事件
# ========================================

func _on_mouse_entered() -> void:
	_hovered = true


func _on_mouse_exited() -> void:
	_hovered = false


func _on_drag_started() -> void:
	_dragging = true


func _on_drag_ended(_value_changed: bool) -> void:
	_dragging = false

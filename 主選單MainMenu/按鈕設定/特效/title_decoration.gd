@tool
extends Control

## 共用標題裝飾元件
## 負責雙曲線、流動波浪、漸層色彩與星光呼吸
## 可套用於所有主選單子頁面


# ========================================
# 裝飾外觀設定
# ========================================

@export_group("裝飾外觀設定")

# 裝飾線條的總寬度
@export_range(100.0, 800.0, 10.0)
var decoration_width: float = 460.0:
	set(value):
		decoration_width = value
		queue_redraw()

# 波浪起伏幅度
@export_range(0.0, 30.0, 0.5)
var wave_height: float = 16.0:
	set(value):
		wave_height = value
		queue_redraw()

# 整體透明度
@export_range(0.0, 1.0, 0.05)
var decoration_opacity: float = 0.85:
	set(value):
		decoration_opacity = value
		queue_redraw()

# 中央星光大小
@export_range(2.0, 20.0, 0.5)
var star_size: float = 8.0:
	set(value):
		star_size = value
		queue_redraw()


# ========================================
# 動畫設定
# ========================================

@export_group("動畫設定")

# 是否啟用動畫
@export var animation_enabled: bool = true:
	set(value):
		animation_enabled = value
		_elapsed = 0.0

		if is_inside_tree():
			set_process(
				value and not Engine.is_editor_hint()
			)

		queue_redraw()

# 完成一次波浪循環的時間
@export_range(1.0, 15.0, 0.1)
var animation_cycle: float = 3.6

# 漸層顏色的流動幅度
@export_range(0.0, 0.15, 0.005)
var color_flow_strength: float = 0.065

# 中央星光的呼吸幅度
@export_range(0.0, 0.2, 0.01)
var star_breath_strength: float = 0.1


# ========================================
# 漸層配色與內部變數
# ========================================

const LEFT_COLOR := Color("#9C92D5")
const CENTER_COLOR := Color("#F1D4E9")
const RIGHT_COLOR := Color("#CE95B4")

# 曲線取樣數量
const SAMPLE_COUNT: int = 96

# 動畫累積時間
var _elapsed: float = 0.0


# ========================================
# 初始化
# ========================================

func _ready() -> void:

	# 節點尺寸發生變化時重新繪製
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)

	# 編輯器只顯示靜態預覽
	# 遊戲運行時才啟用動畫
	set_process(
		animation_enabled and not Engine.is_editor_hint()
	)

	queue_redraw()


# ========================================
# 更新動畫
# ========================================

func _process(delta: float) -> void:

	# 不可見時停止更新動畫
	if not animation_enabled or not is_visible_in_tree():
		return

	var cycle: float = maxf(animation_cycle, 0.1)

	# 保持動畫無縫循環
	_elapsed = fposmod(_elapsed + delta, cycle)

	queue_redraw()


# ========================================
# 繪製裝飾
# ========================================

func _draw() -> void:

	if size.x <= 0.0 or size.y <= 0.0:
		return

	var center: Vector2 = size * 0.5
	var phase: float = 0.0
	var breath: float = 0.0

	# 計算動畫相位
	if animation_enabled and not Engine.is_editor_hint():

		var cycle: float = maxf(animation_cycle, 0.1)

		phase = (_elapsed / cycle) * TAU
		breath = sin(phase)

	# 先畫次要曲線，再畫主要曲線
	_draw_wave(center, phase, breath, true)
	_draw_wave(center, phase, breath, false)

	# 最後畫中央星光
	_draw_star(center, breath)


# ========================================
# 繪製動態漸層波浪
# ========================================

func _draw_wave(
	center: Vector2,
	phase: float,
	breath: float,
	secondary: bool
) -> void:

	var points := PackedVector2Array()
	var colors := PackedColorArray()

	var width: float = minf(decoration_width, size.x)

	for i in range(SAMPLE_COUNT + 1):

		var t: float = float(i) / float(SAMPLE_COUNT)

		var x: float = lerpf(
			-width * 0.5,
			width * 0.5,
			t
		)

		# 計算目前位置與中央的距離
		# 使左右波浪由中心向外對稱流動
		var distance: float = absf(t * 2.0 - 1.0)

		# 固定中央與左右端點
		# 避免整個裝飾隨動畫上下飄動
		var envelope: float = maxf(
			sin(distance * PI),
			0.0
		)

		# 產生持續向外傳遞的波浪
		var wave: float = sin(
			distance * TAU * 1.2 - phase
		)

		var y: float = wave * wave_height * envelope

		var strength: float = 1.0

		# 次要曲線反向運動，形成交織效果
		if secondary:
			y = -y * 0.65
			strength = 0.5

		# 線條兩端逐漸透明
		var edge_fade: float = smoothstep(
			0.0,
			0.22,
			minf(t, 1.0 - t)
		)

		# 柔和的色彩流動
		var color_offset: float = breath * color_flow_strength

		var color: Color = _get_gradient_color(
			t + color_offset
		)

		color.a = (
			edge_fade
			* strength
			* decoration_opacity
		)

		points.append(center + Vector2(x, y))
		colors.append(color)

	# 次要曲線較細，主要曲線較明顯
	var line_width: float = 1.0 if secondary else 2.0

	# 啟用抗鋸齒
	draw_polyline_colors(
		points,
		colors,
		line_width,
		true
	)


# ========================================
# 計算漸層顏色
# ========================================

func _get_gradient_color(t: float) -> Color:

	t = clampf(t, 0.0, 1.0)

	# 左側紫色逐漸過渡到中央淡粉色
	if t < 0.5:
		return LEFT_COLOR.lerp(
			CENTER_COLOR,
			t * 2.0
		)

	# 中央淡粉色逐漸過渡到右側粉色
	return CENTER_COLOR.lerp(
		RIGHT_COLOR,
		(t - 0.5) * 2.0
	)


# ========================================
# 中央星光與呼吸動畫
# ========================================

func _draw_star(center: Vector2, breath: float) -> void:

	var scale_factor: float = 1.0
	var brightness: float = 1.0

	if animation_enabled and not Engine.is_editor_hint():

		# 緩慢放大與縮小
		scale_factor += breath * star_breath_strength

		# 柔和的亮度變化
		brightness -= star_breath_strength * (1.0 - breath)

	var s: float = star_size * scale_factor

	# 多層低透明度光暈
	for i in range(4, 0, -1):

		var radius: float = s + float(i) * 2.0

		var glow := Color(
			0.95,
			0.76,
			0.88,
			0.02 * decoration_opacity * brightness
		)

		draw_circle(center, radius, glow)

	# 四角星光形狀
	var star_points := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s * 0.25, -s * 0.25),
		center + Vector2(s, 0),
		center + Vector2(s * 0.25, s * 0.25),
		center + Vector2(0, s),
		center + Vector2(-s * 0.25, s * 0.25),
		center + Vector2(-s, 0),
		center + Vector2(-s * 0.25, -s * 0.25)
	])

	var star_color := Color("#F5D8E8")

	star_color.a = decoration_opacity * brightness

	draw_colored_polygon(star_points, star_color)

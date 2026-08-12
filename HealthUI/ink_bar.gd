extends Control
class_name InkBar

enum Mode { BLUE, RED, YELLOW }

# ==========================================
# ⚙️ 屬性設定
# ==========================================
@export_group("Ink Settings")
@export var max_ink: float = 60.0:
	set(value):
		max_ink = value
		_update_bar_size()
		queue_redraw()

@export var current_ink: float = 60.0:
	set(value):
		current_ink = clamp(value, 0.0, max_ink)
		queue_redraw()

# 每 1 點墨水占用的像素寬度 (數值越大，UI 越長)
@export var pixels_per_ink: float = 2.5 
@export var bar_height: float = 14.0

@export_group("Style Colors")
@export var bg_color: Color = Color(0.1, 0.1, 0.12, 0.8) # 空管底色
@export var border_color: Color = Color(1.0, 1.0, 1.0, 0.9) # 外框顏色
@export var tick_color: Color = Color(1.0, 1.0, 1.0, 0.75) # 刻度線顏色

@export var blue_color: Color = Color(0.2, 0.55, 0.95)   # 藍色手槍
@export var red_color: Color = Color(0.95, 0.25, 0.25)   # 紅色狙擊
@export var yellow_color: Color = Color(0.95, 0.8, 0.15)  # 黃色散彈

var current_mode: Mode = Mode.BLUE

func _ready() -> void:
	_update_bar_size()

# 根據上限更新物理寬度 (實體伸長)
func _update_bar_size() -> void:
	var total_width = max_ink * pixels_per_ink
	custom_minimum_size = Vector2(total_width, bar_height)
	size = custom_minimum_size

# ==========================================
# 🔄 外部對接 API
# ==========================================

# 切換攻擊模式 (BLUE, RED, YELLOW)
func set_mode(new_mode: Mode) -> void:
	current_mode = new_mode
	queue_redraw()

# 同步玩家目前的墨水數值
func update_ink(current: float, maximum: float = -1.0) -> void:
	if maximum > 0 and maximum != max_ink:
		max_ink = maximum
	current_ink = current

# ==========================================
# 🎨 自訂繪製核心 (_draw)
# ==========================================
func _draw() -> void:
	var total_width = max_ink * pixels_per_ink
	var current_width = current_ink * pixels_per_ink

	# 1. 繪製背景 (空管)
	draw_rect(Rect2(Vector2.ZERO, Vector2(total_width, bar_height)), bg_color, true)

	# 2. 繪製墨水填充 (依模式套用顏色)
	var fill_color = blue_color
	match current_mode:
		Mode.BLUE: fill_color = blue_color
		Mode.RED: fill_color = red_color
		Mode.YELLOW: fill_color = yellow_color

	if current_width > 0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(current_width, bar_height)), fill_color, true)

	# 3. 動態繪製刻度線
	match current_mode:
		Mode.BLUE:
			# 每 10 墨水劃一條白線
			var step = 10.0
			var val = step
			while val < max_ink:
				_draw_tick_line(val * pixels_per_ink)
				val += step

		Mode.RED:
			# 標出 15 (最低門檻) 與 45 (滿蓄力)
			if max_ink >= 15.0:
				_draw_tick_line(15.0 * pixels_per_ink, Color(1, 1, 1, 0.95))
			if max_ink >= 45.0:
				_draw_tick_line(45.0 * pixels_per_ink, Color(1, 1, 1, 0.95))

		Mode.YELLOW:
			# 每 25 墨水劃一條白線
			var step = 25.0
			var val = step
			while val < max_ink:
				_draw_tick_line(val * pixels_per_ink)
				val += step

	# 4. 繪製外框
	draw_rect(Rect2(Vector2.ZERO, Vector2(total_width, bar_height)), border_color, false, 1.0)

# 畫刻度線輔助函式
func _draw_tick_line(x_pos: float, color: Color = tick_color) -> void:
	draw_line(Vector2(x_pos, 0), Vector2(x_pos, bar_height), color, 1.0)

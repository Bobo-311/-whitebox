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

# 🌟 專門用來畫殘影的數值
var trail_ink: float = 60.0:
	set(value):
		trail_ink = value
		queue_redraw() # 當殘影數值變化時，每幀重新繪畫

# 每 1 點墨水占用的像素寬度
@export var pixels_per_ink: float = 2.5 
@export var bar_height: float = 14.0

@export_group("Style Colors")
@export var bg_color: Color = Color(0.1, 0.1, 0.12, 0.8)   # 空管底色
@export var tick_color: Color = Color(1.0, 1.0, 1.0, 0.75) # 刻度線顏色
@export var trail_color: Color = Color(0.9, 0.9, 0.9, 0.9) # 殘影顏色 (灰白色)

@export var blue_color: Color = Color(0.23, 0.51, 0.96)    # 藍色手槍
@export var red_color: Color = Color(0.97, 0.44, 0.44)     # 紅色狙擊
@export var yellow_color: Color = Color(0.99, 0.83, 0.30)   # 黃色散彈

var current_mode: Mode = Mode.BLUE
var drain_tween: Tween # 專門控制殘影掉落的計時器
var heal_tween: Tween  # 專門控制補墨水動畫的計時器

func _ready() -> void:
	trail_ink = current_ink
	_update_bar_size()

# 根據上限更新物理寬度 (實體伸長)
func _update_bar_size() -> void:
	var total_width = max_ink * pixels_per_ink
	custom_minimum_size = Vector2(total_width, bar_height)
	size = custom_minimum_size

# ==========================================
# 🔄 外部對接 API (加入動畫邏輯)
# ==========================================

# 切換攻擊模式 (BLUE, RED, YELLOW)
func set_mode(new_mode: Mode) -> void:
	current_mode = new_mode
	queue_redraw()

# 同步玩家目前的墨水數值
func update_ink(current: float, maximum: float = -1.0) -> void:
	if maximum > 0 and maximum != max_ink:
		max_ink = maximum
		
	var target_ink = clamp(current, 0.0, max_ink)
	
	# 🌟 果汁感動畫邏輯
	if target_ink < current_ink:
		# 💥【扣除墨水】：主色瞬間縮短，殘影停頓後再掉落
		if heal_tween and heal_tween.is_running(): 
			heal_tween.kill() # 打斷補血動畫
			
		current_ink = target_ink 
		
		if drain_tween and drain_tween.is_running(): 
			drain_tween.kill()
		drain_tween = create_tween()
		drain_tween.tween_interval(0.2) # 停頓 0.2 秒
		drain_tween.tween_property(self, "trail_ink", target_ink, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		
	elif target_ink > current_ink:
		# 💖【回復墨水】：平滑增長 + 整個條瞬間發光閃爍
		if drain_tween and drain_tween.is_running(): 
			drain_tween.kill() # 打斷扣血動畫
			
		if heal_tween and heal_tween.is_running(): 
			heal_tween.kill()
			
		heal_tween = create_tween().set_parallel(true)
		
		# 讓墨水跟殘影一起平滑往前衝
		heal_tween.tween_property(self, "current_ink", target_ink, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		heal_tween.tween_property(self, "trail_ink", target_ink, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		# UI 瞬間變亮 (數值 > 1 代表發光)，然後平滑褪回正常的白色
		modulate = Color(1.8, 1.8, 1.8, 1.0) 
		heal_tween.tween_property(self, "modulate", Color.WHITE, 0.3)

# ==========================================
# 🎨 自訂繪製核心 (_draw) 🌟 像素完美重製版
# ==========================================
# ==========================================
# 🎨 自訂繪製核心 (_draw) 🌟 1.38倍縮放抗鋸齒版
# ==========================================
func _draw() -> void:
	var total_width = round(max_ink * pixels_per_ink)
	
	var outline_black = Color(0.05, 0.05, 0.05, 1.0)
	var outline_white = Color(1.0, 1.0, 1.0, 1.0) 
	
	# 底層：純白外框 (填滿)
	draw_rect(Rect2(0, 0, total_width, bar_height), outline_white, true)
	
	# 第二層：純黑內框 (上下左右各縮 2 像素)
	draw_rect(Rect2(2, 2, total_width - 4, bar_height - 4), outline_black, true)
	
	# 第三層：空管底色 (上下左右各縮 4 像素)
	var inner_w = total_width - 8
	var inner_h = bar_height - 8
	draw_rect(Rect2(4, 4, inner_w, inner_h), bg_color, true)

	# 內部墨水與殘影計算
	var current_fill_w = round((current_ink / max_ink) * inner_w) if max_ink > 0 else 0
	var trail_fill_w = round((trail_ink / max_ink) * inner_w) if max_ink > 0 else 0

	# 繪製殘影
	if trail_fill_w > 0:
		draw_rect(Rect2(4, 4, trail_fill_w, inner_h), trail_color, true)

	# 繪製墨水填充
	var fill_color = blue_color
	match current_mode:
		Mode.BLUE: fill_color = blue_color
		Mode.RED: fill_color = red_color
		Mode.YELLOW: fill_color = yellow_color

	if current_fill_w > 0:
		draw_rect(Rect2(4, 4, current_fill_w, inner_h), fill_color, true)

	# 動態繪製刻度線
	# 動態繪製刻度線 (藍色每10、紅色每15、黃色每25)
	match current_mode:
		Mode.BLUE:
			var step = 10.0
			var val = step
			while val < max_ink:
				var x_pos = 4 + round((val / max_ink) * inner_w)
				_draw_tick_line(x_pos, inner_h)
				val += step
		Mode.RED:
			var step = 15.0
			var val = step
			while val < max_ink:
				var x_pos = 4 + round((val / max_ink) * inner_w)
				_draw_tick_line(x_pos, inner_h, Color(1, 1, 1, 0.95))
				val += step
		Mode.YELLOW:
			var step = 25.0
			var val = step
			while val < max_ink:
				var x_pos = 4 + round((val / max_ink) * inner_w)
				_draw_tick_line(x_pos, inner_h)
				val += step

# 更新輔助繪圖函數 (畫出厚度為 2 的實心長方形)
func _draw_tick_line(x_pos: float, inner_h: float, color: Color = tick_color) -> void:
	draw_rect(Rect2(x_pos, 4, 2, inner_h), color, true)

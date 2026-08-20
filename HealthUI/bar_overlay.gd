extends Control

var border_white = Color(0.85, 0.88, 0.9)
var border_black = Color("0b0d0b")
var tick_color = Color("0b0d0b")

func _ready():
	resized.connect(queue_redraw)

func _draw():
	var w = round(size.x)
	var h = round(size.y)

	# 1. 白框 (最外圍 2 像素)
	draw_rect(Rect2(0, 0, w, 2), border_white, true)       # 上
	draw_rect(Rect2(0, h - 2, w, 2), border_white, true)   # 下
	draw_rect(Rect2(0, 0, 2, h), border_white, true)       # 左
	draw_rect(Rect2(w - 2, 0, 2, h), border_white, true)   # 右

	# 2. 黑框 (內縮 2 像素，厚度 2 像素)
	draw_rect(Rect2(2, 2, w - 4, 2), border_black, true)       # 上
	draw_rect(Rect2(2, h - 4, w - 4, 2), border_black, true)   # 下
	draw_rect(Rect2(2, 2, 2, h - 4), border_black, true)       # 左
	draw_rect(Rect2(w - 4, 2, 2, h - 4), border_black, true)   # 右

	# 3. 🌟 終極精準切分 (Pro 級 Pixel-Perfect 分配法)
	var start_x = 4.0
	var inner_w = w - 8.0 # 綠色實體區域的真實總寬度
	var tick_width = 1  # 強烈建議用 2 像素，對抗縮放造成的忽粗忽細

	# 核心數學：要切 5 份，會有 4 條線。
	# 必須先從總寬度「扣除這 4 條線的空間」，剩下的才是真正純綠色的可用空間！
	var total_pure_green_w = inner_w - (tick_width * 4.0)
	var segment_w = total_pure_green_w / 5.0

	for i in range(1, 5):
		# 座標 = 起點 + (前面有幾個綠色區塊) + (前面有幾條黑線)
		var x_pos = round(start_x + (i * segment_w) + ((i - 1) * tick_width))
		draw_rect(Rect2(x_pos, 4, tick_width, h - 8), tick_color, true)

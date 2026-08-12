extends Control

var border_white = Color(1.0, 1.0, 1.0, 1.0) # 最外圈純白外框
var border_black = Color(0.05, 0.05, 0.05, 1.0) # 內圈純黑外框
var tick_color = Color(0.4, 0.4, 0.4, 0.6)   # 灰色刻度線

func _ready():
	# 當血條長度改變時，自動重新繪製外框跟線條
	resized.connect(queue_redraw)

func _draw():
	# 1. 先畫出 4 條灰色的 20% 分割線
	for i in range(1, 5):
		var x_pos = size.x * (i * 0.2)
		draw_line(Vector2(x_pos, 0), Vector2(x_pos, size.y), tick_color, 1.0)
		
	# 2. 畫出黑色內框 
	# Rect2(1, 1, x-2, y-2) 代表從座標(1,1)開始畫，長寬各扣掉2，讓它剛好往內縮進去
	# 這個黑框會完美覆蓋並修飾綠色血條稍微粗糙的邊緣
	draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), border_black, false, 2.0)
	
	# 3. 畫出白色外框
	# 畫在最外圍 0 的位置，把黑框包在裡面
	draw_rect(Rect2(0, 0, size.x, size.y), border_white, false, 2.0)

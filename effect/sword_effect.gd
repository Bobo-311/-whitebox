extends Node2D

var opacity = 0.0

func _process(delta):
	# 讓透明度慢慢消失，達成「閃一下」的效果
	if opacity > 0:
		opacity -= delta * 5.0 # 數值越大消失越快
		queue_redraw() # 強制重新繪圖

func trigger():
	opacity = 0.6 # 設定初始透明度 (0.6 是半透明)
	queue_redraw()

func _draw():
	if opacity <= 0: return
	
	# 參數解釋：位置, 半徑, 起始角度, 結束角度, 點數, 顏色
	# 我們畫一個 90 度的扇形，對準前方
	var color = Color(1, 1, 1, opacity) # 純白色 + 動態透明度
	draw_arc(Vector2.ZERO, 50, deg_to_rad(-45), deg_to_rad(45), 32, color, 10.0)

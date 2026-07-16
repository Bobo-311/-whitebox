extends Control
#notebook

var is_open: bool = false
var screen_height: float = 0.0 # 改成讓程式自己抓，不再寫死數字

func _ready():
	# 遊戲一開始，自動抓取玩家目前的視窗高度 (這樣改解析度也不會壞)
	screen_height = get_viewport_rect().size.y
	
	# 把這本筆記本往下推到螢幕外面 (Y軸位置 = 螢幕高度)
	position.y = screen_height
	# 先隱藏起來節省效能，等按 Tab 才顯示
	hide() 

# ==========================================
# 筆記本開關總控制 (給 player.gd 按下 Tab 時呼叫的)
# ==========================================
func toggle_notebook():
	if is_open:
		close_notebook()
	else:
		open_notebook()

# ==========================================
# 打開與關閉的動畫邏輯 (Tween 補間動畫)
# ==========================================
func open_notebook():
	is_open = true
	show() # 先讓 UI 顯示，但此時它還在螢幕外，玩家看不到
	
	# 建立滑動動畫：0.3 秒內，Y軸從底部滑到 0 (螢幕頂端)
	# TRANS_QUART + EASE_OUT 會做出「快速滑出，最後慢慢煞車」的物理質感
	var tween = create_tween()
	tween.tween_property(self, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func close_notebook():
	is_open = false
	
	# 建立滑落動畫：0.25 秒內，Y軸從 0 滑回螢幕最下方
	# TRANS_SINE + EASE_IN 會有一種順順掉下去的感覺
	var tween = create_tween()
	tween.tween_property(self, "position:y", screen_height, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 關鍵！等滑落動畫完整播完後，才執行隱藏，避免還沒滑完畫面就閃退穿幫
	tween.tween_callback(self.hide)

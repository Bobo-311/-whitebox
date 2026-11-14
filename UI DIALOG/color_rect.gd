extends ColorRect

var fade_tween: Tween

func _ready() -> void:
	# 🌟 防呆：確保這塊黑布絕對不會擋住滑鼠點擊對話
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 🌟 連接 Dialogic 的開始訊號與自訂暗號
	if not Dialogic.timeline_started.is_connected(_on_timeline_started):
		Dialogic.timeline_started.connect(_on_timeline_started)
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)
		
	# 場景剛載入時，立刻執行進場淡入
	_fade_in()

# 🎬 對話開始時：黑底平滑淡入 (0.5秒，對齊上下電影黑邊進場)
func _on_timeline_started() -> void:
	_fade_in()

func _fade_in() -> void:
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
		
	# 先設為完全透明，再淡入到原本設定的 Color Alpha 值
	modulate.a = 0.0
	fade_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.5)

# 🏃‍♂️ 收到退場暗號時：黑底同步淡出 (0.4秒，對齊立繪與上下黑邊退場)
func _on_dialogic_signal(argument: String) -> void:
	if argument == "fade_out_cinematic":
		if fade_tween and fade_tween.is_running():
			fade_tween.kill()
			
		fade_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.4)

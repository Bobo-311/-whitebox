extends ColorRect

# 專門記錄 AM001 的開場黑幕已經退場。
const COVER_FLAG := "am001_opening_cover_released"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 從其他地圖走回 AM001 時，在第一幀顯示前就把黑幕關掉。
	if DataManager.is_cutscene_completed(COVER_FLAG):
		hide()
		return

	Dialogic.signal_event.connect(_on_dialogic_signal)

func _on_dialogic_signal(argument: String) -> void:
	if argument == "am001_release_cover":
		hide()
		DataManager.mark_cutscene_completed(COVER_FLAG)

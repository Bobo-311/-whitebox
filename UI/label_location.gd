extends Label

# 當玩家進入新地圖、HUD 被生成時，自動執行
func _ready():
	# 直接去問大腦現在在哪裡，並更新文字
	if DataManager.current_map_name != "":
		text = "◆ ── 当前位置：" + DataManager.current_map_name + " ── ◆"
	else:
		text = "◆ ── 当前位置：未知 ── ◆"

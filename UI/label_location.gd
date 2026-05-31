#lable_location
extends Label # 繼承 Label 節點 lable_location

# ==========================================
# 系統內建函數：_ready()
# 當 UI 被生成在畫面上時，第一時間執行
# ==========================================
func _ready() -> void:
	# 🌟 1. 訂閱廣播頻道：
	# 告訴大腦：「如果有人發射了 map_changed 廣播，請馬上執行我底下的 update_text 函數」
	if not DataManager.map_changed.is_connected(update_text):
		DataManager.map_changed.connect(update_text)
	
	# 2. 開局防呆：自己先手動去大腦抓一次字，確保畫面一出來就有字
	update_text(DataManager.current_map_name)


# ==========================================
# 自訂函數：專門用來改字的機器
# (這個函數會被大腦的廣播自動呼叫，並塞入 map_name)
# ==========================================
func update_text(map_name: String) -> void:
	# 檢查傳進來的名字是不是空的
	if map_name != "":
		# 把收到的名字，組裝成我們要的格式顯示在畫面上
		text = "◆ ── 当前位置：" + map_name + " ── ◆"
	else:
		# 如果大腦失憶了，顯示未知
		text = "◆ ── 当前位置：未知 ── ◆"

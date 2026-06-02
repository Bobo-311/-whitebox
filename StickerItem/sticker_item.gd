extends TextureRect #StickerItem
class_name StickerItem # 🌟 給它註冊一個專屬類別名稱，以後別的腳本比較好認出它

# ==========================================
# 貼紙的核心資料 (預留給未來的資料庫使用)
# ==========================================
var sticker_id: String = "" # 這張貼紙的身分證 (例如 "sticker_01")


# ==========================================
# Godot 內建函數：當玩家對著這個 UI 按住滑鼠左鍵並「拖曳」時，會自動觸發
# ==========================================
func _get_drag_data(at_position: Vector2) -> Variant:
	
	# 📦 1. 準備要寄出去的包裹 (Dictionary 字典格式)
	# 我們把裝備格會需要用到的所有資訊，都打包在這個包裹裡
	var data = {
		"type": "sticker",    # 標籤：告訴接收端「這是一張貼紙」
		"id": sticker_id,     # 內容物：這張貼紙的 ID
		"texture": texture    # 內容物：順便把圖片寄過去，讓裝備格可以直接換圖
	}
	
	# 👻 2. 製作滑鼠拖曳時，拿在手上的「半透明殘影」
	var preview_icon = TextureRect.new()
	preview_icon.texture = texture
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.custom_minimum_size = custom_minimum_size # 讓殘影大小跟本體一樣大
	preview_icon.modulate.a = 0.7 # 設定為 70% 的半透明，看起來比較有「被拿起來」的感覺
	
	# 🎯 3. 調整殘影的位置，讓滑鼠游標剛好捏在圖片的正中間
	var preview_control = Control.new()
	preview_control.add_child(preview_icon)
	preview_icon.position = -preview_icon.custom_minimum_size / 2 
	
	# 4. 把殘影設定給系統顯示
	set_drag_preview(preview_control)
	
	# 5. 正式把包裹寄給滑鼠游標！(此時包裹就拿在玩家手上了)
	return data

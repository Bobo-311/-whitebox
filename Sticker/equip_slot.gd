extends TextureRect#equip_slot

# 🌟 讓你在編輯器手動填入這是第幾格（0, 1, 2, 3）
@export var slot_index: int = 0

var empty_frame_texture: Texture2D

func _ready() -> void:
	# 1. 記住最初空圈圈的樣子
	empty_frame_texture = texture
	
	# 2. 🌟 核心功能：下次開啟時讀取存檔
	# 檢查大腦裡，我這一格有沒有存圖片路徑
	var saved_path = DataManager.equipped_stickers[slot_index]
	if saved_path != "":
		# 如果有路徑，用 load() 把貼紙圖片載入進來，並換上
		texture = load(saved_path)

# 安檢門：現在包裹裡裝的是路徑字串 (String)
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return data is String

# 📥 當拖曳放手裝備時
func _drop_data(at_position: Vector2, data: Variant) -> void:
	# 1. 把路徑字串轉成真正的圖片顯示出來
	texture = load(data)
	# 2. 🌟 當下存檔：告訴大腦這一格裝了這張貼紙
	DataManager.equipped_stickers[slot_index] = data
	print("第 ", slot_index, " 格裝備成功，已寫入大腦！")

# 🖱️ 當右鍵點擊卸下時
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if texture != empty_frame_texture:
				texture = empty_frame_texture
				# 🌟 當下存檔：告訴大腦這一格現在空了
				DataManager.equipped_stickers[slot_index] = ""
				print("第 ", slot_index, " 格已卸下，大腦數據已清空！")

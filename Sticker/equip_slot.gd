extends TextureRect # equip_slot (裝備格)

# 🌟 讓你在編輯器手動填入這是第幾格（0, 1, 2, 3）
@export var slot_index: int = 0

var empty_frame_texture: Texture2D

func _ready() -> void:
	# 1. 記住最初空圈圈的樣子
	empty_frame_texture = texture
	
	# 2. 讀取存檔
	var saved_path = DataManager.equipped_stickers[slot_index]
	if saved_path != "":
		texture = load(saved_path)

# ==========================================
# 🛑 安檢門：檢查包裹格式
# ==========================================
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 檢查包裹是不是字典格式，而且裡面有沒有貼上 "type": "sticker" 的標籤
	if typeof(data) == TYPE_DICTIONARY and data.has("type"):
		return data["type"] == "sticker"
	return false

# ==========================================
# 📥 當拖曳放手，正式裝備時
# ==========================================
func _drop_data(at_position: Vector2, data: Variant) -> void:
	# 1. 直接從包裹裡面把圖片 (texture) 拿出來換上
	texture = data["texture"]
	
	# 2. 存檔：從圖片中抓取原本的檔案路徑存進大腦 (維持你原本的存檔邏輯)
	DataManager.equipped_stickers[slot_index] = data["texture"].resource_path
	print("第 ", slot_index, " 格裝備成功，已寫入大腦！")

# ==========================================
# 🖱️ 右鍵點擊卸下
# ==========================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if texture != empty_frame_texture:
				texture = empty_frame_texture
				# 告訴大腦這一格現在空了
				DataManager.equipped_stickers[slot_index] = ""
				print("第 ", slot_index, " 格已卸下，大腦數據已清空！")

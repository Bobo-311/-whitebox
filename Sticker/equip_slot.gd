# equip_slot (裝備格)
extends TextureRect # 繼承自 TextureRect，這是一個裝備格的介面

# 讓你在編輯器手動填入這是第幾格（0, 1, 2, 3）
@export var slot_index: int = 0

var empty_frame_texture: Texture2D # 記憶體：用來記住格子空著時候的預設圖案

func _ready() -> void:
	# 1. 遊戲開始時，先記住最初空圈圈的樣子
	empty_frame_texture = texture
	
	# 2. 讀取存檔：去大腦查詢這一格原本有沒有裝備東西
	var saved_id = DataManager.equipped_stickers[slot_index]
	
	# [🌟 本次新增] 修改讀取邏輯：因為大腦現在存的是 ID (不是路徑)，所以要透過 ID 去圖鑑找圖片
	if saved_id != "":
		# 確定有 ID 的話，從大腦的 STICKER_DB 圖鑑裡抓出圖片路徑，並載入顯示
		texture = load(DataManager.STICKER_DB[saved_id].texture_path)

# ==========================================
# 🛑 安檢門：檢查拖過來的包裹格式對不對
# ==========================================
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 檢查包裹是不是字典格式，而且裡面有沒有貼上 "type": "sticker" 的標籤
	if typeof(data) == TYPE_DICTIONARY and data.has("type"):
		return data["type"] == "sticker"
	return false

# ==========================================
# 📥 當拖曳放手，正式裝備到格子上時
# ==========================================
func _drop_data(at_position: Vector2, data: Variant) -> void:
	# 1. 直接從包裹裡面把圖片 (texture) 拿出來換上，讓玩家看到裝備上去了
	texture = data["texture"]
	
	# 2. [🌟 本次新增] 存檔：把包裹裡的「ID」存進大腦對應的格子裡 (以前是存圖片路徑)
	DataManager.equipped_stickers[slot_index] = data["id"]
	print("第 ", slot_index, " 格裝備成功，貼紙 ID：", data["id"])
	
	# 3. [🌟 本次新增] 發射廣播！大聲告訴全遊戲：「裝備有變動啦！玩家請重新算血量！」
	DataManager.equipment_changed.emit()

# ==========================================
# 🖱️ 右鍵點擊卸下裝備
# ==========================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if texture != empty_frame_texture: # 確保格子裡真的有東西才執行卸除
				
				# 1. 把圖片變回原本空空的圈圈
				texture = empty_frame_texture
				
				# 2. 告訴大腦這一格現在空了 (寫入空字串)
				DataManager.equipped_stickers[slot_index] = ""
				print("第 ", slot_index, " 格已卸下裝備！大腦數據已清空！")
				
				# 3. [🌟 本次新增] 既然脫下裝備了，一樣要發射廣播叫玩家重算血量
				DataManager.equipment_changed.emit()

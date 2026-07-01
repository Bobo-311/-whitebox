# equip_slot (裝備格)
extends TextureRect # 外層底框 (負責維持固定大小與顯示金框)

@export var slot_index: int = 0
@onready var holder: CenterContainer = $Holder # 內層托盤 (負責裝載並置中貼紙實體)

# 預載貼紙實體藍圖
const STICKER_ITEM = preload("res://StickerItem/sticker_item.tscn") 

func _ready() -> void:
	# 遊戲啟動時，檢查存檔是否有裝備
	var saved_id = DataManager.equipped_stickers[slot_index]
	if saved_id != "":
		_spawn_sticker(saved_id)

# --------------------------------------------------
# 拖曳系統：判斷是否允許放下
# --------------------------------------------------
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 只接收帶有 "type": "sticker" 標籤的資料字典
	return typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "sticker"

# --------------------------------------------------
# 拖曳系統：正式裝備
# --------------------------------------------------
func _drop_data(at_position: Vector2, data: Variant) -> void:
	_clear_slot()                 # 1. 清空舊裝備 (避免重疊)
	_spawn_sticker(data["id"])    # 2. 生成新裝備實體並放入托盤
	
	# 3. 更新數據與廣播
	DataManager.equipped_stickers[slot_index] = data["id"]
	DataManager.equipment_changed.emit()

# --------------------------------------------------
# 點擊事件：右鍵卸下裝備
# --------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 確認托盤內有貼紙實體才執行卸下
		if holder.get_child_count() > 0: 
			_clear_slot()         
			
			# 更新數據與廣播
			DataManager.equipped_stickers[slot_index] = ""
			DataManager.equipment_changed.emit()

# --------------------------------------------------
# 工具函數：生成實體
# --------------------------------------------------
func _spawn_sticker(id: String) -> void:
	var new_sticker = STICKER_ITEM.instantiate()
	new_sticker.setup_sticker(id) # 初始化貼紙數據
	holder.add_child(new_sticker) # 放入托盤 (CenterContainer 會自動置中)

# --------------------------------------------------
# 工具函數：清空托盤
# --------------------------------------------------
func _clear_slot() -> void:
	# 刪除托盤內所有的子節點 (貼紙實體)
	for child in holder.get_children():
		child.queue_free()

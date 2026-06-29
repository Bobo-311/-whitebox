#StickerItem
extends TextureRect # 繼承自 TextureRect，用來顯示圖片介面

# [🌟 本次新增] 讓你在編輯器介面可以手動輸入這張貼紙的編號 (例如在屬性面板打上 "001")
@export var sticker_id: String = ""




# ==========================================
# 🌟 本次新增：初始化變身函數
# 當 StickerUI 把這張貼紙生出來時，會呼叫這個函數並塞入 ID
# ==========================================
func setup_sticker(id: String) -> void:
	sticker_id = id # 記住自己的身分證
	
	# 去大腦的圖鑑資料庫 (STICKER_DB) 裡，用這個 ID 查出專屬圖片，然後穿上！
	texture = load(DataManager.STICKER_DB[sticker_id].texture_path)


# sticker_item.gd
func _get_drag_data(at_position: Vector2) -> Variant:
	if sticker_id == "": 
		return null
	
	var preview = TextureRect.new()
	preview.texture = texture
	
	# 設定拖曳時的殘影大小 (你可以改數字，看覺得多大比較舒服)
	var drag_size = Vector2(120, 120) 
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = drag_size
	preview.size = drag_size
	preview.modulate.a = 0.5 # 半透明
	
	# 🌟 解決偏移的核心魔法：建立隱形中心點
	var center_node = Control.new()
	preview.position = -drag_size / 2 # 把圖片往左和往上拉一半的距離
	center_node.add_child(preview)
	
	set_drag_preview(center_node) # 把校正好的中心點設為拖曳殘影
	
	return {
		"type": "sticker",
		"texture": texture,
		"id": sticker_id
	}

extends TextureRect #draggable_sticker

# 當玩家對這個貼紙按住滑鼠左鍵拖曳時，這段內建函數就會自動執行
func _get_drag_data(at_position: Vector2) -> Variant:
	
	# --- 1. 製造滑鼠上的半透明殘影 ---
	var preview = TextureRect.new() 
	preview.texture = texture # 殘影圖案跟自己一樣
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE 
	preview.custom_minimum_size = size # 殘影大小跟自己一樣
	preview.modulate = Color(1.0, 1.0, 1.0, 0.7) # 變成 70% 半透明
	
	# 用一個控制節點包裝，讓滑鼠剛好抓在圖片正中心
	var control = Control.new()
	control.add_child(preview)
	preview.position = -0.5 * size 
	
	set_drag_preview(control) # 把這個半透明圖片設定為「拖曳殘影」
	
	# --- 2. 寄出包裹 ---
	# 🌟 改成寄出「圖片的檔案路徑」，這樣大腦才存得住字串
	return texture.resource_path

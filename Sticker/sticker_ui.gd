extends CanvasLayer # StickerUI

@onready var close_button: TextureButton = $Easel/CloseButton



func _on_close_button_pressed() -> void:
	# 尋找藏在背景的存檔面板
	for child in get_tree().root.get_children():
		# 用 "SaveMenu" 來比對比較安全，避免 Godot 實體化時自動加後綴數字
		if "SaveMenu" in child.name: 
			child.show() # 把存檔面板叫回來
			
	# 功成身退，刪除自己
	queue_free()


func _on_close_button_mouse_entered() -> void:
	# Replace with function body.	# self_modulate 就是這個節點的「濾鏡顏色」
	# Color(紅, 綠, 藍)。1.0 是原色，數字越小越暗
	# 我們把它調成 0.7，看起來就會是有質感的深灰色！
	close_button.self_modulate = Color(0.7, 0.7, 0.7) 

# --- 當滑鼠離開叉叉時 ---
func _on_close_button_mouse_exited() -> void:
		# 滑鼠移走，把顏色恢復成原本明亮的樣子 (1.0, 1.0, 1.0 = 白色/無濾鏡)
	close_button.self_modulate = Color(1.0, 1.0, 1.0)

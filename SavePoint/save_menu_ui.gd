extends CanvasLayer

# --- 按下「存檔」按鈕時觸發 ---
func _on_save_pressed() -> void:
	# 檢查 DataManager 與裡面的 player_node 是否存在
	if DataManager and DataManager.player_node:
		# 直接透過玩家節點，將當前血量設為最大血量
		DataManager.player_node.current_hp = DataManager.player_node.max_hp
		# 將當前能量設為最大能量
		DataManager.player_node.current_energy = DataManager.player_node.max_energy
		# 將當前耐力設為最大耐力
		DataManager.player_node.current_sp = DataManager.player_node.max_sp
	
	# 解除全域時間暫停
	get_tree().paused = false
	# 刪除並關閉此 UI 介面
	queue_free()
	# 刷新當前場景 (野豬復活)
	get_tree().reload_current_scene()

# --- 按下「出發」按鈕時觸發 ---
func _on_go_pressed() -> void:
	# 解除全域時間暫停
	get_tree().paused = false
	# 刪除並關閉此 UI 介面
	queue_free()

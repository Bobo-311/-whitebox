extends CanvasLayer # 繼承 CanvasLayer，處理 UI 顯示

# --- 按下「存檔」按鈕時觸發 ---
func _on_save_pressed() -> void:
	if DataManager and DataManager.player_node: # 檢查大腦與玩家是否存在
		
		# 🌟 將血量與體力的最大值，存進大腦當作復活/重載時的數值
		DataManager.saved_hp = DataManager.player_node.max_hp
		DataManager.saved_sp = DataManager.player_node.max_sp
		
		# 🌟 處理能量 (EP) 保底：低於 50% 補到 50%，高於 50% 則保留
		var half_energy = int(DataManager.player_node.max_energy * 0.5) # 算出最大能量的一半
		DataManager.saved_energy = max(DataManager.player_node.current_energy, half_energy) # 取較大值存入大腦
	
	get_tree().paused = false # 解除全域時間暫停
	queue_free() # 刪除並關閉此 UI 介面
	get_tree().reload_current_scene() # 刷新當前場景 (重載後，玩家會自動讀取大腦的滿血小抄)

# --- 按下「出發」按鈕時觸發 ---
func _on_go_pressed() -> void:
	get_tree().paused = false # 解除全域時間暫停
	queue_free() # 刪除並關閉此 UI 介面，直接繼續遊戲

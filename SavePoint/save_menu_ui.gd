#save_menu_ui
extends CanvasLayer

# --- 按下「存檔」按鈕時觸發 ---
func _on_save_pressed() -> void:
	# 檢查 DataManager 與裡面的 player_node 是否存在
	if DataManager and DataManager.player_node:
		# 🌟 核心修改：把玩家的「最大值」存進 DataManager 的小抄裡
		DataManager.saved_hp = DataManager.player_node.max_hp
		DataManager.saved_energy = DataManager.player_node.max_energy
		DataManager.saved_sp = DataManager.player_node.max_sp
	
	# 解除全域時間暫停
	get_tree().paused = false
	# 刪除並關閉此 UI 介面
	queue_free()
	# 刷新當前場景 (野豬復活，玩家會跑 _ready 函數去讀取小抄)
	get_tree().reload_current_scene()

# --- 按下「出發」按鈕時觸發 ---
func _on_go_pressed() -> void:
	# 解除全域時間暫停
	get_tree().paused = false
	# 刪除並關閉此 UI 介面
	queue_free()

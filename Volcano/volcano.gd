#volcano
extends Node2D # volcano (火山地圖)

@onready var spawn_point = $PortalSpawnPoint # 抓取降落點座標

func _ready() -> void:
	# 🌟 呼叫大腦更新函數，發廣播叫 UI 把字改成「火山」！
	DataManager.update_map_name("火山")
	
	# --- 處理傳送降落邏輯 ---
	if DataManager.is_teleporting:
		if DataManager.player_node:
			# 把玩家抓到十字標記的位置
			DataManager.player_node.global_position = spawn_point.global_position
			# 平安落地，關閉傳送狀態
			DataManager.is_teleporting = false
	else:
		# ==========================================
		# 🎬 【新增】如果不是傳送過來的（遊戲開局），就播開場動畫！
		# ==========================================
		Dialogic.signal_event.connect(_on_dialogic_signal)
		Dialogic.timeline_ended.connect(_on_dialogic_ended)	
		
		if DataManager.player_node:
			# 🌟 開場動畫：手動把阿尼上鎖！
			DataManager.player_node.is_in_dialogue = true 
			
			if DataManager.player_node.state_machine:
				DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			DataManager.player_node.animated_sprite_2d.play("idle_down")
			
		Dialogic.start("opening")


# ==========================================
# 🎬 導演接收器：聽到 Dialogic 大喊的暗號，就控制演員做事
# ==========================================
func _on_dialogic_signal(argument: String):
	var player = DataManager.player_node
	if player == null: return
	
	# 根據 Dialogic 傳來的暗號，播放對應的動畫
	match argument:
		"play_stand_up":
			player.animated_sprite_2d.play("idle_right")
			
		"play_search":
			player.animated_sprite_2d.play("idle_down")
			
		# 🗑️ 【我幫你把 cutscene_end 刪掉了！】
		# 因為我們底下已經有 _on_dialogic_ended 在負責收尾，
		# 這裡留著不但會重複執行，還會觸發剛剛的報錯！


# ==========================================
# 🔓 🌟【修改】劇本結束接收器：自動解除點穴，恢復自由！
# ==========================================
func _on_dialogic_ended():
	var player = DataManager.player_node
	if player and player.state_machine:
		# 🌟 劇本結束：手動把阿尼的鎖解開！
		player.is_in_dialogue = false
		# 1. 把大腦還給阿尼 (重新開機)
		player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		
		# 2. 🌟 關鍵修復：換成你們專案正確播放動畫的寫法！
		player.animated_sprite_2d.play("idle_down") 
		
		# 3. 確認有印出這行，就代表解穴成功！
		print("【系統】對話徹底結束，狀態機重啟，恢復控制！")

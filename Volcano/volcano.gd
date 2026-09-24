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
		# 🎬 如果不是傳送過來的（遊戲開局），就播開場動畫！
		# ==========================================
		# 🌟 我們不再需要這裡的 signal_event 囉！交給玩家自己聽廣播即可
		Dialogic.timeline_ended.connect(_on_dialogic_ended)	
		
		if DataManager.player_node:
			# 🌟 開場動畫：手動把阿尼上鎖！
			DataManager.player_node.is_in_dialogue = true 
			
			if DataManager.player_node.state_machine:
				DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			DataManager.player_node.animated_sprite_2d.play("idle_down")
			
		# 🌟 1. 啟動劇本，並把回傳的排版 (layout) 存起來
		var layout = Dialogic.start("opening")
		# 🌟 2. 載入你的 Dialogic 角色檔案
		var ani_character = load("res://dialogic/character/阿尼.dch")
		# 🌟 3. 告訴 Dialogic：這個角色的氣泡，要綁在 player 身上！
		layout.register_character(ani_character, DataManager.player_node.get_node("BubbleMaker"))

# ==========================================
# 🔓 🌟 劇本結束接收器：自動解除點穴，恢復自由！
# ==========================================
func _on_dialogic_ended():
	var player = DataManager.player_node
	if player and player.state_machine:
		# 🌟 劇本結束：手動把阿尼的鎖解開！
		player.is_in_dialogue = false
		# 1. 把大腦還給阿尼 (重新開機)
		player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		
		# 2. 換成你們專案正確播放動畫的寫法！
		player.animated_sprite_2d.play("idle_down") 
		
		# 3. 確認有印出這行，就代表解穴成功！
		print("【系統】對話徹底結束，狀態機重啟，恢復控制！")

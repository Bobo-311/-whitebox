extends Node2D # AM001 (最初之地/森林)

@onready var spawn_point = $PortalSpawnPoint 

func _ready() -> void:
	# 🌟 更新 UI 地圖名稱
	DataManager.update_map_name("森林")
	
	if DataManager.is_teleporting:
		if DataManager.player_node:
			DataManager.player_node.global_position = spawn_point.global_position
			DataManager.is_teleporting = false
	else:
		# ==========================================
		# 🎬 A001 森林開場劇情
		# ==========================================
		Dialogic.timeline_ended.connect(_on_dialogic_ended)	
		
		if DataManager.player_node:
			DataManager.player_node.is_in_dialogue = true 
			if DataManager.player_node.state_machine:
				DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			DataManager.player_node.animated_sprite_2d.play("idle_down")
			
		# 🌟 啟動 A001 劇本 (請把 "A001_opening" 換成你真實的 Timeline 名稱)
		var layout = Dialogic.start("A001")
		
		var ani_character = load("res://dialogic/character/？？？.dch")
		if DataManager.player_node.has_node("BubbleMaker"):
			layout.register_character(ani_character, DataManager.player_node.get_node("BubbleMaker"))

# ==========================================
# 🔓 劇本結束：恢復自由與解除信號
# ==========================================
func _on_dialogic_ended():
	# 🛡️ 關鍵修復：解除信號綁定，避免這張地圖去干擾後續其他的對話！
	if Dialogic.timeline_ended.is_connected(_on_dialogic_ended):
		Dialogic.timeline_ended.disconnect(_on_dialogic_ended)
		
	var player = DataManager.player_node
	if player and player.state_machine:
		player.is_in_dialogue = false
		player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		player.animated_sprite_2d.play("idle_down") 
		print("【系統】AM001 開場結束，恢復控制！")

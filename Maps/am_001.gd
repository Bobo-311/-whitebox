# 🌟 重點：繼承你剛剛寫好的 BaseMap
extends BaseMap 

func _ready() -> void:
	# 這行很重要！先執行 BaseMap 公版裡的 _ready (更新名稱、處理傳送)
	super._ready() 
	
	# (可選) 呼叫你上一題寫的相機邊界設定！
	if DataManager.player_node:
		DataManager.player_node.update_camera_limits(-500, -500, 2500, 1500)

# 🌟 覆寫公版的函數：這裡專心寫 AM001 的專屬劇情就好！
func _play_map_opening() -> void:
	Dialogic.timeline_ended.connect(_on_dialogic_ended)	
	
	if DataManager.player_node:
		DataManager.player_node.is_in_dialogue = true 
		if DataManager.player_node.state_machine:
			DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		DataManager.player_node.animated_sprite_2d.play("idle_down")
		
	var layout = Dialogic.start("opening")
	var ani_character = load("res://dialogic/character/？？？.dch")
	if DataManager.player_node.has_node("BubbleMaker"):
		layout.register_character(ani_character, DataManager.player_node.get_node("BubbleMaker"))

func _on_dialogic_ended():
	if Dialogic.timeline_ended.is_connected(_on_dialogic_ended):
		Dialogic.timeline_ended.disconnect(_on_dialogic_ended)
		
	var player = DataManager.player_node
	if player and player.state_machine:
		player.is_in_dialogue = false
		player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		player.animated_sprite_2d.play("idle_down") 
		print("【系統】AM001 開場結束，恢復控制！")	

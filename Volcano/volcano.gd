extends Node2D

@onready var spawn_point = $PortalSpawnPoint

func _ready():
	# 🌟 唯一要改的地方：告訴大腦現在人在火山
	DataManager.current_map_name = "火山"
	
	# 下面的降落判定完全一模一樣
	if DataManager.is_teleporting:
		if DataManager.player_node:
			DataManager.player_node.global_position = spawn_point.global_position
			DataManager.is_teleporting = false

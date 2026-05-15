extends Node2D # 或者是你的根節點類型

@onready var spawn_point = $PortalSpawnPoint

func _ready():
	# 告訴大腦現在人在工作室
	DataManager.current_map_name = "工作室"
	
	# 降落判定：如果大腦說「玩家是剛搭傳送門過來的」
	if DataManager.is_teleporting:
		if DataManager.player_node:
			# 把玩家抓到十字標記的位置
			DataManager.player_node.global_position = spawn_point.global_position
			# 平安落地，關閉傳送狀態
			DataManager.is_teleporting = false

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

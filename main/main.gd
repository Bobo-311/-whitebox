# main
extends Node2D 

@onready var spawn_point = $PortalSpawnPoint # 抓取降落點座標

func _ready() -> void:
	# 🌟 最正規做法：直接呼叫大腦的更新函數
	# 這行代碼一執行，大腦就會自動發廣播叫 UI 把字改成「鐘塔」！
	DataManager.update_map_name("钟塔")
	
	# --- 處理傳送降落邏輯 ---
	# 降落判定：如果大腦說「玩家是剛搭黑洞傳送門過來的」
	if DataManager.is_teleporting:
		if DataManager.player_node:
			# 把玩家抓到十字標記的位置 (降落點)
			DataManager.player_node.global_position = spawn_point.global_position
			# 平安落地，關閉傳送狀態
			DataManager.is_teleporting = false

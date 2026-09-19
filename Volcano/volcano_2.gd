extends Node2D

@onready var spawn_point = $PortalSpawnPoint 
@onready var ghost_cam = $GhostCamera # 抓取我們新蓋的幽靈相機

func _ready() -> void:
	DataManager.update_map_name("火山二區")
	
	# ==========================================
	# 1. 傳送落地系統
	# ==========================================
	if DataManager.is_teleporting:
		if DataManager.player_node:
			var player = DataManager.player_node
			
			if not player.is_inside_tree():
				add_child(player)
				
			player.global_position = spawn_point.global_position
			
			player.set_physics_process(true)
			if "is_reading_book" in player:
				player.is_reading_book = false 
			if player.has_node("StateMachine"):
				player.get_node("StateMachine").process_mode = Node.PROCESS_MODE_INHERIT
				
			DataManager.is_teleporting = false
			
	# ==========================================
	# 2. 強制奪權：啟動幽靈相機
	# ==========================================
	# 延遲一幀，確保玩家已經載入完畢，我們再搶畫面
	call_deferred("_activate_ghost_camera")

func _activate_ghost_camera():
	if ghost_cam:
		ghost_cam.make_current()
		print("🎥 [系統] 已切換為 GhostCamera！")

# ==========================================
# 3. 核心精華：讓幽靈相機每幀去追蹤玩家！
# ==========================================
func _process(delta: float) -> void:
	# 如果幽靈相機存在，且玩家也活著
	if ghost_cam and DataManager.player_node:
		# 讓相機的座標，永遠等於玩家的座標！
		# 因為我們有開 Position Smoothing，所以看起來會是非常滑順的跟隨效果。
		ghost_cam.global_position = DataManager.player_node.global_position

extends Node2D
class_name BaseMap 

@export var map_name: String = "未命名地圖"

@export_group("相機邊界設定 (Camera Limits)")
@export var limit_left: int = -1000
@export var limit_top: int = -1000
@export var limit_right: int = 1000
@export var limit_bottom: int = 1000

@onready var spawn_point: Marker2D = get_node_or_null("PortalSpawnPoint")

func _ready() -> void:
	# ==========================================
	# 🧹 1. 安全清理機制 (掃除上一張地圖的幽靈 UI)
	# ==========================================
	# 強制結束 Dialogic 的時間軸與黑邊介面
	Dialogic.end_timeline() 
	
	# 強制解除阿尼的「看劇情狀態」，避免按鍵被鎖死或無法移動
	if DataManager.player_node:
		DataManager.player_node.is_in_dialogue = false
		if DataManager.player_node.state_machine:
			DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_INHERIT

	# ==========================================
	# 🗺️ 2. 正常地圖初始化
	# ==========================================
	# 自動更新地圖名稱
	DataManager.update_map_name(map_name)
	
	# 自動更新相機邊界
	if DataManager.player_node and DataManager.player_node.has_method("update_camera_limits"):
		DataManager.player_node.update_camera_limits(limit_left, limit_top, limit_right, limit_bottom)
	
	# 判斷是傳送進來的，還是直接讀取這張地圖的
	if DataManager.is_teleporting:
		if DataManager.player_node and spawn_point:
			DataManager.player_node.global_position = spawn_point.global_position
			DataManager.is_teleporting = false
	else:
		_play_map_opening()

# 給子地圖覆寫用的虛擬函數
func _play_map_opening() -> void:
	pass

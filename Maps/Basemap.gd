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
	# 🧹 1. 安全清理機制 (🌟 修正：只有當真的有殘留劇本時才清理！)
	# ==========================================
	if Dialogic.current_timeline != null:
		Dialogic.end_timeline() 
	
	if DataManager.player_node:
		DataManager.player_node.is_in_dialogue = false
		if DataManager.player_node.state_machine:
			DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_INHERIT

	# ==========================================
	# 🗺️ 2. 正常地圖初始化
	# ==========================================
	DataManager.update_map_name(map_name)
	
	if DataManager.player_node and DataManager.player_node.has_method("update_camera_limits"):
		DataManager.player_node.update_camera_limits(limit_left, limit_top, limit_right, limit_bottom)
	
	if DataManager.is_teleporting:
		if DataManager.player_node and spawn_point:
			DataManager.player_node.global_position = spawn_point.global_position
			DataManager.is_teleporting = false
			
	# 🌟 等待 2 幀：讓玩家節點、相機與 UI 完全就緒後再開拍
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 🎬 3. 執行地圖開場流程
	_play_map_opening()

func _play_map_opening() -> void:
	for child in get_children():
		if child is CutsceneDirector and child.trigger_on_map_enter and not child.has_triggered:
			child.start_cutscene()
			break

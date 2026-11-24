
extends Node2D
class_name BaseMap

# ============================================================
# 《眠境 RE:RECOLOR》
# BaseMap V2｜共用地圖初始化管理
#
# Godot 4.5.1
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 地圖名稱初始化
# 2. 玩家相機邊界設定
# 3. 清理上一張地圖的殘留劇情狀態
# 4. 保留畫架快速傳送預留機制
# 5. 等待 SceneTransition 完成
# 6. 正確啟動地圖開場劇情
#
# ============================================================
# 相容性
# ============================================================
#
# 保留原本的：
#
# map_name
# limit_left
# limit_top
# limit_right
# limit_bottom
# PortalSpawnPoint
# DataManager.is_teleporting
#
# 不需要重新設定所有地圖 Inspector。
# 不修改現有傳送門及出生點。
# ============================================================


# ============================================================
# 1. 地圖基本設定
# ============================================================

## 顯示於遊戲 HUD 的地圖名稱
@export var map_name: String = "未命名地圖"


# ============================================================
# 2. 相機邊界設定
# ============================================================

@export_group("相機邊界設定 (Camera Limits)")

@export var limit_left: int = -1000
@export var limit_top: int = -1000
@export var limit_right: int = 1000
@export var limit_bottom: int = 1000


# ============================================================
# 3. 畫架快速傳送預留出生點
#
# 保留原本 PortalSpawnPoint 的用途。
#
# 不將它用於：
# - 新遊戲出生
# - 一般跨地圖傳送
# - 正式存檔讀取
# ============================================================

@onready var spawn_point: Marker2D = (
	get_node_or_null("PortalSpawnPoint") as Marker2D
)


# ============================================================
# 4. 地圖初始化
# ============================================================

func _ready() -> void:

	# --------------------------------------------------------
	# A. 清理上一張地圖的殘留劇情
	# --------------------------------------------------------

	_clear_previous_dialogue()

	# --------------------------------------------------------
	# B. 初始化地圖名稱
	# --------------------------------------------------------

	DataManager.update_map_name(map_name)

	# --------------------------------------------------------
	# C. 設定玩家相機邊界
	# --------------------------------------------------------

	_setup_camera_limits()

	# --------------------------------------------------------
	# D. 保留畫架快速傳送機制
	# --------------------------------------------------------

	_apply_legacy_teleport()

	# --------------------------------------------------------
	# E. 等待正規場景轉場完成
	#
	# 如果目前由 SceneTransition 進入地圖，
	# 則等待黑幕、玩家定位及相機設定全部結束。
	#
	# 不自行猜測轉場需要多少幀。
	# --------------------------------------------------------

	if SceneTransition.is_transitioning:

		await SceneTransition.transition_settled

	else:

		# 直接 F6 測試地圖，或透過舊快速傳送系統
		# 進入地圖時，保留原本兩幀初始化緩衝。

		await get_tree().process_frame
		await get_tree().process_frame

	# 確認地圖在等待期間沒有被卸載。
	if not is_inside_tree():
		return

	# --------------------------------------------------------
	# F. 啟動地圖開場劇情
	#
	# 此時 SceneTransition 的黑幕已經結束。
	# --------------------------------------------------------

	_play_map_opening()


# ============================================================
# 5. 清理殘留劇情狀態
#
# 只有真的存在殘留 Timeline 時才結束。
# 保留原本的安全清理機制。
# ============================================================

func _clear_previous_dialogue() -> void:

	if Dialogic.current_timeline != null:

		Dialogic.end_timeline()

	var player = DataManager.player_node

	if not is_instance_valid(player):
		return

	if not is_ancestor_of(player):
		return

	player.is_in_dialogue = false

	if player.state_machine:

		player.state_machine.process_mode = (
			Node.PROCESS_MODE_INHERIT
		)


# ============================================================
# 6. 初始化相機邊界
#
# 沿用 Player.update_camera_limits()。
# ============================================================

func _setup_camera_limits() -> void:

	var player: Node2D = DataManager.player_node

	if not is_instance_valid(player):
		return

	if not is_ancestor_of(player):
		return

	if player.has_method("update_camera_limits"):

		player.call(
			"update_camera_limits",
			limit_left,
			limit_top,
			limit_right,
			limit_bottom
		)


# ============================================================
# 7. 原有畫架快速傳送預留機制
#
# 目前仍由 DataManager.is_teleporting 控制。
#
# 等正式畫架管理器製作完成後，
# 再統一整合，不在本階段刪除。
# ============================================================

func _apply_legacy_teleport() -> void:

	if not DataManager.is_teleporting:
		return

	var player: Node2D = DataManager.player_node

	if not is_instance_valid(player):
		return

	if not is_ancestor_of(player):
		return

	if spawn_point == null:
		return

	player.global_position = spawn_point.global_position

	DataManager.is_teleporting = false


# ============================================================
# 8. 執行地圖開場劇情
#
# 保留原本 CutsceneDirector 的觸發規則。
#
# 同一時間只啟動一個地圖開場劇情。
#
# 劇情永久完成紀錄仍由 DataManager 處理，
# 未來再接入 SaveManager。
# ============================================================

func _play_map_opening() -> void:

	# 如果目前已有其他劇情正在播放，
	# 不重複開啟新的 Timeline。
	if Dialogic.current_timeline != null:
		return

	for child in get_children():

		if child is CutsceneDirector:

			var director: CutsceneDirector = child

			if (
				director.trigger_on_map_enter
				and not director.has_triggered
			):

				director.start_cutscene()

				break

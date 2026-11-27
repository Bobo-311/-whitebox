
extends CanvasLayer

# ============================================================
# 《眠境 RE:RECOLOR》
# SaveMenuUI V2｜正式畫架存檔介面
#
# Godot 4.5.1
#
# 職責：
# 1. 顯示目前地圖名稱
# 2. 接收目前畫架的正式身分
# 3. 處理存檔按鈕
# 4. 確認正式寫入成功後執行補給
# 5. 更新既有運行時重生資料
# 6. 保留原有地圖刷新機制
# 7. 維持貼紙、傳送及筆記本操作
#
# 不直接操作 JSON。
#
# CheckpointManager 負責檢查點資料。
# SaveManager 負責實際磁碟寫入。
# ============================================================


# ============================================================
# 1. 原有 Inspector 資源
#
# 保留原本變數名稱及類型。
# ============================================================

@export var sticker_ui_scene: PackedScene

@export var portal_menu_scene: PackedScene


# ============================================================
# 2. 除錯設定
# ============================================================

@export_group("除錯設定")

@export var debug_log: bool = true


# ============================================================
# 3. 節點及原有介面狀態
# ============================================================

@onready var map_name_label: Label = $LocationFrame/Label

var is_reading_from_savepoint: bool = false


# ============================================================
# 4. 本次畫架資料
#
# 由 SavePoint 開啟介面前傳入。
# 不由 UI 自行猜測目前是哪一個畫架。
# ============================================================

var _checkpoint_map_id: String = ""

var _checkpoint_easel_id: String = ""

var _source_save_point: Node2D = null

var _has_checkpoint_context: bool = false

## 防止玩家連續點擊存檔按鈕。
var _is_saving: bool = false


# ============================================================
# 5. 接收 SavePoint 傳入的資料
#
# 在加入 SceneTree 前呼叫。
# 因此不在此操作 @onready 節點。
# ============================================================

func configure_checkpoint(
	map_id: String,
	easel_id: String,
	source: Node2D
) -> void:

	_checkpoint_map_id = map_id

	_checkpoint_easel_id = easel_id

	_source_save_point = source

	_has_checkpoint_context = true


# ============================================================
# 6. 初始化
# ============================================================

func _ready() -> void:

	add_to_group("save_menu")

	if map_name_label:

		map_name_label.text = DataManager.current_map_name


# ============================================================
# 7. 原有 TAB / ESC 返回功能
# ============================================================

func _input(event: InputEvent) -> void:

	# 寫入期間禁止關閉介面。
	if _is_saving or is_queued_for_deletion():
		return

	if (
		event.is_action_pressed("TAB")
		or event.is_action_pressed("ESC")
	):

		# 從筆記本返回畫架。
		if is_reading_from_savepoint:

			var player = DataManager.player_node

			if is_instance_valid(player) and player.notebook_ui:

				player.notebook_ui.toggle_notebook(true)

			show()

			is_reading_from_savepoint = false

			get_viewport().set_input_as_handled()

			return

		# 從畫架返回正常遊戲。
		if visible:

			var player = DataManager.player_node

			if is_instance_valid(player):

				player.is_reading_book = false

			queue_free()

			get_viewport().set_input_as_handled()


# ============================================================
# 8. 原有受攻擊中斷介面機制
#
# 額外防止來源畫架被卸載後，
# 選單仍殘留於全域 root。
# ============================================================

func _process(_delta: float) -> void:

	if _is_saving or is_queued_for_deletion():
		return

	if _has_checkpoint_context:

		if not is_instance_valid(_source_save_point):

			queue_free()

			return

	var player = DataManager.player_node

	if is_instance_valid(player):

		if not player.is_reading_book:

			queue_free()


# ============================================================
# 9. 正式存檔按鈕
#
# 執行順序：
#
# A. 驗證目前玩家與畫架
# B. 取得正式出生點
# C. 寫入目前使用中的存檔
# D. 寫入成功才更新舊版重生資料
# E. 執行既有補給
# F. 重載目前地圖
#
# 存檔失敗不重載、不關閉介面。
# ============================================================

func _on_save_pressed() -> void:

	if _is_saving or is_queued_for_deletion():
		return

	if SceneTransition.is_transitioning:
		return

	var player = DataManager.player_node

	if not is_instance_valid(player):

		push_warning("【SaveMenuUI】找不到目前玩家")

		return

	if not player.is_reading_book:
		return

	var current_map: Node = get_tree().current_scene

	if not is_instance_valid(current_map):
		return

	if not current_map.is_ancestor_of(player):
		return

	# 確認選單由目前地圖的畫架開啟。
	if not _has_checkpoint_context:

		push_warning("【SaveMenuUI】缺少畫架身分資料")

		return

	if not is_instance_valid(_source_save_point):
		return

	if not current_map.is_ancestor_of(_source_save_point):
		return

	_is_saving = true

	# --------------------------------------------------------
	# A. 取得正式定位點
	# --------------------------------------------------------

	var marker: Marker2D = (
		CheckpointManager.get_current_spawn_marker(
			_checkpoint_map_id,
			_checkpoint_easel_id
		)
	)

	var respawn_position: Vector2 = player.global_position

	var is_formal_save: bool = (
		SaveManager.current_slot_id > 0
	)

	# --------------------------------------------------------
	# B. 正式存檔模式
	#
	# 從主選單選擇存檔進入遊戲時，
	# 必須通過所有正式驗證。
	# --------------------------------------------------------

	if is_formal_save:

		if not is_instance_valid(marker):

			push_warning(
				"【SaveMenuUI】畫架定位點不存在，禁止正式存檔"
			)

			_is_saving = false

			return

		respawn_position = marker.global_position

		var success: bool = (
			CheckpointManager.save_checkpoint(
				_checkpoint_map_id,
				_checkpoint_easel_id
			)
		)

		if not success:

			push_warning(
				"【SaveMenuUI】正式存檔失敗，保留畫架選單"
			)

			_is_saving = false

			return

	# --------------------------------------------------------
	# C. F6 開發測試模式
	#
	# 直接執行地圖時可能沒有正式存檔。
	#
	# 開發版本仍允許測試原有補給及刷新機制，
	# 但絕對不會自動建立或覆蓋四格存檔。
	#
	# 正式發行版本不允許此例外。
	# --------------------------------------------------------

	else:

		if not OS.is_debug_build():

			push_warning(
				"【SaveMenuUI】未載入正式存檔，取消操作"
			)

			_is_saving = false

			return

		if is_instance_valid(marker):

			respawn_position = marker.global_position

		if debug_log:

			print(
				"【SaveMenuUI】F6 測試模式：僅執行補給與地圖刷新，不寫入存檔"
			)

	# --------------------------------------------------------
	# D. 更新既有運行時重生資訊
	#
	# 此階段仍相容原本 player.gd 與 player_die.gd。
	#
	# 不再以玩家任意站立位置作為正式重生點，
	# 而是使用指定 Marker2D。
	# --------------------------------------------------------

	DataManager.last_save_position = respawn_position

	DataManager.save_map_path = current_map.scene_file_path

	# --------------------------------------------------------
	# E. 執行原本的畫架補給
	# --------------------------------------------------------

	_replenish_player(player)

	if debug_log:

		print(
			"【SaveMenuUI】運行時重生位置：",
			DataManager.last_save_position
		)

		print(
			"【SaveMenuUI】血量、墨水及快捷欄補給完成"
		)

	# --------------------------------------------------------
	# F. 保留原有地圖重載及普通敵人刷新方式
	#
	# 本次不改寫敵人生成或死亡重生架構。
	# --------------------------------------------------------

	var tree: SceneTree = get_tree()

	tree.paused = false

	var reload_error: Error = tree.reload_current_scene()

	if reload_error != OK:

		push_error(
			"【SaveMenuUI】檢查點操作已完成，但地圖刷新失敗："
			+ error_string(reload_error)
		)

		_is_saving = false

		return

	# 地圖重載要求受理後，銷毀畫架介面。
	queue_free()


# ============================================================
# 10. 保留原有畫架補給
#
# 玩家血量仍由既有 player.gd 的初始化機制
# 讀取 DataManager.saved_hp。
#
# 此函式目前不負責玩家永久資料序列化。
# ============================================================

func _replenish_player(player: Node2D) -> void:

	# A. 記錄最大血量
	DataManager.saved_hp = float(player.get("max_hp"))

	# B. 保留舊能量補給機制
	#
	# 最新 DataManager 不一定還有 saved_energy，
	# 因此必須確認三個欄位均存在，才進行操作。
	if (
		"max_energy" in player
		and "current_energy" in player
		and "saved_energy" in DataManager
	):

		var half_energy: int = int(
			float(player.get("max_energy")) * 0.5
		)

		var restored_energy: float = maxf(
			float(player.get("current_energy")),
			float(half_energy)
		)

		DataManager.set(
			"saved_energy",
			restored_energy
		)

	# C. 墨水補給
	if player.has_method("refill_full_ink"):

		player.call("refill_full_ink")

	# D. 顏料及快捷欄道具補給
	DataManager.replenish_quick_slots()


# ============================================================
# 11. 貼紙按鈕
#
# 保留原有介面生成及返回方式。
# ============================================================

func _on_sticker_pressed() -> void:

	if _is_saving or is_queued_for_deletion():
		return

	if sticker_ui_scene:

		var sticker_menu = sticker_ui_scene.instantiate()

		get_tree().root.add_child(sticker_menu)

		hide()


# ============================================================
# 12. 傳送按鈕
#
# 畫架快速傳送尚未正式製作，
# 暫時保留原有功能。
# ============================================================

func _on_teleport_pressed() -> void:

	if _is_saving or is_queued_for_deletion():
		return

	if portal_menu_scene:

		var portal_menu = portal_menu_scene.instantiate()

		get_tree().root.add_child(portal_menu)

		queue_free()


# ============================================================
# 13. 筆記本按鈕
#
# 保留原本玩家狀態及筆記本操作。
# ============================================================

func _on_inventory_pressed() -> void:

	if _is_saving or is_queued_for_deletion():
		return

	var player = DataManager.player_node

	if not is_instance_valid(player):
		return

	hide()

	player.is_reading_book = true

	player.opened_from_savepoint = true

	player.velocity = Vector2.ZERO

	if player.state_machine:

		player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED

	if player.notebook_ui:

		player.notebook_ui.toggle_notebook(false)

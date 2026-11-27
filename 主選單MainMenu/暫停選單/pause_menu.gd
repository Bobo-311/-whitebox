extends CanvasLayer
# ============================================================
# 《眠境 RE:RECOLOR》
# PauseMenu V1｜正式暫停及返回主選單管理器
# Godot 4.5.1
# Autoload：PauseMenu
# STEP 10.7.7-C
# ============================================================
# 主要職責：
# 1. 暫停及恢復遊戲世界。
# 2. 維持暫停期間的軟體滑鼠操作。
# 3. 保留暫時性道具效果的剩餘時間。
# 4. 返回主選單二次確認。
# 5. 使用 SceneTransition 正式黑幕轉場。
# 6. 結束目前存檔工作階段。
# 7. 清除舊場景及死亡靈魂資料。
#
# 返回主選單不是畫架存檔。
# 不寫入 JSON，不刪除存檔。
# ============================================================

# 1. 主選單場景及除錯設定
@export_group("主選單設定")
@export_file("*.tscn") var main_menu_path: String = ""

@export_group("除錯設定")
@export var debug_log: bool = true

# 2. 節點引用
@onready var overlay: Control = $Overlay
@onready var title_label: Label = $Overlay/Center/Panel/Margin/Content/Title
@onready var warning_label: Label = $Overlay/Center/Panel/Margin/Content/Warning
@onready var resume_button: Button = $Overlay/Center/Panel/Margin/Content/ResumeButton
@onready var return_button: Button = $Overlay/Center/Panel/Margin/Content/ReturnButton
@onready var confirm_button: Button = $Overlay/Center/Panel/Margin/Content/ConfirmButton
@onready var cancel_button: Button = $Overlay/Center/Panel/Margin/Content/CancelButton

# 3. 暫停及返回狀態
var _is_open: bool = false
var _is_confirming: bool = false
var _is_returning: bool = false
var _session_cleanup_completed: bool = false

# 4. DataManager 暫停前狀態
var _cursor_override_active: bool = false
var _previous_data_mode: int = Node.PROCESS_MODE_INHERIT
var _previous_data_processing: bool = true

# ============================================================
# 5. 初始化
# PauseMenu 需在暫停期間正常接收 UI 操作。
# ============================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 必須低於 DataManager 的軟體滑鼠 Layer 128。
	layer = 100
	resume_button.text = "繼續遊戲"
	return_button.text = "返回主選單"
	confirm_button.text = "確認返回"
	cancel_button.text = "取消"

	resume_button.pressed.connect(_on_resume_pressed)
	return_button.pressed.connect(_on_return_pressed)
	confirm_button.pressed.connect(_on_confirm_return)
	cancel_button.pressed.connect(_on_cancel_pressed)

	_show_normal_page()
	overlay.hide()
	set_process(false)

	_log("V1 遊戲暫停管理器初始化完成")
	if _has_valid_main_menu():
		_log("正式主選單已登記：" + main_menu_path)
	else:
		push_warning("【PauseMenu】尚未指定有效的主選單場景")

# ============================================================
# 6. 暫停期間的軟體滑鼠更新
#
# DataManager 一般 _process 暫時停用，
# 防止戰鬥道具效果繼續倒數。
# 這裡只更新滑鼠位置。
# ============================================================
func _process(_delta: float) -> void:
	if not _cursor_override_active:
		return
	if is_instance_valid(DataManager.cursor_rect):
		DataManager.cursor_rect.global_position = (
			get_viewport().get_mouse_position()
		)

# 7. 啟用暫停期間的滑鼠控制
func _enable_pause_cursor() -> void:
	if _cursor_override_active:
		return

	# 保存原始處理模式，不永久修改 DataManager。
	_previous_data_mode = DataManager.process_mode
	_previous_data_processing = DataManager.is_processing()
	_cursor_override_active = true

	# 保留 DataManager 原本的滑鼠點擊 _input。
	# 關閉一般 _process，避免遊戲相關計時繼續執行。
	DataManager.set_process(false)
	DataManager.process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

# 8. 還原原本 DataManager 運作狀態
func _restore_pause_cursor() -> void:
	if not _cursor_override_active:
		return
	_cursor_override_active = false
	set_process(false)

	DataManager.process_mode = _previous_data_mode
	DataManager.set_process(_previous_data_processing)

# ============================================================
# 9. 查詢主選單及暫停狀態
# ============================================================
func _has_valid_main_menu() -> bool:
	return (
		not main_menu_path.is_empty()
		and ResourceLoader.exists(main_menu_path, "PackedScene")
	)

func is_open() -> bool:
	return _is_open

# ============================================================
# 10. 驗證是否允許開啟暫停選單
#
# 劇情、購物、死亡、轉場及閱讀筆記本期間，
# 維持原有操作鎖及 ESC 行為。
# ============================================================
func can_open_pause() -> bool:
	if _is_open or _is_returning:
		return false
	if get_tree().paused:
		return false
	if SaveManager.current_slot_id <= 0:
		return false
	if SceneTransition.is_transitioning:
		return false
	if RespawnManager.is_respawning:
		return false
	if Dialogic.current_timeline != null:
		return false

	var player: Player = DataManager.player_node as Player
	if not is_instance_valid(player):
		return false

	var current_map: Node = get_tree().current_scene
	if not is_instance_valid(current_map):
		return false
	if player != current_map and not current_map.is_ancestor_of(player):
		return false

	if player.is_dead:
		return false
	if player.is_in_dialogue:
		return false
	if player.is_reading_book:
		return false
	if player.is_shopping:
		return false

	# 保留開發者劇照及時間定格模式。
	if "_photo_mode_Active" in player:
		if bool(player.get("_photo_mode_Active")):
			return false
	if Engine.time_scale <= 0.0:
		return false
	return true

# ============================================================
# 11. 正式開啟暫停選單
# 由玩家子節點 PauseInput 呼叫。
# ============================================================
func request_pause() -> bool:
	if not can_open_pause():
		return false

	_is_open = true
	_is_confirming = false
	_show_normal_page()
	show()
	overlay.show()

	_enable_pause_cursor()
	get_tree().paused = true
	resume_button.grab_focus()

	_log("已開啟暫停選單")
	_log("目前存檔：Slot %02d" % SaveManager.current_slot_id)
	_log("SceneTree.paused：true")
	return true

# ============================================================
# 12. 暫停選單 ESC 處理
#
# 確認頁面：取消返回。
# 暫停頁面：恢復遊戲。
# ============================================================
func _input(event: InputEvent) -> void:
	if not _is_open or _is_returning:
		return
	if event.is_action_pressed("ESC"):
		get_viewport().set_input_as_handled()
		if _is_confirming:
			_on_cancel_pressed()
		else:
			_on_resume_pressed()

# 13. 顯示一般暫停頁面
func _show_normal_page() -> void:
	_is_confirming = false
	title_label.text = "遊戲暫停"
	warning_label.hide()
	resume_button.show()
	return_button.show()
	confirm_button.hide()
	cancel_button.hide()

# 14. 顯示返回確認頁面
func _show_confirmation_page() -> void:
	_is_confirming = true
	title_label.text = "返回主選單"
	warning_label.text = "確定要返回主選單嗎？\n尚未保存的進度將會遺失。"
	warning_label.show()
	resume_button.hide()
	return_button.hide()
	confirm_button.show()
	cancel_button.show()

	# 預設選取取消，避免誤操作。
	cancel_button.grab_focus()

# ============================================================
# 15. 恢復遊戲
# ============================================================
func _on_resume_pressed() -> void:
	if not _is_open or _is_returning:
		return
	_is_open = false
	_is_confirming = false
	overlay.hide()
	_restore_pause_cursor()
	get_tree().paused = false
	_log("已恢復遊戲")
	_log("SceneTree.paused：false")

# 16. 提出返回主選單要求
func _on_return_pressed() -> void:
	if not _is_open or _is_returning:
		return
	_show_confirmation_page()
	_log("等待玩家確認返回主選單")

# 17. 取消返回
func _on_cancel_pressed() -> void:
	if not _is_open or _is_returning:
		return
	_show_normal_page()
	resume_button.grab_focus()
	_log("已取消返回主選單")

# ============================================================
# 18. 正式確認返回主選單
# 舊場景仍在時保留運行時資料。
# 只有主選單成功載入才執行工作階段清理。
# ============================================================
func _on_confirm_return() -> void:
	if not _is_open or not _is_confirming or _is_returning:
		return
	if SceneTransition.is_transitioning:
		return
	if not _has_valid_main_menu():
		_show_return_error("主選單場景尚未設定或資源不存在")
		return
	if SaveManager.current_slot_id <= 0:
		_show_return_error("目前沒有正式存檔工作階段")
		return

	_is_returning = true
	_session_cleanup_completed = false
	overlay.hide()

	_log("玩家已確認返回主選單")
	_log("離開目前存檔：Slot %02d" % SaveManager.current_slot_id)

	# 一次性接收本次正式轉場結果。
	SceneTransition.transition_settled.connect(
		_on_return_transition_settled,
		CONNECT_ONE_SHOT
	)

	SceneTransition.change_to_main_menu(
		main_menu_path,
		_on_main_menu_scene_ready
	)

# ============================================================
# 19. 清除舊場景運行時資料
#
# 必須在舊場景卸載後執行。
# 永久玩家資料由 PlayerProgress 重設。
# 永久劇情資料由 StoryProgress 重設。
# ============================================================
func _clear_runtime_world_data() -> void:
	# A. 舊玩家及地圖引用。
	DataManager.player_node = null
	DataManager.current_map_name = "鐘塔"
	DataManager.is_teleporting = false

	# B. 運行時重生資料。
	DataManager.last_save_position = Vector2.ZERO
	DataManager.saved_hp = 0.0
	DataManager.save_map_path = ""

	# C. 舊存檔死亡靈魂。
	DataManager.has_soul_on_ground = false
	DataManager.soul_spawn_pos = Vector2.ZERO
	DataManager.soul_stored_gold = 0
	DataManager.soul_map_path = ""

	# D. 舊道具效果及 HUD 引用。
	DataManager.combat_item_seconds.clear()
	DataManager.buff_seconds_labels.clear()
	DataManager.buff_stack = null

	_log("舊玩家節點引用已清除")
	_log("運行時重生資料已清除")
	_log("死亡靈魂資料已清除")
	_log("舊場景工作階段已重設")

# ============================================================
# 20. 主選單完成建立
#
# 舊場景已卸載，黑幕尚未淡出。
# 此時安全清除上一格存檔的記憶體。
# ============================================================
func _on_main_menu_scene_ready() -> void:
	if not _is_returning:
		return

	# A. 清除場景引用、靈魂及重生資料。
	_clear_runtime_world_data()

	# B. 結束正式存檔工作階段。
	# SaveManager 將通知 StoryProgress 及 PlayerProgress。
	SaveManager.close_session()

	# C. 恢復正常運作。
	_restore_pause_cursor()
	Engine.time_scale = 1.0
	get_tree().paused = false

	_session_cleanup_completed = true
	_is_open = false
	_is_confirming = false
	_show_normal_page()
	overlay.hide()

	_log("正式工作階段清理完成")
	_log("SaveManager.current_slot_id：" + str(SaveManager.current_slot_id))
	_log("PlayerProgress 工作階段：" + str(PlayerProgress.get_loaded_slot_id()))
	_log("SceneTree.paused：" + str(get_tree().paused))

# ============================================================
# 21. 接收返回主選單的最終轉場結果
# ============================================================
func _on_return_transition_settled(
	success: bool,
	scene_path: String
) -> void:
	if not _is_returning:
		return
	_is_returning = false

	if success and _session_cleanup_completed:
		_log("正式返回主選單成功：" + scene_path)
		_log("本次返回主選單未寫入 JSON")
		return

	# 轉場失敗且舊玩家仍存在：
	# 保留原本工作階段，重新顯示暫停選單。
	if is_instance_valid(DataManager.player_node):
		_is_open = true
		get_tree().paused = true
		overlay.show()
		_show_return_error("無法載入主選單，請重新嘗試")
	else:
		# 舊場景已不存在時，不讓遊戲永久卡在暫停。
		_clear_runtime_world_data()
		SaveManager.close_session()
		_restore_pause_cursor()
		_is_open = false
		_is_confirming = false
		overlay.hide()
		Engine.time_scale = 1.0
		get_tree().paused = false
		push_error("【PauseMenu】轉場失敗且舊玩家不存在")

# 22. 返回失敗提示
func _show_return_error(reason: String) -> void:
	_show_normal_page()
	warning_label.text = reason
	warning_label.show()
	resume_button.grab_focus()
	push_warning("【PauseMenu】" + reason)

# 23. 統一除錯輸出
func _log(message: String) -> void:
	if debug_log:
		print("【PauseMenu】" + message)

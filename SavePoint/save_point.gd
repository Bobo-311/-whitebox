extends Area2D

# ============================================================
# 《眠境 RE:RECOLOR》
# SavePoint V3｜畫架互動與永久劇情保存
#
# Godot 4.5.1
# Dialogic 2.0-Alpha-21
#
# STEP 10.6.6
#
# ============================================================
# 保留原有功能
# ============================================================
#
# 1. E 鍵互動畫架
# 2. 浮動提示動畫
# 3. 初見畫架劇情
# 4. 藍色顏料解鎖
# 5. 開啟畫架時補給道具
# 6. 生成畫架存檔選單
# 7. 防止重複開啟介面
# 8. 正式地圖及畫架 ID 傳遞
#
# ============================================================
# V3 新增功能
# ============================================================
#
# 1. 接收 A006B 正式劇情完成暗號
# 2. 等待完整劇情演出結束
# 3. 驗證正式存檔工作階段
# 4. 交由 StoryProgress 保存永久劇情
# 5. 存檔成功後才正式解鎖顏料
# 6. 保存失敗時允許重新互動
# 7. 保留 F6 獨立開發測試模式
#
# ============================================================
# 系統分工
# ============================================================
#
# SavePoint：
# 負責畫架互動及初見劇情演出。
#
# StoryProgress：
# 負責永久劇情與顏料解鎖紀錄。
#
# CheckpointManager：
# 負責正式畫架及重生定位資料。
#
# SaveManager：
# 負責 JSON 實體讀寫。
#
# SaveMenuUI：
# 負責正式畫架存檔操作。
#
# ============================================================
# 注意事項
# ============================================================
#
# 按 E 不等於正式保存檢查點。
#
# A006B 完成後，只保存劇情及顏料解鎖。
# 不提前修改玩家的正式重生位置。
#
# 正式重生點仍必須由玩家按下存檔按鈕更新。
# ============================================================


# ============================================================
# 1. 原有 Inspector 設定
#
# 保留原有欄位名稱及類型。
# ============================================================

@export var save_menu_scene: PackedScene

@export var first_time_timeline: String = "first_easel"


# ============================================================
# 2. 正式畫架身分設定
# ============================================================

@export_group("正式存檔定位")

@export var map_id: String = ""

@export var easel_id: String = ""


# ============================================================
# 3. 除錯設定
# ============================================================

@export_group("除錯設定")

@export var debug_log: bool = true


# ============================================================
# 4. A006B 正式劇情設定
# ============================================================

const FIRST_EASEL_TIMELINE: String = "A006B"

const FIRST_EASEL_COMMIT_SIGNAL: String = "story_commit:A006B"

const FIRST_EASEL_ITEM_ID: String = "hp_paint"


# ============================================================
# 5. 節點與運行狀態
# ============================================================

@onready var interact_prompt = $InteractPrompt

var player_in_range: bool = false

var tween: Tween

var prompt_original_y: float

var current_menu_instance: Node = null

## 是否正在播放初見畫架劇情。
var _is_playing_first_cutscene: bool = false


# ============================================================
# 6. A006B 劇情完成驗證資料
# ============================================================

## 是否收到正式劇情完成暗號。
var _first_easel_signal_received: bool = false

## 是否收到 timeline_ended 訊號。
var _first_easel_timeline_ended: bool = false

## 開始播放劇情時的存檔欄位。
##
## 0 代表 F6 獨立開發測試模式。
var _first_easel_slot_id: int = 0


# ============================================================
# 7. 初始化
#
# 原有 body_entered / body_exited 訊號
# 已在場景中連接，不再重複連接。
# ============================================================

func _ready() -> void:

	interact_prompt.hide()

	prompt_original_y = interact_prompt.position.y


# ============================================================
# 8. 玩家互動偵測
# ============================================================

func _process(_delta: float) -> void:

	var player = DataManager.player_node

	if not is_instance_valid(player):

		hide_prompt()

		return

	# 轉場期間禁止互動畫架。
	if SceneTransition.is_transitioning:

		hide_prompt()

		return

	# 玩家正在使用其他功能時，
	# 不允許同時開啟畫架。
	if (
		player.is_reading_book
		or player.is_in_dialogue
		or player.is_shopping
		or _is_playing_first_cutscene
	):

		if interact_prompt.visible:

			hide_prompt()

		return

	# 玩家進入範圍後，顯示互動提示。
	if (
		player_in_range
		and not interact_prompt.visible
		and not is_instance_valid(current_menu_instance)
	):

		show_prompt()

	# 必須位於畫架感應範圍內。
	if not player_in_range:
		return

	# 必須按下互動鍵。
	if not Input.is_action_just_pressed("interact"):
		return

	# 禁止生成重複的畫架選單。
	if is_instance_valid(current_menu_instance):
		return

	# 其他劇情播放期間禁止互動。
	if Dialogic.current_timeline != null:
		return

	# --------------------------------------------------------
	# A. 第一次互動畫架
	# --------------------------------------------------------

	if (
		not first_time_timeline.is_empty()
		and not DataManager.is_cutscene_completed(
			first_time_timeline
		)
	):

		_trigger_first_time_cutscene()

		return

	# --------------------------------------------------------
	# B. 已完成初見畫架劇情
	#
	# 正常開啟畫架選單。
	# --------------------------------------------------------

	_open_save_menu()


# ============================================================
# 9. 開啟畫架選單
#
# 保留 SavePoint V2 的正式畫架身分傳遞方式。
# ============================================================

func _open_save_menu() -> void:

	if save_menu_scene == null:

		push_warning(
			"【SavePoint】尚未指定畫架選單場景"
		)

		return

	var player = DataManager.player_node

	if not is_instance_valid(player):
		return

	# 建立既有畫架選單。
	var menu: Node = save_menu_scene.instantiate()

	if not menu.has_method("configure_checkpoint"):

		menu.free()

		push_error(
			"【SavePoint】畫架選單缺少 configure_checkpoint()"
		)

		return

	# 在加入場景樹前傳入正式畫架身分。
	menu.call(
		"configure_checkpoint",
		map_id,
		easel_id,
		self
	)

	# 保留原有畫架開啟時的道具補給。
	if DataManager.has_method("replenish_quick_slots"):

		DataManager.replenish_quick_slots()

	# 暫時限制玩家操作。
	player.is_reading_book = true

	if "velocity" in player:

		player.velocity = Vector2.ZERO

	hide_prompt()

	current_menu_instance = menu

	# 選單關閉後，自動清除引用。
	menu.tree_exited.connect(
		_on_menu_closed
	)

	# 保留原有 root 掛載方式。
	get_tree().root.add_child(menu)

	if debug_log:

		print(
			"【SavePoint】開啟畫架：%s / %s"
			% [map_id, easel_id]
		)


# ============================================================
# 10. 畫架選單關閉
# ============================================================

func _on_menu_closed() -> void:

	current_menu_instance = null


# ============================================================
# 11. 第一次觸碰畫架
#
# V3 核心修改。
#
# A006B 不再於播放前標記完成。
# A006B 不再於播放前解鎖顏料。
#
# 其餘尚未正式整合的初見劇情，
# 暫時保留原有運行時行為。
# ============================================================

func _trigger_first_time_cutscene() -> void:

	if _is_playing_first_cutscene:
		return

	if Dialogic.current_timeline != null:
		return

	var player = DataManager.player_node

	if not is_instance_valid(player):
		return

	hide_prompt()

	_is_playing_first_cutscene = true

	# --------------------------------------------------------
	# A. 初始化本次劇情驗證資料
	# --------------------------------------------------------

	_first_easel_signal_received = false

	_first_easel_timeline_ended = false

	_first_easel_slot_id = SaveManager.current_slot_id

	# --------------------------------------------------------
	# B. 區分 A006B 與其他舊版劇情
	# --------------------------------------------------------

	if first_time_timeline == FIRST_EASEL_TIMELINE:

		# A006B 必須等待正式完成暗號。
		# 不提前寫入永久劇情。
		# 不提前解鎖顏料。

		if not Dialogic.signal_event.is_connected(
			_on_first_cutscene_signal
		):

			Dialogic.signal_event.connect(
				_on_first_cutscene_signal
			)

		if debug_log:

			print(
				"【SavePoint】開始 A006B 初見畫架劇情"
			)

			print(
				"【SavePoint】目前存檔欄位：",
				_first_easel_slot_id
			)

	else:

		# 尚未正式整合的舊版畫架劇情，
		# 保留原有運行時機制。

		DataManager.mark_cutscene_completed(
			first_time_timeline
		)

		if DataManager.has_method("unlock_auto_refill_item"):

			DataManager.unlock_auto_refill_item(
				FIRST_EASEL_ITEM_ID
			)

	# --------------------------------------------------------
	# C. 暫時鎖定玩家操作
	# --------------------------------------------------------

	player.is_in_dialogue = true

	if "velocity" in player:

		player.velocity = Vector2.ZERO

	if player.state_machine:

		player.state_machine.process_mode = (
			Node.PROCESS_MODE_DISABLED
		)

	if player.animated_sprite_2d:

		player.animated_sprite_2d.play(
			"idle_down"
		)

	# --------------------------------------------------------
	# D. 監聽劇情正式結束
	# --------------------------------------------------------

	if not Dialogic.timeline_ended.is_connected(
		_on_first_cutscene_ended
	):

		Dialogic.timeline_ended.connect(
			_on_first_cutscene_ended
		)

	# --------------------------------------------------------
	# E. 播放原有 Dialogic 劇情
	# --------------------------------------------------------

	Dialogic.start(first_time_timeline)

	# 保留專案原本的劇情開始通知方式。
	Dialogic.timeline_started.emit()


# ============================================================
# 12. 接收 A006B 正式完成暗號
#
# 此處只記錄劇情抵達完成位置。
# 尚未真正寫入存檔。
# ============================================================

func _on_first_cutscene_signal(
	argument: String
) -> void:

	if not _is_playing_first_cutscene:
		return

	if first_time_timeline != FIRST_EASEL_TIMELINE:
		return

	if argument != FIRST_EASEL_COMMIT_SIGNAL:
		return

	if Dialogic.current_timeline == null:
		return

	# 確認劇情播放期間沒有切換存檔。
	if SaveManager.current_slot_id != _first_easel_slot_id:

		push_warning(
			"【SavePoint】劇情工作階段已變更，拒絕完成暗號"
		)

		return

	# 不重複處理相同完成暗號。
	if _first_easel_signal_received:
		return

	_first_easel_signal_received = true

	if debug_log:

		print(
			"【SavePoint】已收到 A006B 正式完成暗號"
		)


# ============================================================
# 13. 提供 StoryProgress 的正式完成驗證接口
#
# 必須同時收到：
# A. 正式劇情完成暗號
# B. timeline_ended 訊號
#
# 才允許正式保存 A006B。
# ============================================================

func can_commit_first_easel() -> bool:

	return (
		_is_playing_first_cutscene
		and first_time_timeline == FIRST_EASEL_TIMELINE
		and _first_easel_signal_received
		and _first_easel_timeline_ended
		and SaveManager.current_slot_id == _first_easel_slot_id
	)


# ============================================================
# 14. 初見畫架劇情正式結束
# ============================================================

func _on_first_cutscene_ended() -> void:

	if not _is_playing_first_cutscene:
		return

	# 先解除訊號監聽，
	# 防止後續其他劇情重複觸發。
	_disconnect_first_cutscene_signals()

	# --------------------------------------------------------
	# A. 處理正式 A006B 永久保存
	# --------------------------------------------------------

	if first_time_timeline == FIRST_EASEL_TIMELINE:

		_first_easel_timeline_ended = true

		var success: bool = (
			_finish_first_easel_progress()
		)

		if success:

			if debug_log:

				print(
					"【SavePoint】A006B 初見畫架處理完成"
				)

		else:

			# 不標記完成。
			# 玩家仍可重新互動畫架進行重試。

			push_warning(
				"【SavePoint】A006B 尚未正式保存，可重新互動畫架"
			)

	# --------------------------------------------------------
	# B. 清除本次劇情驗證資料
	# --------------------------------------------------------

	_is_playing_first_cutscene = false

	_first_easel_signal_received = false

	_first_easel_timeline_ended = false

	_first_easel_slot_id = 0

	# --------------------------------------------------------
	# C. 恢復玩家操作
	# --------------------------------------------------------

	var player = DataManager.player_node

	if is_instance_valid(player):

		player.is_in_dialogue = false

		if player.state_machine:

			player.state_machine.process_mode = (
				Node.PROCESS_MODE_INHERIT
			)

	# --------------------------------------------------------
	# D. 恢復畫架互動提示
	# --------------------------------------------------------

	if player_in_range:

		show_prompt()


# ============================================================
# 15. 正式處理 A006B 完成結果
#
# 正式模式：
# 交由 StoryProgress 寫入永久存檔。
#
# F6 模式：
# 僅更新運行時資料，不建立或覆蓋正式存檔。
# ============================================================

func _finish_first_easel_progress() -> bool:

	if not can_commit_first_easel():

		push_warning(
			"【SavePoint】未通過 A006B 完成驗證"
		)

		return false

	# --------------------------------------------------------
	# A. 正式遊戲存檔模式
	# --------------------------------------------------------

	if _first_easel_slot_id > 0:

		return StoryProgress.commit_first_easel(self)

	# --------------------------------------------------------
	# B. F6 獨立開發測試模式
	# --------------------------------------------------------

	if not OS.is_debug_build():

		push_warning(
			"【SavePoint】正式版本不可在無存檔狀態解鎖顏料"
		)

		return false

	# 僅修改運行時資料。
	DataManager.mark_cutscene_completed(
		FIRST_EASEL_TIMELINE
	)

	DataManager.unlock_auto_refill_item(
		FIRST_EASEL_ITEM_ID
	)

	if debug_log:

		print(
			"【SavePoint】F6 測試模式：A006B 運行時完成"
		)

		print(
			"【SavePoint】F6 測試模式：顏料已解鎖，未寫入 JSON"
		)

	return true


# ============================================================
# 16. 解除初見劇情訊號監聽
#
# 避免畫架重複互動或地圖卸載後，
# 留下不必要的 Dialogic 監聽。
# ============================================================

func _disconnect_first_cutscene_signals() -> void:

	if Dialogic.signal_event.is_connected(
		_on_first_cutscene_signal
	):

		Dialogic.signal_event.disconnect(
			_on_first_cutscene_signal
		)

	if Dialogic.timeline_ended.is_connected(
		_on_first_cutscene_ended
	):

		Dialogic.timeline_ended.disconnect(
			_on_first_cutscene_ended
		)


# ============================================================
# 17. E 鍵浮動提示
# ============================================================

func show_prompt() -> void:

	interact_prompt.show()

	if tween:

		tween.kill()

	tween = create_tween().set_loops()

	tween.tween_property(
		interact_prompt,
		"position:y",
		prompt_original_y - 15.0,
		0.5
	).set_trans(Tween.TRANS_SINE)

	tween.tween_property(
		interact_prompt,
		"position:y",
		prompt_original_y,
		0.5
	).set_trans(Tween.TRANS_SINE)


func hide_prompt() -> void:

	interact_prompt.hide()

	if tween:

		tween.kill()

		tween = null

	interact_prompt.position.y = prompt_original_y


# ============================================================
# 18. 玩家進入及離開感應區
#
# 保留原本的訊號函式名稱。
# ============================================================

func _on_body_entered(body) -> void:

	if body is Player:

		player_in_range = true

		if (
			not body.is_in_dialogue
			and not body.is_reading_book
			and not SceneTransition.is_transitioning
		):

			show_prompt()


func _on_body_exited(body) -> void:

	if body is Player:

		player_in_range = false

		hide_prompt()


# ============================================================
# 19. 場景卸載清理
#
# 地圖卸載時只清理訊號與動畫。
# 不將尚未完成的劇情寫入存檔。
# ============================================================

func _exit_tree() -> void:

	if is_instance_valid(Dialogic):

		_disconnect_first_cutscene_signals()

	if tween:

		tween.kill()


extends Area2D

# ============================================================
# 《眠境 RE:RECOLOR》
# ShopNPC V2｜正式商店互動與生命週期管理器
# Godot 4.5.1
# STEP 10.7.7-F-4
# ============================================================
# 主要職責：
# 1. 管理商人互動範圍
# 2. 管理 E 鍵互動提示及動畫
# 3. 驗證目前玩家及場景狀態
# 4. 防止重複建立商店介面
# 5. 自動清除已銷毀的商店引用
# 6. 管理商店介面的生命週期
# 7. 防止轉場期間開啟商店
# 8. 防止跨地圖後殘留商店介面
# 9. 保留商人交貨及 Talk 劇情
#
# 系統分工：
# ShopNPC：商人互動及商店生命週期。
# ShopUI：商品驗證及交易操作。
# DataManager：運行時玩家資料。
# CheckpointManager：畫架正式保存。
# SaveManager：JSON 磁碟管理。
#
# 本腳本不直接操作金幣、背包及 JSON。
# ============================================================

# ============================================================
# 1. Inspector 設定
# ============================================================
@export var shop_ui_scene: PackedScene
@export var talk_timeline: String = ""

@export_group("📦 貨物任務階段設定")
@export var quest_condition: String = "A014D"
@export var quest_turn_in_timeline: String = "A014E"
@export var after_quest_talk_timeline: String = "A015"

@export_group("除錯設定")
@export var debug_log: bool = true

# ============================================================
# 2. 節點及運行時狀態
# ============================================================
@onready var interact_prompt: Sprite2D = $InteractPrompt

var player_in_range: bool = false
var tween: Tween
var prompt_original_y: float = 0.0

# 目前由此商人建立的商店介面。
var current_shop_instance: Node = null

# 目前商店的實例編號。
# 防止舊商店的銷毀訊號影響新的商店。
var _shop_instance_id: int = 0

# 交貨劇情播放狀態。
var _is_playing_quest_dialogue: bool = false

# 記錄目前進入互動範圍的玩家。
var _nearby_player: Player = null

# 記錄交貨劇情開始時的玩家。
var _quest_player: Player = null

# ============================================================
# 3. 初始化
# ============================================================
func _ready() -> void:
	interact_prompt.hide()
	prompt_original_y = interact_prompt.position.y

	if not SceneTransition.transition_started.is_connected(
		_on_transition_started
	):
		SceneTransition.transition_started.connect(
			_on_transition_started
		)

	if debug_log:
		print("【商店NPC】ShopNPC V2 初始化完成")

# ============================================================
# 4. 商店互動更新
# ============================================================
func _process(_delta: float) -> void:
	# 玩家已經卸載或不再有效時，
	# 不允許舊商店繼續運行。
	if not is_instance_valid(DataManager.player_node):
		player_in_range = false
		_nearby_player = null
		_hide_interact_prompt()
		_close_current_shop("目前玩家已不存在")
		return

	# 防止轉場及暫停期間重新開啟商店。
	if SceneTransition.is_transitioning or get_tree().paused:
		_hide_interact_prompt()
		return

	# 交貨劇情期間不接受重複互動。
	if _is_playing_quest_dialogue:
		_hide_interact_prompt()
		return

	# 玩家不在商人互動範圍內。
	if not player_in_range:
		_hide_interact_prompt()
		return

	# 確認目前互動的玩家仍為正式玩家。
	if not is_instance_valid(_nearby_player):
		player_in_range = false
		_hide_interact_prompt()
		return

	if DataManager.player_node != _nearby_player:
		player_in_range = false
		_nearby_player = null
		_hide_interact_prompt()
		_close_current_shop("目前玩家引用已變更")
		return

	var player: Player = _nearby_player

	# 劇情、購物及閱讀筆記本期間，
	# 隱藏商人的 E 鍵提示。
	if (
		player.is_in_dialogue
		or player.is_shopping
		or player.is_reading_book
		or Dialogic.current_timeline != null
	):
		_hide_interact_prompt()
		return

	# 已存在商店時禁止重複建立。
	if _has_active_shop():
		_hide_interact_prompt()
		return

	# 合法互動狀態下顯示 E 鍵。
	if not interact_prompt.visible:
		show_prompt()

	# 沿用原本 interact 輸入動作。
	if Input.is_action_just_pressed("interact"):
		_handle_interaction()

# ============================================================
# 5. 正式商人互動入口
# ============================================================
func _handle_interaction() -> void:
	if not _can_interact():
		return

	# 保留原本的貨物任務判斷。
	var has_cargo: bool = (
		(
			not quest_condition.is_empty()
			and DataManager.is_cutscene_completed(
				quest_condition
			)
		)
		or DataManager.is_cutscene_completed("got_cargo")
	)

	var has_turned_in: bool = (
		quest_turn_in_timeline.is_empty()
		or DataManager.is_cutscene_completed(
			quest_turn_in_timeline
		)
	)

	# 已取得貨物但尚未交貨：
	# 優先播放交貨劇情，不開啟商店。
	if has_cargo and not has_turned_in:
		_start_quest_turn_in()
		return

	# 其餘情況正常開啟商店。
	_open_shop(has_turned_in)

# ============================================================
# 6. 驗證目前互動條件
# ============================================================
func _can_interact() -> bool:
	if not player_in_range:
		return false

	if SceneTransition.is_transitioning:
		return false

	if get_tree().paused:
		return false

	if _is_playing_quest_dialogue:
		return false

	if _has_active_shop():
		return false

	if not is_instance_valid(_nearby_player):
		return false

	if DataManager.player_node != _nearby_player:
		return false

	var player: Player = _nearby_player

	if player.is_in_dialogue:
		return false

	if player.is_shopping:
		return false

	if player.is_reading_book:
		return false

	if Dialogic.current_timeline != null:
		return false

	return true

# ============================================================
# 7. 檢查商店實例
#
# 不能只使用 current_shop_instance != null。
# 必須確認物件尚未被引擎銷毀。
# ============================================================
func _has_active_shop() -> bool:
	if not is_instance_valid(current_shop_instance):
		current_shop_instance = null
		_shop_instance_id = 0
		return false

	# 即使已經排入 queue_free，
	# 也要等舊商店真正離開場景樹，
	# 才允許建立下一個商店。
	return true

# ============================================================
# 8. 正式開啟商店
#
# ShopUI V2 自己會在 _ready() 初始化。
# 此處不再重複呼叫 switch_to_main_menu()。
# ============================================================
func _open_shop(has_turned_in: bool) -> void:
	if not _can_interact():
		return

	if shop_ui_scene == null:
		push_warning("【商店NPC】尚未設定 Shop UI Scene")
		return

	var instance: Node = shop_ui_scene.instantiate()

	if not is_instance_valid(instance):
		push_warning("【商店NPC】無法建立商店介面")
		return

	# 保留原本的商人劇本切換規則。
	if "talk_timeline" in instance:
		if (
			has_turned_in
			and not after_quest_talk_timeline.is_empty()
		):
			instance.set(
				"talk_timeline",
				after_quest_talk_timeline
			)
		else:
			instance.set(
				"talk_timeline",
				talk_timeline
			)

	# 在加入場景樹前登記商店引用。
	current_shop_instance = instance
	_shop_instance_id = instance.get_instance_id()

	# 商店銷毀後，自動清除 NPC 保存的引用。
	instance.tree_exited.connect(
		_on_shop_tree_exited.bind(_shop_instance_id),
		CONNECT_ONE_SHOT
	)

	_hide_interact_prompt()

	# 沿用原本的全域 UI 掛載方式，
	# 避免影響既有 CanvasLayer 顯示層級。
	get_tree().root.add_child(instance)

	if debug_log:
		print("【商店NPC】商店介面已建立")
		print(
			"【商店NPC】目前存檔：Slot %02d"
			% SaveManager.current_slot_id
		)

# ============================================================
# 9. 商店銷毀完成
#
# 玩家正常退出、外部關閉或轉場時，
# 都會經過此引用清除流程。
# ============================================================
func _on_shop_tree_exited(instance_id: int) -> void:
	if instance_id != _shop_instance_id:
		return

	current_shop_instance = null
	_shop_instance_id = 0

	if debug_log:
		print("【商店NPC】舊商店介面引用已清除")

# ============================================================
# 10. 統一關閉目前商店
#
# 保留 ShopUI V2 自己的關閉機制。
# 不直接修改任何玩家永久資料。
# ============================================================
func _close_current_shop(reason: String) -> void:
	if not _has_active_shop():
		return

	var instance: Node = current_shop_instance

	if instance.is_queued_for_deletion():
		return

	if debug_log:
		print("【商店NPC】關閉商店原因：", reason)

	if instance.has_method("_close_shop"):
		instance.call("_close_shop", false)
	else:
		if is_instance_valid(_nearby_player):
			_nearby_player.is_shopping = false

		instance.queue_free()

# ============================================================
# 11. 啟動交貨劇情
#
# 保留原有 A014D / A014E 任務流程。
# 不在本階段更改永久任務保存規則。
# ============================================================
func _start_quest_turn_in() -> void:
	if _is_playing_quest_dialogue:
		return

	if quest_turn_in_timeline.is_empty():
		return

	if Dialogic.current_timeline != null:
		return

	if not is_instance_valid(_nearby_player):
		return

	_hide_interact_prompt()
	_is_playing_quest_dialogue = true
	_quest_player = _nearby_player

	# 沿用原始劇情標記方式。
	DataManager.mark_cutscene_completed(
		quest_turn_in_timeline
	)

	var player: Player = _quest_player

	player.is_in_dialogue = true
	player.velocity = Vector2.ZERO

	if is_instance_valid(player.state_machine):
		player.state_machine.process_mode = (
			Node.PROCESS_MODE_DISABLED
		)

	if is_instance_valid(player.animated_sprite_2d):
		player.animated_sprite_2d.play("idle_down")

	if not Dialogic.timeline_ended.is_connected(
		_on_quest_dialogue_ended
	):
		Dialogic.timeline_ended.connect(
			_on_quest_dialogue_ended,
			CONNECT_ONE_SHOT
		)

	if debug_log:
		print(
			"【商店NPC】開始交貨劇情：",
			quest_turn_in_timeline
		)

	# 保留原版 Dialogic 啟動方式。
	Dialogic.start(quest_turn_in_timeline)
	Dialogic.timeline_started.emit()

# ============================================================
# 12. 交貨劇情結束
# ============================================================
func _on_quest_dialogue_ended() -> void:
	if not _is_playing_quest_dialogue:
		return

	_is_playing_quest_dialogue = false

	var player: Player = _quest_player
	_quest_player = null

	if is_instance_valid(player):
		if DataManager.player_node == player:
			player.is_in_dialogue = false

			if is_instance_valid(player.state_machine):
				player.state_machine.process_mode = (
					Node.PROCESS_MODE_INHERIT
				)

	if debug_log:
		print("【商店NPC】交貨劇情已結束")

	if _can_interact():
		show_prompt()

# ============================================================
# 13. 顯示 E 鍵提示及浮動動畫
# ============================================================
func show_prompt() -> void:
	if not is_instance_valid(interact_prompt):
		return

	if interact_prompt.visible:
		return

	interact_prompt.show()

	if tween and tween.is_valid():
		tween.kill()

	interact_prompt.position.y = prompt_original_y

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

# ============================================================
# 14. 單純隱藏互動提示
#
# 隱藏 E 鍵不代表要關閉商店。
# 兩者必須分開處理。
# ============================================================
func _hide_interact_prompt() -> void:
	if not is_instance_valid(interact_prompt):
		return

	interact_prompt.hide()

	if tween and tween.is_valid():
		tween.kill()

	tween = null
	interact_prompt.position.y = prompt_original_y

# ============================================================
# 15. 保留原版 hide_prompt() 接口
#
# 玩家離開商人範圍時，
# 同時關閉互動提示與商店。
# ============================================================
func hide_prompt() -> void:
	_hide_interact_prompt()
	_close_current_shop("玩家離開商人互動範圍")

# ============================================================
# 16. 玩家進入互動範圍
#
# 保留原本的訊號函式名稱，
# 不需要重新連接 Inspector。
# ============================================================
func _on_body_entered(body: Node2D) -> void:
	if debug_log:
		print(
			"【商店NPC】有物體進入範圍：",
			body.name
		)

	if not body is Player:
		return

	if body != DataManager.player_node:
		return

	_nearby_player = body as Player
	player_in_range = true

	if _can_interact():
		show_prompt()

# ============================================================
# 17. 玩家離開互動範圍
# ============================================================
func _on_body_exited(body: Node2D) -> void:
	if not body is Player:
		return

	if body != _nearby_player:
		return

	player_in_range = false

	hide_prompt()

	_nearby_player = null

# ============================================================
# 18. 跨地圖及死亡重生轉場保護
#
# 死亡重生及正常跨地圖皆使用 SceneTransition。
# 因此在正式轉場開始時清理商店。
# ============================================================
func _on_transition_started(_scene_path: String) -> void:
	_hide_interact_prompt()
	_close_current_shop("場景開始切換")

# ============================================================
# 19. NPC 離開場景樹
#
# ShopUI 掛載於全域 Root，
# 不會必然隨地圖一起卸載。
#
# NPC 銷毀時主動清理，
# 防止商店殘留在下一張地圖。
# ============================================================
func _exit_tree() -> void:
	if SceneTransition.transition_started.is_connected(
		_on_transition_started
	):
		SceneTransition.transition_started.disconnect(
			_on_transition_started
		)

	if Dialogic.timeline_ended.is_connected(
		_on_quest_dialogue_ended
	):
		Dialogic.timeline_ended.disconnect(
			_on_quest_dialogue_ended
		)

	if tween and tween.is_valid():
		tween.kill()

	_close_current_shop("商人 NPC 已離開場景")

	current_shop_instance = null
	_shop_instance_id = 0
	player_in_range = false
	_nearby_player = null
	_quest_player = null
	_is_playing_quest_dialogue = false

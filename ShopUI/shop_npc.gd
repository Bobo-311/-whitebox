extends Area2D # 繼承 Area2D 商人 NPC

@export var shop_ui_scene: PackedScene # 🌟 屬性面板掛載商店 UI 場景 (改用 PackedScene)
@export var talk_timeline: String = "" # 🌟 任務完成前，點商店裡的 Talk 要播的劇本

@export_group("📦 貨物任務階段設定")
@export var quest_condition: String = "A014D"          # 🌟 觸發交貨的條件 (填撿箱子劇本 "A014D" 或暗號名稱 "got_cargo")
@export var quest_turn_in_timeline: String = "A014E"   # 🌟 拿到箱子後，對商人按 E 直接觸發的交貨劇本！
@export var after_quest_talk_timeline: String = "A015" # 🌟 交完貨之後，點商店裡的 Talk 改播的劇本 (若在 A014E 已連播 A015 可留空或填日常對話)

@onready var interact_prompt: Sprite2D = $InteractPrompt

var player_in_range: bool = false # 記錄玩家是否在範圍內
var tween: Tween # 動畫控制器
var prompt_original_y: float # 記錄 E 鍵初始高度
var current_shop_instance: Node = null # 記錄目前開著的商店，防重複開啟
var _is_playing_quest_dialogue: bool = false # 記錄是否正在播交任務劇情

func _ready(): # 初始化
	interact_prompt.hide() # 隱藏 E 鍵
	prompt_original_y = interact_prompt.position.y # 記住初始高度

func _process(_delta): # 每一幀檢查
	# 🌟 防呆 1：如果玩家正在看劇情 (is_in_dialogue) 或正在逛商店 (is_shopping)，隱藏 E 鍵並禁止重複開啟！
	if DataManager.player_node and (DataManager.player_node.is_in_dialogue or DataManager.player_node.is_shopping):
		if interact_prompt.visible:
			interact_prompt.hide()
		return
	elif player_in_range and not interact_prompt.visible and current_shop_instance == null:
		show_prompt()

	if player_in_range and Input.is_action_just_pressed("interact"): # 按下 E 鍵時
		# 防呆 2：確認玩家現在是不是正在看書或已在對話中？如果是，直接中斷！
		if DataManager.player_node and (DataManager.player_node.is_reading_book or DataManager.player_node.is_in_dialogue):
			return
		if Dialogic.current_timeline != null:
			return
			
		# 🌟 關鍵判定：如果玩家已經拿到箱子 (完成 A014D 或 got_cargo)，且還沒交過貨 (還沒播過 A014E)
		# ➡️ 按 E 直接進入交貨劇情，不開商店選單！
		var has_cargo = (quest_condition != "" and DataManager.is_cutscene_completed(quest_condition)) or DataManager.is_cutscene_completed("got_cargo")
		var has_turned_in = (quest_turn_in_timeline == "") or DataManager.is_cutscene_completed(quest_turn_in_timeline)
		
		if has_cargo and not has_turned_in:
			_start_quest_turn_in()
			return
			
		# 🌟 平時狀態 (還沒拿到箱子，或是已經交完貨了)：正常打開商店 UI！
		if current_shop_instance == null and shop_ui_scene:
			interact_prompt.hide()
			current_shop_instance = shop_ui_scene.instantiate()
			
			# 把商人的劇本名稱傳給商店 UI 的 Talk 按鈕！(如果已經交完貨，就傳入任務後的劇本)
			if "talk_timeline" in current_shop_instance:
				if has_turned_in and after_quest_talk_timeline != "":
					current_shop_instance.talk_timeline = after_quest_talk_timeline
				else:
					current_shop_instance.talk_timeline = talk_timeline
			
			# 必須先將 UI 實體加入場景樹，UI 內的 @onready 才會開始抓取節點！
			get_tree().root.add_child(current_shop_instance)
			
			# 確認加入場景後，再呼叫初始化選單
			if current_shop_instance.has_method("switch_to_main_menu"):
				current_shop_instance.switch_to_main_menu()

# 🌟 直接啟動交還貨物的劇情 (A014E)
func _start_quest_turn_in() -> void:
	interact_prompt.hide()
	_is_playing_quest_dialogue = true
	DataManager.mark_cutscene_completed(quest_turn_in_timeline)
	
	var player = DataManager.player_node
	if player:
		player.is_in_dialogue = true
		if "velocity" in player:
			player.velocity = Vector2.ZERO
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		if player.animated_sprite_2d:
			player.animated_sprite_2d.play("idle_down")
			
	if not Dialogic.timeline_ended.is_connected(_on_quest_dialogue_ended):
		Dialogic.timeline_ended.connect(_on_quest_dialogue_ended)
		
	Dialogic.start(quest_turn_in_timeline)
	Dialogic.timeline_started.emit()

# 🔓 交貨劇情結束時，自動解鎖玩家
func _on_quest_dialogue_ended() -> void:
	if not _is_playing_quest_dialogue: return
	_is_playing_quest_dialogue = false
	
	if Dialogic.timeline_ended.is_connected(_on_quest_dialogue_ended):
		Dialogic.timeline_ended.disconnect(_on_quest_dialogue_ended)
		
	var player = DataManager.player_node
	if is_instance_valid(player):
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
			
	if player_in_range:
		show_prompt()

func show_prompt(): # 處理 E 鍵顯示與浮動動畫
	interact_prompt.show() 
	if tween: tween.kill() 
	tween = create_tween().set_loops() 
	tween.tween_property(interact_prompt, "position:y", prompt_original_y - 15, 0.5).set_trans(Tween.TRANS_SINE) 
	tween.tween_property(interact_prompt, "position:y", prompt_original_y, 0.5).set_trans(Tween.TRANS_SINE) 

func hide_prompt(): # 處理 E 鍵隱藏與重置
	interact_prompt.hide() 
	if tween: tween.kill() 
	interact_prompt.position.y = prompt_original_y 
	
	# 🌟 玩家離開了，如果商店還開著，強制銷毀！
	if current_shop_instance != null:
		if DataManager.player_node:
			DataManager.player_node.is_shopping = false
		current_shop_instance.queue_free()
		current_shop_instance = null

func _on_body_entered(body):
	print("【商店NPC】有物體進入範圍：", body.name)
	if body is Player: # 完美防呆
		player_in_range = true 
		if not body.is_in_dialogue:
			show_prompt() 

func _on_body_exited(body): 
	if body is Player: 
		player_in_range = false 
		hide_prompt()

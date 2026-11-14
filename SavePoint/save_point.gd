extends Area2D # 繼承 Area2D savepoint

@export var save_menu_scene: PackedScene # 屬性面板掛載 UI 選單
@export var first_time_timeline: String = "first_easel" # 🌟 新增：第一次碰到畫架時觸發的劇本名稱 (填你的顏料劇本名！)

@onready var interact_prompt = $InteractPrompt # 抓取 E 鍵圖片節點

var player_in_range: bool = false # 記錄玩家是否在範圍內
var tween: Tween # 動畫控制器
var prompt_original_y: float # 記錄 E 鍵初始高度
var current_menu_instance: Node = null # 🌟 新增：記錄目前開啟的選單，防止重複生成
var _is_playing_first_cutscene: bool = false # 🌟 新增：記錄是否正在播放初見顏料劇情

func _ready(): # 初始化
	interact_prompt.hide() # 隱藏 E 鍵
	prompt_original_y = interact_prompt.position.y # 記住初始高度

func _process(_delta): # 每一幀檢查
	# 🌟 優化 1：如果玩家正在看書、看劇情或逛商店，自動隱藏 E 鍵提示並禁止觸發！
	if DataManager.player_node and (DataManager.player_node.is_reading_book or DataManager.player_node.is_in_dialogue or DataManager.player_node.is_shopping):
		if interact_prompt.visible:
			interact_prompt.hide()
		return
	elif player_in_range and not interact_prompt.visible and current_menu_instance == null:
		show_prompt()

	if player_in_range and Input.is_action_just_pressed("interact"): # 按下 E 鍵時
		# 🌟 終極防護：確認現在沒有開著存檔選單，也沒有正在跑 Dialogic 對話
		if current_menu_instance != null or Dialogic.current_timeline != null:
			return
			
		# 🌟 寫入存檔座標與當前地圖路徑
		if DataManager and DataManager.player_node:
			DataManager.last_save_position = DataManager.player_node.global_position
			DataManager.save_map_path = get_tree().current_scene.scene_file_path
			
		# 🌟 優化 2：檢查是否為「全遊戲第一次摸畫架」！
		# 如果是第一次，先觸發撿到【藍色顏料】的劇情，不開存檔選單！
		if first_time_timeline != "" and not DataManager.is_cutscene_completed(first_time_timeline):
			_trigger_first_time_cutscene()
			return
			
		# 🌟 優化 3：每次摸畫架時，自動補滿「藍色顏料 (元素瓶)」與從倉庫補充快捷欄道具！
		if DataManager.has_method("replenish_quick_slots"):
			DataManager.replenish_quick_slots()
			
		# 🌟 打開存檔點選單，並強迫玩家進入罰站狀態
		if DataManager.player_node:
			DataManager.player_node.is_reading_book = true
			if "velocity" in DataManager.player_node:
				DataManager.player_node.velocity = Vector2.ZERO
				
		if save_menu_scene:
			interact_prompt.hide()
			current_menu_instance = save_menu_scene.instantiate()
			get_tree().root.add_child(current_menu_instance)
			# 當存檔選單關閉被銷毀時，自動清空記錄
			current_menu_instance.tree_exited.connect(func(): current_menu_instance = null)

# 🎬 第一次觸碰畫架：播放獲得【藍色顏料】劇情
func _trigger_first_time_cutscene() -> void:
	interact_prompt.hide()
	_is_playing_first_cutscene = true
	DataManager.mark_cutscene_completed(first_time_timeline)
	
	# 解鎖藍色顏料並自動裝進快捷欄補滿 3 次！
	if DataManager.has_method("unlock_auto_refill_item"):
		DataManager.unlock_auto_refill_item("blue_paint")
		
	var player = DataManager.player_node
	if player:
		player.is_in_dialogue = true
		if "velocity" in player:
			player.velocity = Vector2.ZERO
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		if player.animated_sprite_2d:
			player.animated_sprite_2d.play("idle_down")
			
	if not Dialogic.timeline_ended.is_connected(_on_first_cutscene_ended):
		Dialogic.timeline_ended.connect(_on_first_cutscene_ended)
		
	Dialogic.start(first_time_timeline)
	Dialogic.timeline_started.emit()

# 🔓 初見畫架劇情結束後，恢復玩家行動
func _on_first_cutscene_ended() -> void:
	if not _is_playing_first_cutscene:
		return
	_is_playing_first_cutscene = false
	
	if Dialogic.timeline_ended.is_connected(_on_first_cutscene_ended):
		Dialogic.timeline_ended.disconnect(_on_first_cutscene_ended)
		
	var player = DataManager.player_node
	if is_instance_valid(player):
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
			
	if player_in_range:
		show_prompt()

func show_prompt(): # 自訂函數：處理 E 鍵顯示與浮動動畫
	interact_prompt.show()
	if tween: tween.kill()
	tween = create_tween().set_loops()
	tween.tween_property(interact_prompt, "position:y", prompt_original_y - 15, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(interact_prompt, "position:y", prompt_original_y, 0.5).set_trans(Tween.TRANS_SINE)

func hide_prompt(): # 自訂函數：處理 E 鍵隱藏與重置
	interact_prompt.hide()
	if tween: tween.kill()
	interact_prompt.position.y = prompt_original_y

func _on_body_entered(body): # 當有實體踏入存檔點感應區時觸發
	if body is Player:
		player_in_range = true
		if not body.is_in_dialogue and not body.is_reading_book:
			show_prompt()

func _on_body_exited(body): # 當有實體離開存檔點感應區時觸發
	if body is Player:
		player_in_range = false
		hide_prompt()

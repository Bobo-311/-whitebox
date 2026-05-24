extends Area2D # 繼承 Area2D savepoint

@export var save_menu_scene: PackedScene # 屬性面板掛載 UI 選單

@onready var interact_prompt = $InteractPrompt # 抓取 E 鍵圖片節點

var player_in_range: bool = false # 記錄玩家是否在範圍內
var tween: Tween # 動畫控制器
var prompt_original_y: float # 記錄 E 鍵初始高度

func _ready(): # 初始化
	interact_prompt.hide() # 隱藏 E 鍵
	prompt_original_y = interact_prompt.position.y # 記住初始高度

func _process(_delta): # 每一幀檢查
	if player_in_range and Input.is_action_just_pressed("interact"): # 按下 E 鍵時
		
		# 🌟 寫入存檔座標
		if DataManager and DataManager.player_node:
			DataManager.last_save_position = DataManager.player_node.global_position
			
			# 🌟 新增：讓大腦記住現在這張地圖的檔案路徑！
			DataManager.save_map_path = get_tree().current_scene.scene_file_path
			
		# 🌟 只負責叫出 UI 和暫停遊戲，不處理補血補體力！
		if save_menu_scene:
			var menu = save_menu_scene.instantiate()
			get_tree().root.add_child(menu)
			get_tree().paused = true

func show_prompt(): # 自訂函數：處理 E 鍵顯示與浮動動畫
	interact_prompt.show() # 將 E 鍵圖片顯示出來
	if tween: tween.kill() # 如果上次的動畫還沒播完，先強行停止，避免畫面抖動
	tween = create_tween().set_loops() # 建立一個新的無限循環動畫控制器
	tween.tween_property(interact_prompt, "position:y", prompt_original_y - 15, 0.5).set_trans(Tween.TRANS_SINE) # 花 0.5 秒平滑向上飄浮 15 像素
	tween.tween_property(interact_prompt, "position:y", prompt_original_y, 0.5).set_trans(Tween.TRANS_SINE) # 再花 0.5 秒平滑降回原始高度

func hide_prompt(): # 自訂函數：處理 E 鍵隱藏與重置
	interact_prompt.hide() # 將 E 鍵圖片隱藏起來
	if tween: tween.kill() # 玩家離開了，終止浮動動畫
	interact_prompt.position.y = prompt_original_y # 強制把 E 鍵位置拉回原點，避免下次顯示時座標跑掉

func _on_body_entered(body): # 當有實體踏入存檔點感應區時觸發
	if body is Player: # 完美防呆：檢查踏進來的是不是掛著 Player 腳本的玩家本人
		player_in_range = true # 將範圍標記設為真
		show_prompt() # 呼叫顯示 E 鍵的動畫函數

func _on_body_exited(body): # 當有實體離開存檔點感應區時觸發
	if body is Player: # 完美防呆：檢查離開的是不是玩家
		player_in_range = false # 將範圍標記設為假
		hide_prompt() # 呼叫隱藏 E 鍵的重置函數

extends Area2D # 繼承 Area2D 商人 NPC

@export var shop_ui_scene: PackedScene # 🌟 屬性面板掛載商店 UI 場景 (改用 PackedScene)

@onready var interact_prompt: Sprite2D = $InteractPrompt


var player_in_range: bool = false # 記錄玩家是否在範圍內
var tween: Tween # 動畫控制器
var prompt_original_y: float # 記錄 E 鍵初始高度
var current_shop_instance: Node = null # 記錄目前開著的商店，防重複開啟

func _ready(): # 初始化
	interact_prompt.hide() # 隱藏 E 鍵
	prompt_original_y = interact_prompt.position.y # 記住初始高度

func _process(_delta): # 每一幀檢查
	if player_in_range and Input.is_action_just_pressed("interact"): # 按下 E 鍵時
		
		# 防呆：確認玩家現在是不是正在看書？如果是，直接中斷裝瞎！
		if DataManager.player_node and DataManager.player_node.is_reading_book:
			return
			
		# 🌟 如果畫面還沒開著商店，且有掛載商店場景，就生成商店 UI
		if current_shop_instance == null and shop_ui_scene:
			current_shop_instance = shop_ui_scene.instantiate()
			
			# 🌟🌟🌟 [本次修改：正統生命週期] 🌟🌟🌟
			# 必須先將 UI 實體加入場景樹，UI 內的 @onready 才會開始抓取節點！
			get_tree().root.add_child(current_shop_instance)
			
			# 確認加入場景後，再呼叫初始化選單
			# (這裡不使用 get_tree().paused = true，讓世界保持運轉！)
			if current_shop_instance.has_method("switch_to_main_menu"):
				current_shop_instance.switch_to_main_menu()
			# 🌟🌟🌟 [修改結束] 🌟🌟🌟
				
			
			
			# (註：商店通常不需要暫停遊戲，所以這邊就不加 get_tree().paused = true 了)

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
		current_shop_instance.queue_free()
		current_shop_instance = null

func _on_body_entered(body):
	print("【商店NPC】有物體進入範圍：", body.name)
	if body is Player: # 完美防呆
		player_in_range = true 
		show_prompt() 

func _on_body_exited(body): 
	if body is Player: 
		player_in_range = false 
		hide_prompt()

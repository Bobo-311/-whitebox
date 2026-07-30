extends CanvasLayer # 繼承 CanvasLayer，處理 UI 顯示 savemenu_ui

# ==========================================
# 變數掛載區
# ==========================================
@export var sticker_ui_scene: PackedScene # 貼紙介面場景
@export var portal_menu_scene: PackedScene # 傳送介面場景
@onready var map_name_label: Label = $BackgroundDim/LocationFrame/Label
# 🌟 核心：記錄現在是不是在「存檔狀態下看筆記本」
var is_reading_from_savepoint: bool = false
# ==========================================
# 系統初始化
# ==========================================
func _ready() -> void:
	add_to_group("save_menu") # 🌟 貼上標籤，讓玩家等等按 TAB 時能把它叫回來
	# 打開存檔選單時，自動讀取大腦並更新地圖名稱
	if map_name_label and DataManager:
		map_name_label.text = DataManager.current_map_name
		
# ==========================================
# 🌟 完美整合的 TAB 鍵上一頁邏輯
# ==========================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("notebook"):
		
		# 情況 A：現在正在看筆記本 ➡️ 關掉筆記本，退回存檔畫架
		if is_reading_from_savepoint:
			var player = DataManager.player_node
			if player and player.notebook_ui:
				# 🌟 呼叫你的瞬間關閉 (或你原本設定的關閉方式)
				player.notebook_ui.toggle_notebook(true) 
			show() # 畫架重新顯示
			is_reading_from_savepoint = false
			get_viewport().set_input_as_handled() # 吃掉按鍵
			return
			
		# 情況 B：現在正在看存檔畫架 ➡️ 關掉畫架，解除暫停回遊戲
		if visible:
			get_tree().paused = false
			queue_free()
			get_viewport().set_input_as_handled() # 吃掉按鍵

# ==========================================
# 原有功能按鈕
# ==========================================
# --- 按下「存檔」：寫入數值並重載場景 ---
func _on_save_pressed() -> void:
	if DataManager and DataManager.player_node: 
		# 記錄最大血量與體力
		DataManager.saved_hp = DataManager.player_node.max_hp
		DataManager.saved_sp = DataManager.player_node.max_sp
		
		# 能量保底：低於 50% 補滿 50%，高於則保留現狀
		var half_energy = int(DataManager.player_node.max_energy * 0.5) 
		DataManager.saved_energy = max(DataManager.player_node.current_energy, half_energy) 
	
	get_tree().paused = false 
	queue_free() 
	get_tree().reload_current_scene() 


# --- 按下「貼紙」：叫出貼紙介面並隱藏自己 ---
func _on_sticker_pressed() -> void:
	if sticker_ui_scene:
		var sticker_menu = sticker_ui_scene.instantiate()
		get_tree().root.add_child(sticker_menu)
		hide() 

# ==========================================
# 🌟 本次新增：傳送與物品欄捷徑
# ==========================================
# --- 按下「傳送」：叫出黑洞傳送選單 ---
func _on_teleport_pressed() -> void:
	if portal_menu_scene:
		var portal_menu = portal_menu_scene.instantiate()
		get_tree().root.add_child(portal_menu)
		
		# 關閉畫架，把時間暫停的控制權無縫交接給傳送選單
		queue_free() 





func _on_notebook_pressed() -> void:
	get_tree().paused = false # 🌟 必須解除暫停，筆記本的彈出動畫才跑得出來！
	hide() # 🌟 不要 queue_free()，把它藏起來就好
	
	var player = DataManager.player_node
	if player and not player.is_reading_book:
		player.is_reading_book = true
		player.opened_from_savepoint = true # 標記：從畫架開的！
		
		player.velocity = Vector2.ZERO 
		player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
		
		if player.notebook_ui:
			player.notebook_ui.toggle_notebook(false) # 呼叫筆記本正常打開

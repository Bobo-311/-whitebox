extends CanvasLayer # 繼承 CanvasLayer，處理 UI 顯示 savemenu_ui

# ==========================================
# 變數掛載區
# ==========================================
@export var sticker_ui_scene: PackedScene # 貼紙介面場景
@export var portal_menu_scene: PackedScene # 傳送介面場景
@onready var map_name_label: Label = $BackgroundDim/LocationFrame/Label

# ==========================================
# 系統初始化
# ==========================================
func _ready() -> void:
	# 打開存檔選單時，自動讀取大腦並更新地圖名稱
	if map_name_label and DataManager:
		map_name_label.text = DataManager.current_map_name
		
# ==========================================
# 原有功能按鈕
# ==========================================
# --- 按下「存檔」：寫入數值並重載場景 ---
func _on_save_pressed() -> void:
	if DataManager and DataManager.player_node: 
		var player = DataManager.player_node
		
		# 1. 記錄最大血量與體力 (存檔點全滿)
		DataManager.saved_hp = player.max_hp
		DataManager.saved_sp = player.max_sp
		
		# 2. [🌟 墨水彈藥系統] 存檔時將墨水彈藥補滿 (3/3)
		player.current_ammo = player.max_ammo
		if player.player_hud and player.player_hud.has_method("update_ammo"):
			player.player_hud.update_ammo(player.current_ammo, player.max_ammo)
			
		print("💾【存檔成功】血量、體力與墨水彈藥已全數補滿！")
	
	get_tree().paused = false 
	queue_free() 
	get_tree().reload_current_scene() 

# --- 按下「出發」：關閉選單繼續遊戲 ---
func _on_go_pressed() -> void:
	get_tree().paused = false 
	queue_free() 

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

# --- 按下「物品欄」：解除暫停，瞬間切換到看書模式 ---
func _on_inventory_pressed() -> void:
	get_tree().paused = false # 1. 解除全域暫停
	
	var player = DataManager.player_node
	if player and not player.is_reading_book:
		player.is_reading_book = true
		
		# 🌟 核心暗號：標記這是從「存檔點捷徑」強制打開的
		player.opened_from_savepoint = true 
		
		player.velocity = Vector2.ZERO # 煞車防滑
		player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED # 鎖死動作
		
		# 2. 呼叫筆記本，傳入 true 執行「瞬間開啟」
		if player.notebook_ui:
			player.notebook_ui.toggle_notebook(true)
			
	# 3. 徹底關閉畫架選單
	queue_free()

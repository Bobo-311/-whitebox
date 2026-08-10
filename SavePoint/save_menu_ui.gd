extends CanvasLayer # 繼承 CanvasLayer，這樣 UI 才會獨立繪製在最上層，不會受攝影機移動影響

# ==========================================
# 📦 變數掛載區 (從外部拉進來的素材與節點)
# ==========================================
@export var sticker_ui_scene: PackedScene # 在右邊屬性面板掛載「貼紙介面」的場景檔案 (.tscn)
@export var portal_menu_scene: PackedScene # 在右邊屬性面板掛載「傳送介面」的場景檔案 (.tscn)

@onready var map_name_label: Label = $BackgroundDim/LocationFrame/Label # 抓取顯示「當前地圖名稱」的文字節點

# 🌟 狀態標記：記錄玩家現在是不是在「存檔畫架」的狀態下打開了筆記本？
var is_reading_from_savepoint: bool = false

# ==========================================
# 🚀 系統初始化 (UI 剛被叫出來的瞬間執行)
# ==========================================
func _ready() -> void:
	# 🌟 幫這個 UI 貼上一個名叫 "save_menu" 的群組標籤
	add_to_group("save_menu") 
	
	# 打開存檔選單時，自動問大腦 (DataManager) 現在在哪裡，並把地圖名字印在 UI 上
	if map_name_label and DataManager:
		map_name_label.text = DataManager.current_map_name
		
# ==========================================
# ⌨️ 玩家輸入偵測 (完美整合的 TAB 鍵上一頁邏輯)
# ==========================================
func _input(event: InputEvent) -> void:
	# 當玩家按下 TAB 鍵 (綁定名稱為 "notebook") 時
	if event.is_action_pressed("TAB") or event.is_action_pressed("ESC"):
		
		# 【情況 A】：現在是「存檔狀態下看筆記本」 ➡️ 關掉筆記本，退回存檔畫架
		if is_reading_from_savepoint:
			var player = DataManager.player_node
			if player and player.notebook_ui:
				player.notebook_ui.toggle_notebook(true) 
				
			show() # 把剛才藏起來的存檔畫架重新顯示出來！
			is_reading_from_savepoint = false # 狀態重置
			get_viewport().set_input_as_handled() # 吃掉輸入
			return 
			
		# 【情況 B】：現在是在看「存檔畫架」 ➡️ 關掉畫架，解除罰站，回到正常遊戲
		if visible:
			# 解除玩家的罰站狀態
			if DataManager and DataManager.player_node:
				DataManager.player_node.is_reading_book = false
			queue_free() # 把存檔畫架銷毀
			get_viewport().set_input_as_handled()

# 🌟🌟🌟 [本次新增：自動偵測「被打斷」的自毀系統] 🌟🌟🌟
func _process(_delta: float) -> void:
	if DataManager and DataManager.player_node:
		# 如果大腦發現玩家的罰站狀態被強制解除了 (代表被怪物攻擊了)
		if not DataManager.player_node.is_reading_book:
			queue_free() # 存檔畫面立刻自動銷毀，退回遊戲！
# 🌟🌟🌟 [新增結束] 🌟🌟🌟
# ==========================================
# 💾 按鈕功能實作區
# ==========================================

# --- 1️⃣ 按下「存檔」按鈕 ---
func _on_save_pressed() -> void:
	if DataManager and DataManager.player_node: 
		var player = DataManager.player_node
		
		# 1. 記錄最大血量與體力 (存檔點全滿)
		DataManager.saved_hp = player.max_hp
		DataManager.saved_sp = player.max_sp
		
		# 2. 能量(EP)保底機制 (防呆安全檢查)
		if "max_energy" in player and "current_energy" in player:
			var half_energy = int(player.max_energy * 0.5) 
			DataManager.saved_energy = max(player.current_energy, half_energy) 
		
		# 3. [🌟 墨水彈藥系統] 存檔時將墨水彈藥補滿 (3/3)
		player.current_ammo = player.max_ammo
		if player.player_hud and player.player_hud.has_method("update_ammo"):
			player.player_hud.update_ammo(player.current_ammo, player.max_ammo)
			
		# 4. [🌟 道具補給] 呼叫大腦，將快捷欄上的藥水/道具補滿，並扣除倉庫數量
		DataManager.replenish_quick_slots()
			
		print("💾【存檔成功】血量、體力、墨水彈藥與快捷欄道具已全數補給完成！")
	
	# 存檔完畢，解除時間暫停
	get_tree().paused = false 
	# 銷毀畫架 UI
	queue_free() 
	# 重新載入當前地圖 (畫面閃一下，營造存檔並刷新怪物的感覺)
	get_tree().reload_current_scene() 


# --- 2️⃣ 按下「貼紙」按鈕 ---
func _on_sticker_pressed() -> void:
	if sticker_ui_scene:
		var sticker_menu = sticker_ui_scene.instantiate()
		get_tree().root.add_child(sticker_menu)
		hide() 


# --- 3️⃣ 按下「傳送」按鈕 ---
func _on_teleport_pressed() -> void:
	if portal_menu_scene:
		var portal_menu = portal_menu_scene.instantiate()
		get_tree().root.add_child(portal_menu)
		queue_free() 


# --- 4️⃣ 按下「物品欄 (筆記本)」按鈕 ---
func _on_inventory_pressed() -> void:
	hide() 
	
	var player = DataManager.player_node
	# 🌟 直接要求執行，拿掉會造成衝突的 not player.is_reading_book 判斷
	if player:
		player.is_reading_book = true 
		player.opened_from_savepoint = true 
		
		player.velocity = Vector2.ZERO 
		player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
		
		if player.notebook_ui:
			player.notebook_ui.toggle_notebook(false)

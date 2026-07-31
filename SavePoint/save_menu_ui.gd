extends CanvasLayer # 繼承 CanvasLayer，這樣 UI 才會獨立繪製在最上層，不會受攝影機移動影響

# ==========================================
# 📦 變數掛載區 (從外部拉進來的素材與節點)
# ==========================================
@export var sticker_ui_scene: PackedScene # 在右邊屬性面板掛載「貼紙介面」的場景檔案 (.tscn)
@export var portal_menu_scene: PackedScene # 在右邊屬性面板掛載「傳送介面」的場景檔案 (.tscn)

@onready var map_name_label: Label = $BackgroundDim/LocationFrame/Label # 抓取顯示「當前地圖名稱」的文字節點

# 🌟 狀態標記：記錄玩家現在是不是在「存檔畫架」的狀態下打開了筆記本？
# 這個很重要，用來判斷玩家按 TAB 關掉筆記本時，是要回到遊戲，還是要退回存檔畫架。
var is_reading_from_savepoint: bool = false

# ==========================================
# 🚀 系統初始化 (UI 剛被叫出來的瞬間執行)
# ==========================================
func _ready() -> void:
	# 🌟 幫這個 UI 貼上一個名叫 "save_menu" 的群組標籤
	# 這樣當玩家在筆記本裡按 TAB 時，玩家腳本才能用 get_tree().get_nodes_in_group("save_menu") 把它找出來重新顯示！
	add_to_group("save_menu") 
	
	# 打開存檔選單時，自動問大腦 (DataManager) 現在在哪裡，並把地圖名字印在 UI 上
	if map_name_label and DataManager:
		map_name_label.text = DataManager.current_map_name
		
# ==========================================
# ⌨️ 玩家輸入偵測 (完美整合的 TAB 鍵上一頁邏輯)
# ==========================================
func _input(event: InputEvent) -> void:
	# 當玩家按下 TAB 鍵 (綁定名稱為 "notebook") 時
	if event.is_action_pressed("notebook"):
		
		# 【情況 A】：現在是「存檔狀態下看筆記本」 ➡️ 關掉筆記本，退回存檔畫架
		if is_reading_from_savepoint:
			var player = DataManager.player_node
			if player and player.notebook_ui:
				# 🌟 呼叫筆記本的無動畫/瞬間關閉函數，把筆記本收起來
				player.notebook_ui.toggle_notebook(true) 
				
			show() # 把剛才藏起來的存檔畫架重新顯示出來！
			is_reading_from_savepoint = false # 狀態重置，代表已經不在看筆記本了
			get_viewport().set_input_as_handled() # 🌟 吃掉這個按鍵輸入，避免觸發其他腳本的 TAB 鍵功能
			return # 直接中斷退出，不要往下執行
			
		# 【情況 B】：現在是在看「存檔畫架」 ➡️ 關掉畫架，解除時間暫停，回到正常遊戲
		if visible:
			get_tree().paused = false # 🌟 解除時間暫停，世界開始運轉
			queue_free() # 把存檔畫架這個 UI 徹底銷毀丟進垃圾桶
			get_viewport().set_input_as_handled() # 🌟 吃掉按鍵

# ==========================================
# 💾 按鈕功能實作區
# ==========================================

# --- 1️⃣ 按下「存檔」按鈕 ---
func _on_save_pressed() -> void:
	if DataManager and DataManager.player_node: 
		# 把玩家現在的「最大血量」跟「最大體力」寫進小抄裡 (存檔)，這樣重載場景時，血量就會是滿的！
		DataManager.saved_hp = DataManager.player_node.max_hp
		DataManager.saved_sp = DataManager.player_node.max_sp
		
		# 能量(EP)保底機制：不能無腦回滿。如果低於 50% 就補到 50%，高於 50% 就保留現狀
		var half_energy = int(DataManager.player_node.max_energy * 0.5) 
		DataManager.saved_energy = max(DataManager.player_node.current_energy, half_energy) 
		
		# 🌟🌟🌟 補給機制啟動：呼叫大腦，把身上藥水從 0/2 補滿回 2/2，並扣除倉庫數量！
		DataManager.replenish_quick_slots()
	
	# 存檔完畢，解除時間暫停
	get_tree().paused = false 
	# 銷毀畫架 UI
	queue_free() 
	# 重新載入當前地圖 (畫面閃一下，營造存檔並刷新怪物的感覺)
	get_tree().reload_current_scene() 


# --- 2️⃣ 按下「貼紙」按鈕 ---
func _on_sticker_pressed() -> void:
	# 防呆：確保右邊面板有把貼紙場景拉進來
	if sticker_ui_scene:
		# 實體化 (Instantiate) 貼紙介面
		var sticker_menu = sticker_ui_scene.instantiate()
		# 把它加到遊戲最頂層 (root) 畫面上
		get_tree().root.add_child(sticker_menu)
		# 🌟 把自己 (存檔畫架) 隱藏起來，假裝切換了畫面
		hide() 


# --- 3️⃣ 按下「傳送」按鈕 ---
func _on_teleport_pressed() -> void:
	if portal_menu_scene:
		var portal_menu = portal_menu_scene.instantiate()
		get_tree().root.add_child(portal_menu)
		
		# 🌟 這裡跟貼紙不一樣！因為傳送選單有自己獨立的關閉邏輯，
		# 所以我們直接把畫架銷毀 (queue_free)，把時間暫停的控制權無縫交接給傳送選單！
		queue_free() 


# --- 4️⃣ 按下「物品欄 (筆記本)」按鈕 ---
func _on_inventory_pressed() -> void:
	# 🌟 關鍵解法：必須先解除時間暫停，不然筆記本的「彈出動畫」會卡住不動！
	get_tree().paused = false 
	# 🌟 把畫架藏起來就好，絕對不能 queue_free()！因為等下玩家按 TAB 還要回到這裡！
	hide() 
	
	var player = DataManager.player_node
	# 確認有抓到玩家，且玩家現在沒有在看書
	if player and not player.is_reading_book:
		player.is_reading_book = true # 鎖死玩家的移動與攻擊
		player.opened_from_savepoint = true # 🌟 留下線索：告訴玩家腳本，我是從畫架打開的！
		
		# 強制讓玩家煞車，並把負責動作的狀態機關機
		player.velocity = Vector2.ZERO 
		player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
		
		if player.notebook_ui:
			# 呼叫筆記本，播放正常的打開動畫
			player.notebook_ui.toggle_notebook(false)

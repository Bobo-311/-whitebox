extends CanvasLayer

# ==========================================
# 節點抓取區 (取得場景樹上的 UI 元件)
# ==========================================
@onready var cursor = $Cursor # 指示目前選項的游標
# 🌟 [音效節點修改] 替換成你剛剛建立的三個音效節點
@onready var select_sound = $SelectSound
@onready var check_sound = $CheckSound   # 確認進入、購買成功時播放 (check)
@onready var back_sound = $BackSound     # 退出選單、關閉商店時播放 (back)
@onready var purchase_success_sound = $"Purchase success sound"
@onready var purchase_failure_sound = $"Purchase failure sound"

@onready var main_menu_layout = $BottomFrame/MainMenu_Layout # 主選單容器 (Buy, Sell, Talk, Exit)
@onready var buy_menu_layout = $BottomFrame/BuyMenu_Layout # 購買選單容器 (商品清單)

@onready var main_vbox = $BottomFrame/MainMenu_Layout/RightMenuArea/VBoxContainer # 主選單的垂直排列容器
@onready var buy_vbox = $BottomFrame/BuyMenu_Layout/LeftItemList/VBoxContainer # 購買選單的垂直排列容器

@onready var info_box = $InfoBox # 右上角的商品資訊黑框
@onready var desc_label = $InfoBox/MarginContainer/DescLabel # 商品資訊黑框裡的文字節點

# [新增] 抓取購買頁面右邊的對話文字節點，用來把 "What would you like to buy?" 替換成餘額不足的警告
@onready var buy_prompt_label = $BottomFrame/BuyMenu_Layout/RightInfoArea/Label

# ==========================================
# 變數設定區
# ==========================================
var menu_items: Array = [] # 用來存放目前選單裡所有 Label 的陣列
var current_index: int = 0 # 記錄游標目前停留在第幾個選項 (從 0 開始)
var cursor_offset: Vector2 = Vector2(-55, -20) # 游標相對於選項文字的微調位置
var current_state: int = 0 # 記錄目前的選單狀態：0 代表在主選單，1 代表在購買清單

# ==========================================
# 🛒 商店商品資料庫
# ==========================================
var item_database = {
	"50G - 咕咕嘎嘎药水": {
		"desc": "不知道是什么，但听起来很好吃。\n恢复 20 HP",
		"price": 50,
		"item_id": "potion_gugu" 
	},
	"30G - 奇迹苹果": {
		"desc": "又脆又甜的苹果。\n恢复 10 HP",
		"price": 30,
		"item_id": "miracle_apple"
	},
	"150G - 烤带骨牛排": {
		"desc": "香气四溢的带骨肉排。\n恢复 50 HP",
		"price": 150,
		"item_id": "steak_bone"
	},
	"20G - 蓝色提神水": {
		"desc": "喝起来像气泡水。\n恢复 5 HP",
		"price": 20,
		"item_id": "energy_drink"
	},
	"25G - 西巴鲁玛": {
		"desc": "神秘的道具。\n速度 +10",
		"price": 25,
		"item_id": "item_xibaluma"
	}
}

# ==========================================
# 系統初始化
# ==========================================
func _ready():
	# 遊戲一開始執行時，強制先切換到主選單狀態
	switch_to_main_menu()

# 切換到主選單的邏輯
func switch_to_main_menu():
	if DataManager.player_node:
		DataManager.player_node.is_shopping = true
	current_state = 0 # 狀態設為 0 (主選單)
	current_index = 0 # 游標歸零回到第一個選項
	main_menu_layout.show() # 顯示主選單的 UI
	buy_menu_layout.hide() # 隱藏購買選單的 UI
	info_box.hide() # 隱藏右上角的商品資訊框
	refresh_menu_items(main_vbox) # 重新抓取主選單裡的選項

# 切換到購買選單的邏輯
func switch_to_buy_menu():
	current_state = 1 # 狀態設為 1 (購買清單)
	current_index = 0 # 游標歸零回到第一個商品
	main_menu_layout.hide() # 隱藏主選單的 UI
	buy_menu_layout.show() # 顯示購買選單的 UI
	info_box.show() # 顯示右上角的商品資訊框
	refresh_menu_items(buy_vbox) # 重新抓取購買清單裡的選項

# 重新整理清單內容的函數 (切換選單時呼叫)
func refresh_menu_items(container):
	menu_items.clear() # 先清空舊的選項陣列
	
	# 尋找傳入的容器 (container) 裡面所有的子節點
	for child in container.get_children():
		if child is Label:
			menu_items.append(child) # 如果是 Label，就把他加進選項陣列裡
			
	# 等待引擎重新計算 UI 排版兩次，確保抓到的座標是準確的
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 排版完成後，更新游標的位置
	update_cursor_position()

# ==========================================
# 玩家按鍵輸入處理
# ==========================================
func _input(event):
	# 如果按下「往下」鍵
	if event.is_action_pressed("ui_down"):
		# 游標索引值 +1。使用 % 取餘數可以讓游標到底部時，自動循環回到最上面
		current_index = (current_index + 1) % menu_items.size()
		update_cursor_position()
		select_sound.play()
		
	# 如果按下「往上」鍵
	elif event.is_action_pressed("ui_up"):
		# 游標索引值 -1。加上陣列大小再取餘數，可以讓游標在最上方時，自動循環到底部
		current_index = (current_index - 1 + menu_items.size()) % menu_items.size()
		update_cursor_position()
		select_sound.play()

	# 如果按下「確認」鍵 (Enter/空白鍵)
	elif event.is_action_pressed("ui_accept"):
		handle_selection() # 執行確認邏輯

# ==========================================
# 確認鍵的判斷邏輯
# ==========================================
func handle_selection():
	# 如果目前在主選單
	if current_state == 0:
		if current_index == 0: # 如果游標在第一個選項 (Buy)
			check_sound.play()
			switch_to_buy_menu() # 切換到購買選單
		elif current_index == 3: # 如果游標在第四個選項 (Exit)
			back_sound.play()
			# 🌟 1. 商店關閉了，解除主角的購物模式 (恢復自由)
			if DataManager.player_node:
				DataManager.player_node.is_shopping = false
				
			# 🌟 2. 徹底銷毀商店 UI
			queue_free()
			
	# 如果目前在購買選單
	elif current_state == 1:
		# 抓取目前游標指到的 Label 節點，並讀取它的文字
		var selected_label = menu_items[current_index]
		var item_name = selected_label.text
		
		# 判斷點擊的是否為退出鍵
		if item_name == "Exit":
			back_sound.play()
			switch_to_main_menu() # 退回主選單
		else:
			# [新增] 核心扣錢邏輯
			# 先檢查點擊的字串有沒有在商品資料庫裡
			if item_database.has(item_name):
				var item_info = item_database[item_name]
				var price = item_info["price"] # 從資料庫讀取這個商品的價格
				
				# 去 DataManager 檢查玩家目前的總金額是否大於等於商品價格
				if DataManager.total_gold >= price:
					purchase_success_sound.play() 
					DataManager.total_gold -= price # 扣錢
					# 🌟 發貨檢查：只要商品字典裡有 "item_id" 這個鑰匙，就把東西送進大腦
					if item_info.has("item_id"):
						DataManager.add_item_to_reserve(item_info["item_id"], 1)
						
					print("【商店】購買成功！扣除 ", price, " G，剩餘 ", DataManager.total_gold, " G")
					
				else:
					back_sound.play()
					# 金額不足的情況
					print("【商店】錢不夠！商品要 ", price, " G，但你只有 ", DataManager.total_gold, " G")
					
					# 把右邊的對話框文字改成餘額不足的提示
					buy_prompt_label.text = "You don't have enough gold!"
					
					# 暫停腳本執行 1 秒鐘
					await get_tree().create_timer(1.0).timeout
					
					# 1 秒後把對話框文字恢復原狀
					buy_prompt_label.text = "What would you like to buy?"

# ==========================================
# 更新游標位置與說明文字
# ==========================================
func update_cursor_position():
	if menu_items.size() > 0:
		var target_node = menu_items[current_index] # 抓出目前的目標 Label
		var center_y = target_node.size.y / 2.0 # 計算 Label 高度的正中心
		
		# 將游標的絕對座標對齊 Label 的左上角，再往下推到正中心，最後加上微調值 (cursor_offset)
		cursor.global_position = target_node.global_position + Vector2(cursor_offset.x, center_y + cursor_offset.y)
		
		# 如果目前在購買選單，要跟著游標動態更新右上角的說明文字
		if current_state == 1:
			var item_name = target_node.text
			
			if item_database.has(item_name):
				# 讀取資料庫裡的 desc 並顯示在 UI 上
				desc_label.text = item_database[item_name]["desc"]
			elif item_name == "Exit":
				desc_label.text = "" # 游標指到 Exit 時清空說明

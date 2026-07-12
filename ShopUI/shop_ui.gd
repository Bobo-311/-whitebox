extends Control


@onready var cursor = $Cursor               
@onready var move_sound = $MoveSound        
@onready var confirm_sound = $ConfirmSound  

@onready var main_menu_layout = $BottomFrame/MainMenu_Layout 
@onready var buy_menu_layout = $BottomFrame/BuyMenu_Layout   


@onready var main_vbox = $BottomFrame/MainMenu_Layout/RightMenuArea/VBoxContainer
@onready var buy_vbox = $BottomFrame/BuyMenu_Layout/LeftItemList/VBoxContainer


# ==========================================
# 第二區：大腦記憶區 (用變數記住現在的狀況)
# ==========================================
var menu_items: Array = []       # 這是一張「點名表」。裡面會暫時存放目前畫面上的選項文字。
var current_index: int = 0       # 記錄玩家現在指著點名表上的第幾個人 (0 是第一個)。
var cursor_offset: Vector2 = Vector2(-40, 15) # 游標要跟文字保持的距離 (往左 40，往下 5)

# 🌟 核心靈魂：記錄目前在哪個畫面 (狀態機)
# 0 = 我們現在在「主選單」 (可以看到 Buy, Sell, Talk, Exit)
# 1 = 我們現在在「購買頁面」 (可以看到 Apple, Potion, Exit)
var current_state: int = 0 


# ==========================================
# 第三區：遊戲剛啟動的第一個動作
# ==========================================
func _ready():
	# 遊戲一打開，強制執行「切換到主選單」的動作，確保畫面乾淨
	switch_to_main_menu()


# ==========================================
# 第四區：切換畫面的魔法 (障眼法控制器)
# ==========================================

# 魔法 A：切換到「主選單」
func switch_to_main_menu():
	current_state = 0             # 1. 把大腦狀態設定為 0 (主選單)
	current_index = 0             # 2. 把游標號碼歸零 (強制作回到第一個選項)
	main_menu_layout.show()       # 3. 顯示主選單的佈景
	buy_menu_layout.hide()        # 4. 隱藏購買選單的佈景
	# 5. 呼叫底下的「重整名單」工具，並把主選單的 VBox 丟給它去抓字
	refresh_menu_items(main_vbox) 

# 魔法 B：切換到「購買選單」
func switch_to_buy_menu():
	current_state = 1             # 1. 把大腦狀態設定為 1 (購買選單)
	current_index = 0             # 2. 把游標號碼歸零 (強制回到第一個商品)
	main_menu_layout.hide()       # 3. 隱藏主選單的佈景
	buy_menu_layout.show()        # 4. 顯示購買選單的佈景
	# 5. 呼叫底下的「重整名單」工具，並把購買選單的 VBox 丟給它去抓字
	refresh_menu_items(buy_vbox)  

# 工具：重新整理點名表 (超級實用！)
# 只要你丟一個容器 (container) 給它，它就會把裡面的文字全部抄進點名表裡
func refresh_menu_items(container):
	menu_items.clear()            # 1. 先把舊的點名表用橡皮擦擦乾淨
	
	# 2. 把容器裡面的小孩 (文字節點) 一個一個叫出來
	for child in container.get_children():
		if child is Label:
			menu_items.append(child) # 3. 如果是文字，就抄進點名表裡
	
	# 🌟 防彈魔法：等兩次！
	# 確保無論 UI 有多複雜，Godot 絕對已經把所有框框的長寬高都算得清清楚楚了。
	await get_tree().process_frame
	await get_tree().process_frame
	
	update_cursor_position()


# ==========================================
# 第五區：監聽玩家按鍵
# ==========================================
func _input(event):
	# 當玩家按下「下」
	if event.is_action_pressed("ui_down"):
		# 這裡用了一個數學小技巧 `%` (取餘數) 來做無限循環選單！
		# 假設名單有 4 個選項 (size = 4)：
		# 如果 current_index 從 3 再加 1 變成 4，(4 % 4) 會變成 0，游標就瞬間回到最上面了！
		current_index = (current_index + 1) % menu_items.size()
		
		update_cursor_position() # 算好號碼後，叫游標移動過去
		move_sound.play()        # 播嗶嗶聲
		
	# 當玩家按下「上」
	elif event.is_action_pressed("ui_up"):
		# 往上的邏輯也是一樣，為了避免減 1 變成負數，我們先加上總人數再取餘數，就能完美從 0 跳到最下面
		current_index = (current_index - 1 + menu_items.size()) % menu_items.size()
		
		update_cursor_position() # 算好號碼後，叫游標移動過去
		move_sound.play()        # 播嗶嗶聲

	# 當玩家按下「確認鍵 (Enter/空白/Z/A鍵)」
	elif event.is_action_pressed("ui_accept"):
		confirm_sound.play()     # 先播一聲確認的咚咚聲
		handle_selection()       # 把「接下來要幹嘛」交給底下的專門函式去處理


# ==========================================
# 第六區：判斷按下確認後要發生什麼事
# ==========================================
func handle_selection():
	# 情況 A：如果我們現在在「主選單」
	if current_state == 0: 
		if current_index == 0:     # 如果游標指著第 0 個 (Buy)
			switch_to_buy_menu()   # 施放切換到購買選單的魔法！
			
		elif current_index == 3:   # 如果游標指著第 3 個 (Exit)
			hide()                 # 關閉整個商店介面
			
	# 情況 B：如果我們現在在「購買選單」
	elif current_state == 1: 
		# 我們先去點名表把現在選到的那個文字節點抓出來看
		var selected_label = menu_items[current_index]
		
		# 檢查這個文字節點的內容是不是寫著 "Exit"
		if selected_label.text == "Exit":
			switch_to_main_menu()  # 施放切換回主選單的魔法！
		else:
			# 如果不是 Exit，就代表玩家買了商品
			print("玩家買了: ", selected_label.text)


# ==========================================
# 第七區：游標的瞬間移動核心
# ==========================================
func update_cursor_position():
	# 為了安全起見，先確認點名表裡面真的有東西 (大於 0)
	if menu_items.size() > 0:
		# 抓出當前號碼牌對應的文字節點
		var target_node = menu_items[current_index]
		
		# 游標的絕對座標 = 目標文字的絕對座標 + 我們設定好的微調距離
		cursor.global_position = target_node.global_position + cursor_offset

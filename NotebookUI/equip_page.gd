extends Control

# === 1. 抓取舞台上的兩個演員 ===
@onready var center_slots = $MarginContainer/MainLayout/Center_Stage/Center_Slots
@onready var item_list_ui = $MarginContainer/MainLayout/Center_Stage/ItemList_UI

# 抓取清單的容器 (確保等下按鈕生在這裡面)
@onready var list_content = $MarginContainer/MainLayout/Center_Stage/ItemList_UI/ListContent
# ==========================================
# 玩家的背包資料 (假資料，用來測試)
# ==========================================
var my_inventory = [
	{
		"item_name": "紅色藥水",
		"description": "經典的補血道具，據說喝起來有草莓糖漿的味道。",
		"icon": load("res://FreePixelSurvivalItemsPack/Items/25.png/") # 等下我們會換成真的圖片
	},
	{
		"item_name": "阿巴阿巴貼紙", # 借用你畫面上可愛的文案 XD
		"description": "一張神秘的貼紙，散發著奇妙的能量。",
		"icon": null 
	}
]
# 用來記錄玩家現在點的是第幾個裝備格 (-1 代表還沒選)
var current_slot_index = -1

func _ready():
	# 遊戲一打開這頁時，預設畫面是「顯示裝備格、隱藏清單」
	close_item_list()

# === 4. 監聽玩家的鍵盤輸入 (只攔截 TAB 鍵) ===
func _input(event):
	# 確保只有在「道具清單打開」的時候，才進行按鍵攔截
	if item_list_ui.visible:
		
		# 判斷玩家是否按下了 TAB 鍵 (你的輸入動作名稱 "notebook")
		if event.is_action_pressed("notebook"):
			
			# 1. 執行退回裝備格的動作
			close_item_list() 
			
			# 2. 【關鍵防呆機制】把這個 TAB 鍵的訊號「吃掉」！
			# 這樣外層的玩家/主系統就不會收到 TAB，也不會因為按了 TAB 而把整本筆記本收起來。
			get_viewport().set_input_as_handled()

# ==========================================
# 生成道具清單的功能
# ==========================================
func refresh_inventory_ui():
	# 1. 先把舊的按鈕清空 (避免重複生成)
	for child in list_content.get_children():
		child.queue_free()
		
	# 2. 拿出背包裡的每一個道具，幫它做一個專屬按鈕
	for item in my_inventory:
		var btn = Button.new()          # 創造一個新按鈕
		btn.text = item["item_name"]    # 把按鈕的文字設定成道具名字
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT # 讓文字靠左對齊
		
		# 【本次新增：圖片處理邏輯】
		if item["icon"] != null:
			btn.icon = item["icon"]       # 把載入的圖片塞給按鈕
			btn.expand_icon = true        # 允許圖片縮放 (非常重要，不然原圖太大會跑版)
		# (選做) 設定按鈕的高度，讓它看起來大一點
		btn.custom_minimum_size = Vector2(0, 80) 
		
		# 3. 把做好的按鈕塞進清單容器裡
		list_content.add_child(btn)	









# === 2. 核心功能：切換顯示狀態 ===

# 打開清單 (點擊裝備格時觸發)
func open_item_list(slot_number):
	current_slot_index = slot_number
	refresh_inventory_ui() #打開清單前，先把按鈕生好！
	center_slots.hide()  # 把格子藏起來
	item_list_ui.show()  # 把清單叫出來

# 關閉清單 (退回裝備格時觸發)
func close_item_list():
	item_list_ui.hide()  # 把清單藏起來
	center_slots.show()  # 讓格子重新出現

# === 3. 裝備格的點擊連線 ===
func _on_slot_1_pressed() -> void:
	open_item_list(1)  # 告訴程式：打開清單，並記住現在是換第 1 格！

func _on_slot_2_pressed() -> void:
	open_item_list(2)  # 告訴程式：打開清單，並記住現在是換第 2 格！

func _on_slot_3_pressed() -> void:
	open_item_list(3)  # 告訴程式：打開清單，並記住現在是換第 3 格！

func _on_slot_4_pressed() -> void:
	open_item_list(4)  # 告訴程式：打開清單，並記住現在是換第 4 格！

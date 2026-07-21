extends Control

# === 1. 抓取舞台上的兩個演員 ===
@onready var center_slots = $MarginContainer/MainLayout/Center_Stage/Center_Slots
@onready var item_list_ui = $MarginContainer/MainLayout/Center_Stage/ItemList_UI

# 抓取清單的容器 (確保等下按鈕生在這裡面)
@onready var list_content = $MarginContainer/MainLayout/Center_Stage/ItemList_UI/ListContent

# === 抓取右側資訊欄的節點 ===
@onready var info_name_label = $MarginContainer/MainLayout/Right_Info/ItemName
@onready var info_desc_label = $MarginContainer/MainLayout/Right_Info/ItemDesc

# ==========================================
# 裝備狀態帳本 (記錄 1~4 格目前裝了什麼道具)
# ==========================================
var equipped_items = {
	1: null,
	2: null,
	3: null,
	4: null
}


# 用來記錄玩家現在點的是第幾個裝備格 (-1 代表還沒選)
var current_slot_index = -1

func _ready():
	# 遊戲一打開這頁時，預設畫面是「顯示裝備格、隱藏清單」
	close_item_list()
	
	setup_slot_effects()
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
# 生成道具清單的功能 (純圖示網格版)
# ==========================================
func refresh_inventory_ui():
	
	# 會抓出網格裡面現在有幾個按鈕。
	# 因為我們每次打開筆記本，程式都會重新生一次按鈕，如果不先清空，按鈕就會無性生殖越疊越多。
	for child in list_content.get_children():
		child.queue_free() # queue_free() 的意思就是「把這個節點安全地刪除」
		
	# ==========================================
	var unequip_btn = Button.new()
	unequip_btn.custom_minimum_size = Vector2(80, 80)
	unequip_btn.flat = true
	unequip_btn.text = "X\n卸除" # 簡單用文字當圖標，之後你可以換成打叉的圖片
	unequip_btn.add_theme_color_override("font_color", Color.BLACK)           # 正常狀態：黑色
	unequip_btn.add_theme_color_override("font_hover_color", Color.DIM_GRAY)  # 滑鼠滑過：深灰色
	unequip_btn.add_theme_color_override("font_pressed_color", Color.GRAY)    # 點擊瞬間：淺灰色
	
	unequip_btn.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.double_click:
				# 雙擊 -> 執行卸下並退回
				unequip_current_slot()
			else:
				# 單擊 -> 右側資訊欄顯示卸下說明
				info_name_label.text = "卸除裝備"
				info_desc_label.text = "清空這個欄位，讓 Bobo 兩手空空。"
	)
	list_content.add_child(unequip_btn)
	
	# ==========================================
	# 【全新生產線：去大腦倉庫搬真實道具】
	# ==========================================
	# 尋找大腦裡的真實道具庫存
	for item_id in DataManager.inventory_items.keys():
		var amount = DataManager.inventory_items[item_id]["reserve_amount"]
		
		# 只有當倉庫數量大於 0 的時候，才顯示在清單上！
		if amount > 0:
			var item_data = DataManager.ITEM_DB[item_id]
			
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(80, 80)
			btn.flat = true 
			
			# 從大腦讀取圖片路徑並載入
			if item_data.has("texture_path"):
				btn.icon = load(item_data["texture_path"])
				btn.expand_icon = true
				btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				
			# 設定單擊預覽與雙擊裝備
			btn.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					if event.double_click:
						# 雙擊裝備！(把真實的 item_id 跟 資料傳過去)
						equip_item_to_slot(item_id, item_data)
					else:
						# 單擊預覽：把大腦裡的名稱和敘述丟給右邊的 Label
						info_name_label.text = item_data["name"]
						info_desc_label.text = item_data["description"]
			)
			
			list_content.add_child(btn)
	
	
	
# ==========================================
# 更新右側預覽資訊的功能
# ==========================================
func update_info_panel(item_data):
	# 把右側的 Label 文字，換成被點擊道具的資料
	info_name_label.text = item_data["item_name"]
	info_desc_label.text = item_data["description"]

# ==========================================
# 裝備道具的核心功能 (真實連動版)
# ==========================================
func equip_item_to_slot(item_id, item_data):
	# UI 顯示是 1~4，但在陣列裡是 0~3
	var array_index = current_slot_index - 1 
	
	# 1. 正式寫入大腦陣列！
	DataManager.equipped_items[array_index] = item_id
	print("【系統】", item_data["name"], " 裝備成功！目前大腦裝備狀態：", DataManager.equipped_items)
	
	# 2. 更新畫面的格子圖片
	var target_slot = center_slots.get_node("SlotsGrid/Slot_" + str(current_slot_index))
	var icon_layer = target_slot.get_node("ItemIcon")
	
	if item_data.has("texture_path"):
		icon_layer.texture = load(item_data["texture_path"])
		
	# 3. 關閉清單退回
	close_item_list()


# ==========================================
# 卸下裝備的核心功能 (隻狼風格)
# ==========================================
func unequip_current_slot():
	# 1. 把我們 UI 的帳本清空
	equipped_items[current_slot_index] = null
	
	# 2. 抓到畫面上那個格子，把圖片拔掉 (變成 null)
	var target_slot = center_slots.get_node("SlotsGrid/Slot_" + str(current_slot_index))
	target_slot.get_node("ItemIcon").texture = null
	
	# 3. 關閉商品瀏覽，完美退回上一頁
	close_item_list()



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


# ==========================================
# 設定裝備格的 UI 互動特效
# ==========================================
func setup_slot_effects():
	for i in range(1, 5):
		var slot = center_slots.get_node("SlotsGrid/Slot_" + str(i))
		
		# 游標滑上 -> 變亮
		slot.mouse_entered.connect(func(): slot.modulate = Color(1.2, 1.2, 1.2))
		# 游標離開 -> 恢復正常
		slot.mouse_exited.connect(func(): slot.modulate = Color(1.0, 1.0, 1.0))
		# 點擊瞬間 -> 變暗
		slot.button_down.connect(func(): slot.modulate = Color(0.7, 0.7, 0.7))
		# 放開瞬間 -> 恢復微亮
		slot.button_up.connect(func(): slot.modulate = Color(1.2, 1.2, 1.2))

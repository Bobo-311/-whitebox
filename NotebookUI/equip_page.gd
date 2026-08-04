extends Control
#equip_page
# --- 介面節點綁定 ---
# 裝備格的容器
@onready var center_slots = $MarginContainer/MainLayout/Center_Stage/Center_Slots
@onready var item_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/ItemSlotsGrid
@onready var skill_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/SkillSlotsGrid

# 🌟 新增：貼紙專用容器 (裡面不放任何格子)
@onready var sticker_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/StickerSlotsGrid

# 道具清單介面
@onready var item_list_ui = $MarginContainer/MainLayout/Center_Stage/ItemList_UI
@onready var list_content = $MarginContainer/MainLayout/Center_Stage/ItemList_UI/ListContent

# 右側資訊面板文字
@onready var info_name_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemName
@onready var info_desc_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemDesc
@onready var info_story_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemStory

# --- 系統記憶 ---
# 記錄 1~5 格裝了什麼 (null = 空的)
var equipped_items = { 1: null, 2: null, 3: null, 4: null, 5: null }

# 記錄玩家「現在選了哪一格」
var current_selected_type: String = ""   
var current_selected_index: int = -1     

# 記錄玩家在清單裡「預覽了哪個道具」
var current_list_selected_item: String = "" 

func _ready():
	close_item_list()
	setup_all_slots() # 啟動時自動綁定所有格子
	
	# 🌟 新增：啟動時也讀取一次貼紙
	load_stickers()
	
	# 當介面被隱藏或顯示時，通知自己
	visibility_changed.connect(_on_visibility_changed)

func _input(event):
	# 只要按了筆記本快捷鍵 (Tab) 或取消鍵
	if event.is_action_pressed("TAB") or event.is_action_pressed("ESC"):
		
		# 1. 強制洗白所有「點過誰」的記憶
		current_selected_type = ""
		current_selected_index = -1
		current_list_selected_item = ""
		
		# 2. 如果清單開著，把它關掉退回首頁
		if item_list_ui.visible:
			close_item_list()
			get_viewport().set_input_as_handled()



func on_sticker_clicked(sticker_id: String):
	# 點擊貼紙時，洗白道具的選取記憶
	current_selected_type = "sticker"
	current_selected_index = -1
	current_list_selected_item = ""
	
	clear_info_panel()
	
	var data = DataManager.STICKER_DB[sticker_id]
	info_name_label.text = data["name"]
	
	var effect_text = "功能類型：" + data["type"] + "\n數值影響：" + str(data["value"])
	if data.has("threshold"):
		effect_text += "\n發動條件：HP低於 " + str(data["threshold"] * 100) + "%"
		
	info_desc_label.text = effect_text
	if info_story_label: info_story_label.hide()

# --- 格子綁定與搜尋 ---
func setup_all_slots():
	# 🌟 1. 把 sticker_slots_grid 也加進掃描名單
	var all_grids = [item_slots_grid, skill_slots_grid, sticker_slots_grid] 
	for grid in all_grids:
		if grid:
			for child in grid.get_children():
				if child is NotebookEquipSlot:
					child.slot_clicked.connect(on_slot_clicked)
					
					# 🌟🌟🌟 本次新增：讓道具格一出生就去大腦讀取記憶 🌟🌟🌟
					# 為什麼要做這步？因為你原本每次打開筆記本，格子都是空的。
					# 現在我們讓它去問大腦：「我這格原本裝了什麼？」
					if child.slot_type == "item":
						# 數學小教室：UI 上的格子是 1~5，但大腦裡的陣列是 0~4，所以要減 1
						var array_idx = child.slot_index - 1
						var saved_item_id = DataManager.quick_slots[array_idx]
						
						# 如果大腦說這格有裝東西，而且圖鑑裡查得到這個東西
						if saved_item_id != "" and DataManager.ITEM_DB.has(saved_item_id):
							# 去圖鑑把圖片路徑抓出來，幫這格換上對應的圖片
							var texture_path = DataManager.ITEM_DB[saved_item_id]["texture_path"]
							child.set_icon(texture_path)

func get_slot_node(type: String, index: int) -> NotebookEquipSlot:
	# 🌟 2. 讓系統知道貼紙格要去哪裡找
	var grid = null
	if type == "item": grid = item_slots_grid
	elif type == "skill": grid = skill_slots_grid
	elif type == "sticker": grid = sticker_slots_grid
	
	if grid:
		for child in grid.get_children():
			if child is NotebookEquipSlot and child.slot_index == index:
				return child
	return null

# ==========================================
# 🌟 讀取貼紙資料 (安全版：只換圖，不刪節點)
# ==========================================
func load_stickers():
	for i in range(4):
		var slot = get_slot_node("sticker", i + 1)
		if slot:
			var sticker_id = DataManager.equipped_stickers[i]
			if sticker_id != "" and DataManager.STICKER_DB.has(sticker_id):
				# 有貼紙就換圖
				slot.set_icon(DataManager.STICKER_DB[sticker_id].texture_path)
			else:
				# 沒貼紙就清空，露出你的圓形底框
				slot.set_icon("")

# --- 點擊處理 ---
func on_slot_clicked(slot_type: String, index: int):
	# 點到技能格：目前只能預覽，洗白右邊面板顯示未實裝
	if slot_type == "skill":
		current_selected_type = slot_type
		current_selected_index = index
		clear_info_panel()
		info_name_label.text = "尚未實裝"
		info_desc_label.text = "此欄位目前僅供預覽。"
		return

	# 點到道具格：第一下預覽資訊，第二下開啟裝備清單
	if slot_type == "item":
		if current_selected_type == slot_type and current_selected_index == index:
			open_item_list(slot_type, index)
		else:
			current_selected_type = slot_type 
			current_selected_index = index    
			show_equipped_item_info(slot_type, index)
	# 🌟 點到貼紙格
	if slot_type == "sticker":
		current_selected_type = slot_type
		current_selected_index = index
		show_equipped_sticker_info(index)
		return

# 當介面顯示/隱藏狀態改變時觸發
func _on_visibility_changed():
	if not visible:
		# 介面被隱藏 (按 Tab 關掉) 時，強制洗白點擊記憶
		current_selected_type = ""
		current_selected_index = -1
		current_list_selected_item = ""
		close_item_list() # 確保下次打開不會卡在道具清單畫面
		clear_info_panel()
	else:
		# 🌟 新增：每次打開筆記本時，重新讀取一次最新貼紙
		load_stickers()

# --- 面板更新 ---
func show_equipped_item_info(slot_type: String, index: int):
	clear_info_panel() 
	# 去記憶體抓道具 ID，有抓到就顯示設定，沒有就顯示空欄位
	if slot_type == "item":
		# 🌟 以前你從局部的 equipped_items 拿資料，現在統一從大腦拿！
		var array_index = index - 1
		var item_id = equipped_items[index]
		
		# 如果大腦說這格有裝東西
		if item_id and DataManager.ITEM_DB.has(item_id):
			var data = DataManager.ITEM_DB[item_id]
			info_name_label.text = data["name"]
			if data.has("description"): info_desc_label.text = data["description"]
			if data.has("story"):
				info_story_label.text = data["story"]
				info_story_label.show()
		else:
			# 如果大腦說這格是空的
			info_name_label.text = "空欄位"
			info_desc_label.text = "再點擊一下以選擇道具。"

# 🌟 新增：貼紙專用資訊面板
func show_equipped_sticker_info(index: int):
	clear_info_panel()
	var sticker_id = DataManager.equipped_stickers[index - 1]
	
	if sticker_id != "" and DataManager.STICKER_DB.has(sticker_id):
		var data = DataManager.STICKER_DB[sticker_id]
		info_name_label.text = data["name"]
		
		var effect_text = "功能類型：" + data["type"] + "\n數值影響：" + str(data["value"])
		if data.has("threshold"):
			effect_text += "\n發動條件：HP低於 " + str(data["threshold"] * 100) + "%"
		info_desc_label.text = effect_text
	else:
		info_name_label.text = "空欄位"
		info_desc_label.text = "尚未裝備任何貼紙。"


func clear_info_panel():
	# 清空右側面板文字
	if info_name_label: info_name_label.text = ""
	if info_desc_label: info_desc_label.text = ""
	if info_story_label: 
		info_story_label.text = ""
		info_story_label.show()

# --- 清單操作 ---
func open_item_list(slot_type: String, index: int):
	refresh_inventory_ui() # 重新生成背包清單
	center_slots.hide()    # 藏起原本的格子
	item_list_ui.show()    # 秀出清單
	
	if info_story_label: info_story_label.hide()
	info_name_label.text = "選擇裝備"
	info_desc_label.text = "請從左側選擇要裝備的道具。"
	current_list_selected_item = "" 

func close_item_list():
	item_list_ui.hide()    
	center_slots.show()    
	show_equipped_item_info(current_selected_type, current_selected_index)
	
	# 離開清單時重置選擇狀態
	current_selected_type = ""
	current_selected_index = -1
	current_list_selected_item = ""

func refresh_inventory_ui():
	# 清空舊按鈕
	for child in list_content.get_children():
		child.queue_free()

	if not DataManager or not DataManager.inventory_items: return

	# 遍歷背包，擁有數量 > 0 才生成按鈕
	for item_id in DataManager.inventory_items.keys():
		var amount = DataManager.inventory_items[item_id]["reserve_amount"]
		if amount > 0:
			var item_data = DataManager.ITEM_DB[item_id]
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 60) 
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT 
			btn.text = "      " + item_data["name"] + "  (擁有: " + str(amount) + ")"
			

			if item_data.has("texture_path"):
				btn.icon = load(item_data["texture_path"])
				btn.expand_icon = true

			# 清單內的按鈕一樣兩階段點擊：第一下看資訊，第二下裝備
			btn.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					if current_list_selected_item == item_id:
						equip_item_to_slot(item_id, item_data)
					else:
						current_list_selected_item = item_id
						info_name_label.text = item_data["name"]
						if item_data.has("description"): info_desc_label.text = item_data["description"]
						if info_story_label: info_story_label.hide()
			)
			list_content.add_child(btn)

# ==========================================
# 🌟 第三大修改：正式將道具裝備進大腦
# ==========================================
func equip_item_to_slot(item_id, item_data):
	if current_selected_type == "item":
		
		# 🌟 第一步：把 UI 的格子編號 (1~5) 轉換成大腦陣列的編號 (0~4)
		var array_index = current_selected_index - 1 
		
		# 🌟 第二步：防影分身機制 (超級重要！)
		# 假設你原本第 1 格放蘋果，現在你想把蘋果改放到第 3 格。
		# 必須先巡視大腦的 5 個格子，把「舊的蘋果」拔掉，才不會同時出現兩個蘋果！
		for i in range(5):
			# 如果發現大腦裡某一格裝的東西，跟我們現在要裝的東西一模一樣
			if DataManager.quick_slots[i] == item_id:
				# 1. 把大腦裡的那格洗白 (變成空字串)
				DataManager.quick_slots[i] = "" 
				# 2. 順便呼叫 UI，把那個舊格子的圖片清空
				var old_slot = get_slot_node("item", i + 1)
				if old_slot: old_slot.set_icon("") 
		
		# 🌟 第三步：正式把新道具寫入大腦！
		DataManager.quick_slots[array_index] = item_id 
		
		# 🌟 第四步：幫筆記本上「目前選中的這格」換上新道具的圖片
		var target_slot = get_slot_node("item", current_selected_index)
		if target_slot and item_data.has("texture_path"):
			target_slot.set_icon(item_data["texture_path"]) 
			
		# 🌟🌟🌟 第五步：最核心的一行！發射廣播！🌟🌟🌟
		# 大腦的資料改完了，現在大喊一聲，讓左下角的 QuickSlotUI 聽到後立刻重畫畫面！
		DataManager.quick_slot_updated.emit()
			
	close_item_list()

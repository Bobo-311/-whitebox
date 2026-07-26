extends Control

# --- 介面節點綁定 ---
# 裝備格的容器
@onready var center_slots = $MarginContainer/MainLayout/Center_Stage/Center_Slots
@onready var item_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/ItemSlotsGrid
@onready var skill_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/SkillSlotsGrid

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
	
	# 新增這行：當介面被隱藏或顯示時，通知自己
	visibility_changed.connect(_on_visibility_changed)

func _input(event):
	# 只要按了筆記本快捷鍵 (Tab) 或取消鍵
	if event.is_action_pressed("notebook") or event.is_action_pressed("ui_cancel"):
		
		# 1. 強制洗白所有「點過誰」的記憶
		current_selected_type = ""
		current_selected_index = -1
		current_list_selected_item = ""
		
		# 2. 如果清單開著，把它關掉退回首頁
		if item_list_ui.visible:
			close_item_list()
			get_viewport().set_input_as_handled()

# --- 格子綁定與搜尋 ---
func setup_all_slots():
	# 掃描道具與技能區，把所有 EquipSlot 格子的點擊事件接上
	var all_grids = [item_slots_grid, skill_slots_grid] 
	for grid in all_grids:
		if grid:
			for child in grid.get_children():
				if child is EquipSlot:
					child.slot_clicked.connect(on_slot_clicked)

func get_slot_node(type: String, index: int) -> EquipSlot:
	# 根據身分證 (slot_index) 找出畫面上對應的格子節點
	var grid = item_slots_grid if type == "item" else skill_slots_grid
	if grid:
		for child in grid.get_children():
			if child is EquipSlot and child.slot_index == index:
				return child
	return null

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

# 當介面顯示/隱藏狀態改變時觸發
func _on_visibility_changed():
	if not visible:
		# 介面被隱藏 (按 Tab 關掉) 時，強制洗白點擊記憶
		current_selected_type = ""
		current_selected_index = -1
		current_list_selected_item = ""
		close_item_list() # 確保下次打開不會卡在道具清單畫面
		clear_info_panel()



# --- 面板更新 ---
func show_equipped_item_info(slot_type: String, index: int):
	clear_info_panel() 
	
	# 去記憶體抓道具 ID，有抓到就顯示設定，沒有就顯示空欄位
	if slot_type == "item":
		var item_id = equipped_items[index]
		if item_id and DataManager.ITEM_DB.has(item_id):
			var data = DataManager.ITEM_DB[item_id]
			info_name_label.text = data["name"]
			if data.has("description"): info_desc_label.text = data["description"]
			if data.has("story"):
				info_story_label.text = data["story"]
				info_story_label.show()
		else:
			info_name_label.text = "空欄位"
			info_desc_label.text = "再點擊一下以選擇道具。"

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

# --- 裝備執行 ---
func equip_item_to_slot(item_id, item_data):
	if current_selected_type == "item":
		
		# 防影分身：如果別格裝過同道具，把它拔掉並清空圖片
		for slot_idx in equipped_items.keys():
			if equipped_items[slot_idx] == item_id:
				equipped_items[slot_idx] = null
				var old_slot = get_slot_node("item", slot_idx)
				if old_slot: old_slot.set_icon("") 
		
		# 裝上新道具：寫入記憶，並呼叫格子換圖
		equipped_items[current_selected_index] = item_id 
		var target_slot = get_slot_node("item", current_selected_index)
		
		if target_slot and item_data.has("texture_path"):
			target_slot.set_icon(item_data["texture_path"]) 
			
	close_item_list()

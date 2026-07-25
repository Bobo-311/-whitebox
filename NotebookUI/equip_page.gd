extends Control

# ==========================================
# 節點抓取區：將場景樹中的 UI 元件全部綁定到腳本變數
# ==========================================
@onready var center_slots = $MarginContainer/MainLayout/Center_Stage/Center_Slots
@onready var item_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/ItemSlotsGrid
@onready var sticker_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/StickerSlotsGrid
@onready var skill_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/SkillSlotsGrid

@onready var item_list_ui = $MarginContainer/MainLayout/Center_Stage/ItemList_UI
@onready var list_content = $MarginContainer/MainLayout/Center_Stage/ItemList_UI/ListContent

# 右側資訊欄節點 (名稱、描述、故事)
@onready var info_name_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemName
@onready var info_desc_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemDesc
@onready var info_story_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemStory

# ==========================================
# 系統狀態與防呆記憶變數
# ==========================================
# 記錄 5 個道具格目前裝了哪個道具 ID (預設都是空的 null)
var equipped_items = {
	1: null, 2: null, 3: null, 4: null, 5: null
}

# 防呆大腦：記錄目前選中的是哪一種類型 ("item", "sticker", "skill")
var current_selected_type: String = ""
# 防呆大腦：記錄目前選中該類型的第幾個格子 (1~5) (-1 代表目前沒選中任何格子)
var current_selected_index: int = -1

# 記錄目前在「道具清單」裡被點擊預覽的是哪個道具 ID
var current_list_selected_item: String = ""

# ==========================================
# 遊戲初始化設定
# ==========================================
func _ready():
	# 遊戲一開始預設關閉道具清單，只顯示左側的 5-4-3 裝備格子
	close_item_list()
	# 自動呼叫工廠函式，把 12 個格子的點擊訊號全部自動綁定好，不用手動拉線
	setup_all_slots()

# 鍵盤監聽：當道具清單打開時，按下 Tab 鍵或 ESC 鍵可以退回裝備格
func _input(event):
	if item_list_ui.visible:
		if event.is_action_pressed("notebook") or event.is_action_pressed("ui_cancel"):
			close_item_list()
			get_viewport().set_input_as_handled() # 攔截事件，防止背後的主選單跟著關閉

# ==========================================
# 自動綁定 12 個格子的點擊與滑鼠互動特效
# ==========================================
func setup_all_slots():
	# 1. 自動綁定道具格 (共 5 格)
	for i in range(1, 6):
		var slot = item_slots_grid.get_node_or_null("Slot_" + str(i))
		if slot:
			slot.pressed.connect(func(): on_slot_clicked("item", i))
			add_hover_effect(slot)
			
	# 2. 自動綁定貼紙格 (共 4 格)
	for i in range(1, 5):
		var slot = sticker_slots_grid.get_node_or_null("StickerSlot_" + str(i))
		if slot:
			slot.pressed.connect(func(): on_slot_clicked("sticker", i))
			add_hover_effect(slot)
			
	# 3. 自動綁定招式格 (共 3 格)
	for i in range(1, 4):
		var slot = skill_slots_grid.get_node_or_null("SkillSlot_" + str(i))
		if slot:
			slot.pressed.connect(func(): on_slot_clicked("skill", i))
			add_hover_effect(slot)

# 滑鼠懸停與點擊時的視覺回饋特效 (變亮或變暗)
func add_hover_effect(slot):
	slot.mouse_entered.connect(func(): slot.modulate = Color(1.2, 1.2, 1.2))
	slot.mouse_exited.connect(func(): slot.modulate = Color(1.0, 1.0, 1.0))
	slot.button_down.connect(func(): slot.modulate = Color(0.7, 0.7, 0.7))
	slot.button_up.connect(func(): slot.modulate = Color(1.2, 1.2, 1.2))

# ==========================================
# 核心防呆邏輯：點擊任意裝備格子時的判定
# ==========================================
func on_slot_clicked(slot_type: String, index: int):
	# 🔴 隔離貼紙與技能格子：目前只做純預覽，絕對不會開啟道具清單
	if slot_type == "sticker" or slot_type == "skill":
		current_selected_type = slot_type
		current_selected_index = index
		clear_info_panel()
		info_name_label.text = "尚未實裝"
		info_desc_label.text = "此欄位目前僅供預覽。"
		return

	# 🟢 道具格子專屬的兩階段邏輯：
	if slot_type == "item":
		# 判定 A (第二下)：如果點擊的格子跟「剛才記憶中的格子」完全相同 -> 打開道具清單準備換裝備
		if current_selected_type == slot_type and current_selected_index == index:
			open_item_list(slot_type, index)
		# 判定 B (第一下)：如果點的是不同的新格子 -> 僅更新右側資訊面板預覽，不開清單
		else:
			current_selected_type = slot_type 
			current_selected_index = index    
			show_equipped_item_info(slot_type, index)

# 更新右側面板資訊 (會同時處理名稱、說明、以及故事的顯示與隱藏)
func show_equipped_item_info(slot_type: String, index: int):
	clear_info_panel() # 先把舊資料洗白，防止殘留
	
	if slot_type == "item":
		var item_id = equipped_items[index]
		if item_id and DataManager.ITEM_DB.has(item_id):
			var data = DataManager.ITEM_DB[item_id]
			info_name_label.text = data["name"]
			if data.has("description"):
				info_desc_label.text = data["description"]
			# 如果有故事，填入故事並確保故事欄位是顯示狀態
			if data.has("story"):
				info_story_label.text = data["story"]
				info_story_label.show()
		else:
			# 如果格子裡是空的
			info_name_label.text = "空欄位"
			info_desc_label.text = "再點擊一下以選擇道具。"

# 清空右側面板內容的專用函式
func clear_info_panel():
	if info_name_label: info_name_label.text = ""
	if info_desc_label: info_desc_label.text = ""
	if info_story_label: 
		info_story_label.text = ""
		info_story_label.show()

# ==========================================
# 畫面切換控制 (裝備欄面 <-> 道具清單頁面)
# ==========================================
func open_item_list(slot_type: String, index: int):
	refresh_inventory_ui() # 重新生成隻狼風格的道具清單
	center_slots.hide()    # 隱藏左側的 5-4-3 裝備格子
	item_list_ui.show()    # 顯示左側的道具清單容器
	
	# 打開清單時，預設隱藏故事欄位，並給予操作提示
	if info_story_label:
		info_story_label.hide()
	info_name_label.text = "選擇裝備"
	info_desc_label.text = "請從左側選擇要裝備的道具。"
	current_list_selected_item = "" # 清空清單內的選取記憶

func close_item_list():
	item_list_ui.hide()    # 隱藏左側道具清單
	center_slots.show()    # 顯示左側裝備格子
	
	# 退回裝備格時，重新顯示剛剛選中那一格的資訊
	show_equipped_item_info(current_selected_type, current_selected_index)
	
	# 強制讓系統失憶，這樣下次點擊裝備格時，才會重新被判定為「第一下單擊預覽」
	current_selected_type = ""
	current_selected_index = -1
	current_list_selected_item = ""

# ==========================================
# 生成隻狼風格道具清單 (點第一下預覽資訊，點第二下確認裝備)
# ==========================================
func refresh_inventory_ui():
	# 每次打開清單前，先把舊有的按鈕全部清除乾淨
	for child in list_content.get_children():
		child.queue_free()

	# 檢查大腦資料庫是否存在
	if not DataManager or not DataManager.inventory_items: return

	# 讀取背包庫存，開始動態生成道具按鈕
	for item_id in DataManager.inventory_items.keys():
		var amount = DataManager.inventory_items[item_id]["reserve_amount"]
		# 只有當擁有數量大於 0 時才生成按鈕
		if amount > 0:
			var item_data = DataManager.ITEM_DB[item_id]
			
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 60) # 長條橫幅高度
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL # 寬度自動填滿容器
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT # 文字靠左對齊
			btn.text = "      " + item_data["name"] + "  (擁有: " + str(amount) + ")"

			# 如果資料庫有圖示路徑，載入並顯示圖示
			if item_data.has("texture_path"):
				btn.icon = load(item_data["texture_path"])
				btn.expand_icon = true

			# 按鈕的兩階段點擊防呆判定
			btn.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					# 判定 A (第二下)：如果點擊的道具跟剛剛記憶中的一樣 -> 直接裝備並自動退回裝備頁
					if current_list_selected_item == item_id:
						equip_item_to_slot(item_id, item_data)
					# 判定 B (第一下)：如果點的是新道具 -> 僅記錄併發送預覽到右側面板，同時隱藏故事
					else:
						current_list_selected_item = item_id
						info_name_label.text = item_data["name"]
						if item_data.has("description"):
							info_desc_label.text = item_data["description"]
						if info_story_label: 
							info_story_label.hide() # 道具清單模式下強制隱藏故事
			)
			list_content.add_child(btn)

# ==========================================
# 裝備動作執行：將道具寫入格子並更新畫面圖示
# ==========================================
func equip_item_to_slot(item_id, item_data):
	if current_selected_type == "item":
		equipped_items[current_selected_index] = item_id # 寫入帳本記憶
		var target_slot = item_slots_grid.get_node_or_null("Slot_" + str(current_selected_index))
		if target_slot and item_data.has("texture_path"):
			target_slot.get_node("ItemIcon").texture = load(item_data["texture_path"]) # 更新畫面上格子的圖片
			
	close_item_list() # 裝備完成後，自動關閉清單並退回裝備格畫面

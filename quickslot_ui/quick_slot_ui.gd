extends Control#QuickSlotUI

# ==========================================
# 節點抓取區 (確保這裡的名字跟你場景裡的節點名字一模一樣)
# ==========================================
@onready var center_icon: TextureRect = $CenterSlot/ItemIcon
@onready var center_label: Label = $CenterSlot/AmountLabel

@onready var left_icon: TextureRect = $LeftSlot/ItemIcon
@onready var right_icon: TextureRect = $RightSlot/ItemIcon

func _ready() -> void:
	# 🌟 頻道綁定：只要聽到大腦喊 quick_slot_updated，就立刻執行 update_ui
	if not DataManager.quick_slot_updated.is_connected(update_ui):
		DataManager.quick_slot_updated.connect(update_ui)
	# 遊戲一開始，先跟大腦拿一次資料來更新畫面
	update_ui()

# ==========================================
# 🔄 核心更新畫面邏輯
# ==========================================
func update_ui() -> void:
	# 防呆：確保 DataManager 有成功載入
	if not DataManager: return
	
	# 從 DataManager 大腦獲取目前的狀態
	var slots = DataManager.quick_slots
	var current_idx = DataManager.current_slot_index
	var slots_count = slots.size()
	
	# 算出左邊跟右邊的 index 是多少 (含完美循環邏輯)
	var left_idx = (current_idx - 1 + slots_count) % slots_count
	var right_idx = (current_idx + 1) % slots_count
	
	# 更新三個格子的圖片與狀態
	setup_slot(slots[current_idx], center_icon, center_label)
	setup_slot(slots[left_idx], left_icon, null) # 左右兩邊傳入 null，代表不顯示數字
	setup_slot(slots[right_idx], right_icon, null) 

# ==========================================
# 🎨 單一格子設定 (換圖、變暗、改數字)
# ==========================================
func setup_slot(item_id: String, icon_rect: TextureRect, label: Label = null) -> void:
	if item_id == "":
		# 如果這格是空的，把圖片清空
		icon_rect.texture = null
		if label: label.text = ""
		return
		
	# 從 ITEM_DB 抓取道具資料 (確保你的 DataManager 裡有 ITEM_DB)
	if DataManager.ITEM_DB.has(item_id):
		var item_data = DataManager.ITEM_DB[item_id]
		var current_count = DataManager.get_item_count(item_id)
		var max_count = item_data.get("max_carry", 1) # 預設最大攜帶量為1
		
		# 1. 換上對應的道具圖片
		icon_rect.texture = load(item_data["texture_path"])
		
		# 2. 處理數字顯示 (只有中間那格有傳 label 進來，才會執行這段)
		if label:
			label.text = str(current_count) + "/" + str(max_count)
			
		# 3. 🌟 視覺回饋：如果沒水了 (0數量)，把道具圖示變成暗灰色！
		if current_count <= 0:
			icon_rect.modulate = Color(0.3, 0.3, 0.3, 1.0) # 變暗灰
		else:
			icon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) # 恢復正常顏色

extends Control#QuickSlotUI

# ==========================================
# 節點抓取區 (確保這裡的名字跟你場景裡的節點名字一模一樣)
# ==========================================
@onready var center_slot = $CenterSlot
@onready var center_icon: TextureRect = $CenterSlot/ItemIcon
@onready var center_label: Label = $CenterSlot/AmountLabel

@onready var left_slot = $LeftSlot
@onready var left_icon: TextureRect = $LeftSlot/ItemIcon

@onready var right_slot = $RightSlot
@onready var right_icon: TextureRect = $RightSlot/ItemIcon

# ==========================================
# 🌟 動畫專用記憶體
# ==========================================
var last_index: int = -1 # 記住上一次的 index，用來判斷玩家是往左切還是往右切
var tween: Tween # 專屬動畫控制器
var center_orig_pos: Vector2
var left_orig_pos: Vector2
var right_orig_pos: Vector2

func _ready() -> void:
	# 🌟 關鍵修復 1：強制等待一幀，等 Godot 把 UI 確實排版到左下角後，再抓取座標！
	await get_tree().process_frame
	
	# 記住三個格子真正的完美座標
	center_orig_pos = center_slot.position
	left_orig_pos = left_slot.position
	right_orig_pos = right_slot.position
	
	# 🌟 關鍵修復 2：把中間圖片的中心點設在正中間，這樣彈跳縮放才不會歪掉！
	center_icon.pivot_offset = center_icon.size / 2.0
	
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

	# 🌟 動畫觸發邏輯：判斷切換方向
	if last_index != -1 and current_idx != last_index:
		var dir = 0
		# 如果是往右切 (按3)，或者發生邊界循環 (從最後一個切回第0個)
		if current_idx == (last_index + 1) % slots_count:
			dir = 1 # 往右轉
		# 如果是往左切 (按1)，或者發生邊界循環 (從第0個切回最後一個)
		elif current_idx == (last_index - 1 + slots_count) % slots_count:
			dir = -1 # 往左轉
			
		play_switch_animation(dir)
		
	last_index = current_idx # 更新記憶

# ==========================================
# 🎬 切換動畫核心 (Tween)
# ==========================================
func play_switch_animation(dir: int) -> void:
	# 如果上次的動畫還沒播完，直接砍掉重練，避免玩家狂按導致 UI 飛走
	if tween: tween.kill()
	tween = create_tween().set_parallel(true) # set_parallel(true) 代表所有動畫同時播放
	
	# 設定滑動距離 (你可以依據你的 UI 大小調整這個數字，目前設 40 像素)
	var offset_x = 40 * dir 
	
	# --- 1. 中間格子的「Q彈」動畫 ---
	# 先把中間格子強行推開，然後花 0.2 秒平滑滑回原位
	center_slot.position.x = center_orig_pos.x + offset_x
	tween.tween_property(center_slot, "position:x", center_orig_pos.x, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 🌟 關鍵修復 3：只針對圖片(Icon)做放大縮小，不搞亂外框！
	center_icon.scale = Vector2(1.3, 1.3)
	tween.tween_property(center_icon, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# --- 2. 左邊格子的「跟進」動畫 ---
	left_slot.position.x = left_orig_pos.x + offset_x
	tween.tween_property(left_slot, "position:x", left_orig_pos.x, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	left_slot.modulate.a = 0.0 # 先變透明
	tween.tween_property(left_slot, "modulate:a", 1.0, 0.15) # 快速淡入
	
	# --- 3. 右邊格子的「跟進」動畫 ---
	right_slot.position.x = right_orig_pos.x + offset_x
	tween.tween_property(right_slot, "position:x", right_orig_pos.x, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	right_slot.modulate.a = 0.0 # 先變透明
	tween.tween_property(right_slot, "modulate:a", 1.0, 0.15) # 快速淡入


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

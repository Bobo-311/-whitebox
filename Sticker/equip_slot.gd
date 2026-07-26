extends TextureRect 

# ==========================================
# 【設定區】
# slot_index 代表這個格子是大腦陣列 (0~3) 的第幾個。
# ⚠️ 必須在編輯器手動設定：Slot_1=0, Slot_2=1, Slot_3=2, Slot_4=3
# ==========================================
@export var slot_index: int = 0
@onready var holder: CenterContainer = $Holder 

const STICKER_ITEM = preload("res://StickerItem/sticker_item.tscn") 

# 記憶體：讓格子記住「自己目前畫面上顯示的是哪張貼紙」
var current_rendered_id: String = "" 

func _ready() -> void:
	# 【訂閱廣播】
	# MVC 架構核心：UI 不准自己亂改畫面。
	# 我們讓格子變成聽指令的小弟，只要大腦 (DataManager) 大喊「裝備變更！」，
	# 所有格子就會立刻執行 _sync_with_data()，照著大腦現在的陣列重新畫圖。
	DataManager.equipment_changed.connect(_sync_with_data)
	_sync_with_data() # 開局先主動對齊一次大腦狀態

# ==========================================
# 【核心邏輯：與大腦同步畫面】
# ==========================================
func _sync_with_data() -> void:
	# 1. 問大腦：我這格 (slot_index) 現在應該裝什麼？
	var saved_id = DataManager.equipped_stickers[slot_index]
	
	# 2. 判斷情況並更新畫面：
	if saved_id == "":
		# 情況 A：大腦說這格是空的 -> 拔掉貼紙，清空畫面。
		_clear_slot()
		current_rendered_id = ""
	elif saved_id != current_rendered_id:
		# 情況 B：大腦說的貼紙，跟我現在畫面上顯示的不一樣！
		_clear_slot()             # 先拔掉舊的
		_spawn_sticker(saved_id)  # 生成新的
		current_rendered_id = saved_id # 更新記憶體

# ==========================================
# 【拖曳系統：放下裝備】
# ==========================================
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 防呆：只接收帶有 "type": "sticker" 標籤的東西
	return typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "sticker"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var new_id = data["id"]
	
	# 1. 【防影分身】在裝備前，先去大腦巡邏一圈 (0~3格)
	# 如果發現別格已經裝了這張貼紙，就強制把它變成空字串 "" (也就是卸下)
	for i in range(DataManager.equipped_stickers.size()):
		if DataManager.equipped_stickers[i] == new_id:
			DataManager.equipped_stickers[i] = ""
			
	# 2. 【寫入大腦】把新貼紙的 ID 寫入這格專屬的位子
	DataManager.equipped_stickers[slot_index] = new_id
	
	# 3. 【發射廣播】這行一執行，所有格子的 _sync_with_data() 都會被觸發。
	# 剛才被強制卸下的舊格子會自動清空，這格新格子會自動顯示圖案。完美連動！
	DataManager.equipment_changed.emit()

# ==========================================
# 【點擊系統：右鍵卸下】
# ==========================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 如果畫面上真的有裝東西，才執行卸下
		if current_rendered_id != "": 
			DataManager.equipped_stickers[slot_index] = ""
			DataManager.equipment_changed.emit() # 廣播通知大家更新畫面

# ==========================================
# 【工具函數：控制子節點】
# ==========================================
func _spawn_sticker(id: String) -> void:
	var new_sticker = STICKER_ITEM.instantiate()
	new_sticker.setup_sticker(id)
	
	# ⚠️【重要細節】關閉貼紙實體的滑鼠阻擋！
	# 如果不加這行，貼紙會擋住滑鼠，你的「右鍵卸下」點擊事件會傳不到底層的格子上。
	new_sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 放入托盤，托盤 (CenterContainer) 會自動把它置中
	holder.add_child(new_sticker) 

func _clear_slot() -> void:
	# 把托盤裡的所有貼紙實體全部刪除
	for child in holder.get_children():
		child.queue_free()

extends TextureRect 

# ==========================================
# 📊 [企劃數值與節點綁定 - Design & Nodes]
# ==========================================
# slot_index：這是格子的身分證號碼，對應大腦 (DataManager) 陣列裡的 0~3
@export var slot_index: int = 0

# holder：貼紙的專屬托盤。
# 這裡無論你是用 CenterContainer(死守原尺寸) 或 MarginContainer(強迫拉伸) 都可以，
# 因為我們接下來的邏輯是直接「隱藏白圈底圖」，不會再有視覺重疊的問題。
@onready var holder: Container = $Holder 

# 預載貼紙實體的藍圖，用以稍後動態生成
const STICKER_ITEM = preload("res://StickerItem/sticker_item.tscn") 

# ==========================================
# 🔒 [內部狀態鎖 - State Locks]
# ==========================================
# 記憶體：讓格子自己記住「目前畫面上顯示的是哪張貼紙的 ID」
var current_rendered_id: String = "" 

# ==========================================
# 💡 [初始化與廣播綁定 - Init & Signals]
# ==========================================
func _ready() -> void:
	# 【MVC 架構核心】：UI 絕對不自己亂改畫面。
	# 訂閱大腦的廣播，只要大腦一喊「裝備變更」，所有格子就乖乖執行 _sync_with_data 對齊大腦。
	DataManager.equipment_changed.connect(_sync_with_data)
	_sync_with_data() # 遊戲開局，先主動對齊一次狀態

# ==========================================
# 🧠 [核心邏輯：與大腦同步畫面 - Data Synchronization]
# ==========================================
func _sync_with_data() -> void:
	# 去問大腦：我這格 (slot_index) 現在應該裝什麼？
	var saved_id = DataManager.equipped_stickers[slot_index]
	
	if saved_id == "":
		# 情況 A：大腦說這格是空的。
		_clear_slot()
		current_rendered_id = ""
	elif saved_id != current_rendered_id:
		# 情況 B：大腦說這格有東西，而且跟我目前畫面上顯示的不一樣。
		_clear_slot()             # 1. 確保乾淨，先拔舊的
		_spawn_sticker(saved_id)  # 2. 生成新的貼紙，並「隱藏白圈底圖」
		current_rendered_id = saved_id # 3. 刷新記憶體

# ==========================================
# 🖱️ [拖曳與點擊系統 - Drag & Drop / Input]
# ==========================================
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 防呆檢查：只允許 type 為 "sticker" 的資料放進來
	return typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "sticker"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var new_id = data["id"]
	
	# 【防影分身】：在放上新格子前，巡邏大腦 0~3 格，把原本已經裝這張貼紙的舊格子洗白
	for i in range(DataManager.equipped_stickers.size()):
		if DataManager.equipped_stickers[i] == new_id:
			DataManager.equipped_stickers[i] = ""
			
	# 把新貼紙寫入大腦的這格
	DataManager.equipped_stickers[slot_index] = new_id
	
	# 呼叫大腦發射廣播，觸發所有格子的 _sync_with_data()
	DataManager.equipment_changed.emit()

func _gui_input(event: InputEvent) -> void:
	# 點擊右鍵卸下裝備
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if current_rendered_id != "": 
			DataManager.equipped_stickers[slot_index] = ""
			DataManager.equipment_changed.emit() 

# ==========================================
# 🌟 [視覺渲染替換魔法 - Visual Replacement] (本次核心修正)
# ==========================================
func _spawn_sticker(id: String) -> void:
	# 1. 生成實體並設定資料
	var new_sticker = STICKER_ITEM.instantiate()
	new_sticker.setup_sticker(id)
	
	# 2. 【防阻擋】：關閉貼紙的滑鼠捕捉，讓右鍵點擊能穿透貼紙，被底下的格子接收到
	new_sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 3. 放入托盤
	holder.add_child(new_sticker) 
	
	# 🌟【正規作法：狀態切換 (替換圖層)】
	# 為什麼用 self_modulate 而不是 modulate？
	# - 如果用 modulate.a = 0.0，這格底下「所有的子節點 (包含你剛放進去的貼紙)」都會跟著變透明消失！
	# - 使用 self_modulate.a = 0.0，只會把「格子自己的白圈底圖」變透明，完美保留子節點(貼紙)的顯示！
	self_modulate.a = 0.0 

func _clear_slot() -> void:
	# 1. 把托盤裡的貼紙實體全部刪除
	for child in holder.get_children():
		child.queue_free()
		
	# 🌟【狀態恢復】：當貼紙被拔掉，格子變回「空置狀態」，
	# 把白圈底圖的透明度調回 1.0 (完全不透明)，讓玩家知道這裡又可以放東西了。
	self_modulate.a = 1.0

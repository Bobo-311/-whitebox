extends TextureButton
class_name NotebookEquipSlot # 註冊為自訂組件，讓主程式能直接辨識

# 廣播訊號：當自己被點擊時，通知主程式「我是什麼類型、第幾格」
signal slot_clicked(slot_type: String, index: int)

# 開放給編輯器設定：可以直接在屬性面板下拉選擇，不用寫死在程式碼
@export_enum("item", "sticker", "skill") var slot_type: String = "item"
@export var slot_index: int = 1

@onready var item_icon = $ItemIcon

func _ready():
	# 綁定自己的點擊事件
	pressed.connect(_on_pressed)
	
	# 懸停視覺回饋：滑鼠移入變亮，按下變暗 (格子自己管自己，不麻煩主程式)
	mouse_entered.connect(func(): modulate = Color(1.2, 1.2, 1.2))
	mouse_exited.connect(func(): modulate = Color(1.0, 1.0, 1.0))
	button_down.connect(func(): modulate = Color(0.7, 0.7, 0.7))
	button_up.connect(func(): modulate = Color(1.2, 1.2, 1.2))	

func _on_pressed():
	# 按下按鈕時，發射訊號把自己的身分證交出去
	slot_clicked.emit(slot_type, slot_index)

# 外部呼叫用：主程式直接傳入圖片路徑就能換圖
func set_icon(texture_path: String):
	if texture_path == "":
		item_icon.texture = null
	else:
		item_icon.texture = load(texture_path)

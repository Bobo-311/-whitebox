extends CanvasLayer # StickerUI 貼紙介面主腳本

# ==========================================
# 🌟 貼紙模具載入區
# ==========================================
# 載入萬用貼紙模具，準備在稍後大量生成貼紙實體
const STICKER_ITEM = preload("res://StickerItem/sticker_item.tscn")

# ==========================================
# 節點抓取區 (@onready 確保畫面載入完畢才抓取)
# ==========================================


 
# 抓取 4 個用來控制翻頁的小點點 (已更新為最新完美命名)
@onready var dot1: TextureButton = $Easel/MainLayout/LeftPanel/Margin_UnequippedTitle/HBox_UnequippedTitle/HBox_PageDots/Dot1
@onready var dot2: TextureButton = $Easel/MainLayout/LeftPanel/Margin_UnequippedTitle/HBox_UnequippedTitle/HBox_PageDots/Dot2
@onready var dot3: TextureButton = $Easel/MainLayout/LeftPanel/Margin_UnequippedTitle/HBox_UnequippedTitle/HBox_PageDots/Dot3
@onready var dot4: TextureButton = $Easel/MainLayout/LeftPanel/Margin_UnequippedTitle/HBox_UnequippedTitle/HBox_PageDots/Dot4

# 抓取裝載貼紙的 4 個頁面容器 (已更新為最新完美命名)
@onready var page1: GridContainer = $Easel/MainLayout/LeftPanel/Margin_Pages/Page1
@onready var page2: GridContainer = $Easel/MainLayout/LeftPanel/Margin_Pages/Page2
@onready var page3: GridContainer = $Easel/MainLayout/LeftPanel/Margin_Pages/Page3
@onready var page4: GridContainer = $Easel/MainLayout/LeftPanel/Margin_Pages/Page4

# 🌟 右側：資訊面板 (路徑已更新為便利貼排版)
@onready var preview_img: TextureRect = $Easel/MainLayout/RightPanel/VBox_Info/Center_Preview/Img_Preview
@onready var info_title: Label = $Easel/MainLayout/RightPanel/VBox_Info/InfoTextContainer/ItemName
@onready var info_desc: RichTextLabel = $Easel/MainLayout/RightPanel/VBox_Info/InfoTextContainer/ItemDesc
# ==========================================
# 大腦記憶區 (記錄玩家目前的瀏覽狀態)
# ==========================================
var current_page: GridContainer # 記住目前畫面正在顯示哪一「頁」
var current_dot: TextureButton  # 記住目前亮起的是哪一個「點點」

# ==========================================
# 系統初始化 (介面打開的第一時間執行)
# ==========================================
func _ready() -> void:
	# 1. 綁定點擊事件：告訴系統「按下哪個點，就切換到對應的頁面」
	dot1.pressed.connect(func(): switch_page(page1, dot1))
	dot2.pressed.connect(func(): switch_page(page2, dot2))
	dot3.pressed.connect(func(): switch_page(page3, dot3))
	dot4.pressed.connect(func(): switch_page(page4, dot4))
	
	# 2. 綁定滑鼠懸停 (Hover) 的視覺回饋效果
	setup_dot_hover(dot1)
	setup_dot_hover(dot2)
	setup_dot_hover(dot3)
	setup_dot_hover(dot4)
	
	# 3. 開局預設狀態：永遠從第一頁開始看
	current_page = page1
	current_dot = dot1
	page1.show() 
	page2.hide() 
	page3.hide() 
	page4.hide() # 開局先隱藏後面三頁，節省效能
	
	# 4. 根據目前狀態，更新所有點點的明暗顏色
	update_dots_color()
	
	# 5. UI 都架設好後，呼叫大腦把玩家擁有的貼紙發配到畫架上
	load_inventory()

# 🌟 新增：監聽 TAB 鍵關閉貼紙介面，並返回存檔選單
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("notebook"):
		# 尋找藏在背景的存檔主選單，把它叫回來
		for child in get_tree().root.get_children():
			if "SaveMenu" in child.name: 
				child.show() 
				
		# 功成身退，把貼紙介面徹底刪除
		queue_free()
		# 吃掉輸入，避免這個 TAB 鍵又去觸發外面的筆記本
		get_viewport().set_input_as_handled()
# ==========================================
# 視覺回饋：滑鼠滑過點點時的明暗變化
# ==========================================
func setup_dot_hover(dot: TextureButton) -> void:
	# 當滑鼠「碰到」點點時，讓它稍微變亮，提示玩家可以點擊
	dot.mouse_entered.connect(func():
		dot.self_modulate = Color(0.8, 0.8, 0.8, 1.0)
	)
	
	# 當滑鼠「離開」點點時，判斷該恢復成什麼顏色
	dot.mouse_exited.connect(func():
		if dot == current_dot:
			dot.self_modulate = Color.WHITE # 如果是目前正在看的頁面，保持全亮 (白色)
		else:
			dot.self_modulate = Color(1.0, 1.0, 1.0, 0.4) # 如果是其他頁面，恢復成半透明狀態
	)

# ==========================================
# 換頁核心邏輯 (包含淡入淡出的平滑動畫)
# ==========================================
func switch_page(new_page: GridContainer, active_dot: TextureButton) -> void:
	# 防呆機制：如果玩家點的點點就是目前這頁，直接中斷，不重複播動畫
	if new_page == current_page:
		return 
		
	# 記錄新舊狀態，準備交接
	var old_page = current_page
	current_page = new_page
	current_dot = active_dot 

	# 狀態交接後，立刻刷新 4 個點點的明暗顯示
	update_dots_color()

	# --- 建立過場動畫 (Tween) ---
	var tween = create_tween().set_parallel(true)
	
	# 動畫 A：讓舊頁面在 0.15 秒內變透明消失
	tween.tween_property(old_page, "modulate:a", 0.0, 0.15)
	
	# 準備新頁面：先設為完全透明，然後開啟顯示，準備淡入
	new_page.modulate.a = 0.0
	new_page.show()
	
	# 動畫 B：讓新頁面在 0.15 秒內從透明浮現到全亮
	tween.tween_property(new_page, "modulate:a", 1.0, 0.15)
	
	# 關鍵節能：等過場動畫播完後，才真正把舊頁面的顯示狀態關閉 (hide)
	tween.chain().tween_callback(old_page.hide)

# ==========================================
# 狀態更新：統一控制 4 個點點的亮暗
# ==========================================
func update_dots_color() -> void:
	# 先無腦把所有點點設為「未選中」的半透明狀態
	var unselected_color = Color(1.0, 1.0, 1.0, 0.4)
	dot1.self_modulate = unselected_color
	dot2.self_modulate = unselected_color
	dot3.self_modulate = unselected_color
	dot4.self_modulate = unselected_color
	
	# 接著，單獨把目前選中的那個點點「點亮」
	if current_dot:
		current_dot.self_modulate = Color.WHITE

# ==========================================
# 關閉介面邏輯 (右上角的叉叉)
# ==========================================

# ==========================================
# 更新右側資訊面板
# ==========================================
func show_sticker_info(sticker_id: String) -> void:
	if sticker_id == "" or not DataManager.STICKER_DB.has(sticker_id):
		return
		
	# 從大腦撈出這張貼紙的資料
	var data = DataManager.STICKER_DB[sticker_id]
	
	# 1. 更新標題
	info_title.text = data["name"]
	
	# 2. 更新大圖預覽
	preview_img.texture = load(data["texture_path"])
	
	# 3. 更新文案說明 (如果你的 DB 之後加了 "description" 欄位，可以直接替換)
	# 目前先用 type 和 value 拼湊出效果說明
	var effect_text = "功能類型：" + data["type"] + "\n數值影響：" + str(data["value"])
	if data.has("threshold"):
		effect_text += "\n發動條件：HP低於 " + str(data["threshold"] * 100) + "%"
		
	info_desc.text = effect_text




# ==========================================
# 自動召喚貼紙流水線 (4 頁發牌系統)
# ==========================================
func load_inventory() -> void:
	# 發牌前，先讓大腦把背包裡的 ID 照順序排好，畫面才不會亂
	DataManager.owned_stickers.sort()
	var max_per_page: int = 12 
	var current_count: int = 0 
	
	# 遍歷大腦背包裡的每一張貼紙 ID
	for sticker_id in DataManager.owned_stickers:
		var new_sticker = STICKER_ITEM.instantiate()
		new_sticker.setup_sticker(sticker_id) # 把 ID 傳給貼紙，讓它自己抓取圖片與數值
		
		# 🟢 換成這段：只有當滑鼠「左鍵按下」時，才更新右側資訊
		new_sticker.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_sticker_info(sticker_id)
		)
		# 🌟 分頁派發邏輯：滿 12 張就自動塞到下一頁
		if current_count < max_per_page:
			page1.add_child(new_sticker)     
		elif current_count < max_per_page * 2:
			page2.add_child(new_sticker)     
		elif current_count < max_per_page * 3:
			page3.add_child(new_sticker)     
		else:
			# 超過 36 張的全部裝進第四頁
			if page4: # 防呆：確認你有建立 Page4 節點
				page4.add_child(new_sticker) 
			
		current_count += 1

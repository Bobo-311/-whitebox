extends CanvasLayer # StickerUI 貼紙介面主腳本

# ==========================================
# 🌟 貼紙模具載入區
# ==========================================
# 載入我們剛剛做好的「萬用貼紙模具」
# (⚠️ 記得把下面的路徑替換成你 StickerItem.tscn 實際存放的路徑！)
const STICKER_ITEM = preload("res://StickerItem/sticker_item.tscn")

# ==========================================
# 節點抓取區 (自動抓取畫面上的 UI 元件)
# @onready 代表「等畫面都準備好後才抓取」，避免抓不到東西當機
# ==========================================
@onready var close_button: TextureButton = $Easel/CloseButton # 關閉按鈕 (右上角的叉叉)

# (⚠️ 這裡的路徑請依據你實際的節點樹，從左邊拖曳進來替換)
@onready var tab1: TextureButton = $Easel/TabButtons/Tab1 # 第一張便利貼
@onready var tab2: TextureButton = $Easel/TabButtons/Tab2 # 第二張便利貼
@onready var tab3: TextureButton = $Easel/TabButtons/Tab3 # 第三張便利貼

@onready var page1: GridContainer = $Easel/MainLayout/LeftPanel/MarginContainer2/Page1 # 第一頁貼紙櫃
@onready var page2: GridContainer = $Easel/MainLayout/LeftPanel/MarginContainer2/Page2 # 第二頁貼紙櫃
@onready var page3: GridContainer = $Easel/MainLayout/LeftPanel/MarginContainer2/Page3 # 第三頁貼紙櫃

# ==========================================
# 大腦記憶區 (記錄玩家目前的狀態)
# ==========================================
var current_page: GridContainer # 記住目前畫面正在顯示哪一頁的「內容」
var current_tab: TextureButton  # 記住目前玩家點選了哪一張「便利貼」

# ==========================================
# 系統初始化 (當玩家打開這個介面時，第一時間執行的動作)
# ==========================================
func _ready() -> void:
	# 1. 綁定「點擊」便利貼的動作 (不用手動去右邊拉線，用程式碼綁定比較乾淨)
	tab1.pressed.connect(func(): switch_page(page1, tab1))
	tab2.pressed.connect(func(): switch_page(page2, tab2))
	tab3.pressed.connect(func(): switch_page(page3, tab3))
	
	# 2. 綁定便利貼的「滑鼠懸停 (Hover)」效果 (呼叫下面的自訂函數)
	setup_tab_hover(tab1)
	setup_tab_hover(tab2)
	setup_tab_hover(tab3)
	
	# 3. 開局預設狀態：一打開介面，強制顯示第一頁與第一張便利貼
	current_page = page1
	current_tab = tab1
	page1.show() # 顯示第一頁
	page2.hide() # 隱藏第二頁
	page3.hide() # 隱藏第三頁
	
	# 4. 根據目前的狀態，刷新所有便利貼的明暗顏色
	update_tabs_color()
	
	# 🌟 5. 介面都準備好之後，呼叫大腦把玩家擁有的貼紙全部擺上畫架！
	load_inventory()


# ==========================================
# 自訂函數：設定滑鼠滑過便利貼時的變色效果
# ==========================================
func setup_tab_hover(tab: TextureButton) -> void:
	# 當滑鼠「碰到」這張便利貼時
	tab.mouse_entered.connect(func():
		# 讓它變得更暗，提示玩家「這個可以點」
		tab.self_modulate = Color(0.5, 0.5, 0.5)
	)
	
	# 當滑鼠「離開」這張便利貼時
	tab.mouse_exited.connect(func():
		# 檢查這張被離開的便利貼，是不是玩家「現在正在看」的那一頁？
		if tab == current_tab:
			tab.self_modulate = Color.WHITE # 如果是，恢復成全亮 (白色)
		else:
			tab.self_modulate = Color(0.7, 0.7, 0.7) # 如果不是，恢復成微暗狀態 (灰色)
	)


# ==========================================
# 換頁核心邏輯 (負責處理頁面的淡入淡出，與便利貼的切換)
# ==========================================
func switch_page(new_page: GridContainer, active_tab: TextureButton) -> void:
	# 防呆機制：如果玩家點的便利貼，就是現在畫面上顯示的這頁，就甚麼都不做直接結束
	if new_page == current_page:
		return 
		
	# 把原本在看的頁面存起來當作「舊頁面」
	var old_page = current_page
	
	# 把大腦的記憶更新為玩家剛剛點的「新頁面」和「新便利貼」
	current_page = new_page
	current_tab = active_tab 

	# 刷新所有便利貼的顏色 (把舊的變暗，新的變亮)
	update_tabs_color()

	# --- 開始製作淡入淡出 (Crossfade) 動畫 ---
	var tween = create_tween().set_parallel(true)
	
	# 動畫 A：讓「舊頁面」的透明度花 0.15 秒降到 0.0 (完全透明消失)
	tween.tween_property(old_page, "modulate:a", 0.0, 0.15)
	
	# 準備新頁面：先強制把新頁面變完全透明，然後開啟顯示
	new_page.modulate.a = 0.0
	new_page.show()
	
	# 動畫 B：讓「新頁面」的透明度花 0.15 秒升到 1.0 (完全清楚浮現)
	tween.tween_property(new_page, "modulate:a", 1.0, 0.15)
	
	# 動畫 C：等上面動畫播完後，才真正把舊頁面的顯示關閉，節省效能
	tween.chain().tween_callback(old_page.hide)


# ==========================================
# 自訂函數：統一刷新所有便利貼的顏色狀態
# ==========================================
func update_tabs_color() -> void:
	# 先無腦把所有的便利貼都變暗 (設定濾鏡為 0.7 的深灰色)
	tab1.self_modulate = Color(0.7, 0.7, 0.7)
	tab2.self_modulate = Color(0.7, 0.7, 0.7)
	tab3.self_modulate = Color(0.7, 0.7, 0.7)
	
	# 接著，把玩家目前正在看的那張便利貼給「點亮」 (恢復成 1.0 原生顏色)
	if current_tab:
		current_tab.self_modulate = Color.WHITE


# ==========================================
# 關閉按鈕邏輯 (右上角的叉叉)
# ==========================================
func _on_close_button_pressed() -> void:
	# 尋找藏在背景的存檔面板 (大腦記憶選單)
	for child in get_tree().root.get_children():
		# 用名稱包含 "SaveMenu" 來比對，把背景的大選單叫回來
		if "SaveMenu" in child.name: 
			child.show() 
			
	# 功成身退，把這個貼紙介面從遊戲記憶體中徹底刪除
	queue_free()

func _on_close_button_mouse_entered() -> void:
	# 當滑鼠碰到右上角叉叉時，按鈕變暗
	close_button.self_modulate = Color(0.7, 0.7, 0.7) 

func _on_close_button_mouse_exited() -> void:
	# 當滑鼠離開右上角叉叉時，按鈕恢復原本明亮的樣子
	close_button.self_modulate = Color(1.0, 1.0, 1.0)


# ==========================================
# 🌟 自動召喚貼紙流水線 (ID 升級版)
# ==========================================
func load_inventory() -> void:
	# 🌟 新增這行：在發牌之前，先請大腦把背包裡的 ID (001, 004...) 照順序排好！
	DataManager.owned_stickers.sort()
	var max_per_page: int = 12 
	var current_count: int = 0 
	
	# 🌟 改變點 1：現在從大腦拿出來的是純 ID字串 (例如 "001")，不再是路徑了
	for sticker_id in DataManager.owned_stickers:
		
		# 照藍圖生出一個空白貼紙
		var new_sticker = STICKER_ITEM.instantiate()
		
		# 🌟 改變點 2：呼叫貼紙的變身函數，把它該有的 ID 傳給它，讓它自己變身！
		new_sticker.setup_sticker(sticker_id) 
		
		# 分頁邏輯 (跟你原本寫的一模一樣，非常完美)
		if current_count < max_per_page:
			page1.add_child(new_sticker)     
		elif current_count < max_per_page * 2:
			page2.add_child(new_sticker)     
		else:
			page3.add_child(new_sticker)     
			
		current_count += 1

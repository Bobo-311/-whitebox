extends Control
# 素描本主系統 (Notebook UI)
# 負責控制素描本的滑出/收合，以及左側書籤的分頁切換與動畫

var is_open: bool = false
var screen_height: float = 0.0

# ==========================================
# 書籤動畫設定區 (標籤的預設位置與彈出距離)
# ==========================================
var default_tab_x: float = 0.0       # 系統自己記住書籤原本的 X 座標 (對齊的基準線)
const POP_OUT_DISTANCE: float = 30.0 # 書籤被點擊時，往左凸出去的距離 (覺得不夠可以改大)
# [🌟 本次新增] 新增一個大腦變數，專門記住「現在到底哪一頁是被選中的」
var current_active_btn: TextureButton
# ==========================================
# 節點抓取區 (@onready 確保畫面載入完畢才抓)
# ==========================================
# 抓取左側的三個彩色便利貼按鈕 (必須是 TextureButton 才能自動換圖)
@onready var btn_equip: TextureButton = $TabButtons/Btn_Equip
@onready var btn_sticker: TextureButton = $TabButtons/Btn_Sticker
@onready var btn_map: TextureButton = $TabButtons/Btn_Map

# 抓取對應的三個大書頁內容容器
@onready var equip_page = $EquipPage
@onready var sticker_page = $StickerPage
@onready var map_page = $MapPage

# ==========================================
# 遊戲初始化 (_ready) - 遊戲一開局就執行的設定
# ==========================================
func _ready():
	# 1. 算出玩家螢幕的高度，把素描本推到螢幕最下面 (畫面外) 藏起來
	screen_height = get_viewport_rect().size.y
	position.y = screen_height
	# 強制程式「等一幀」，讓 UI 引擎把畫面徹底排版完，我們再去抓座標才不會抓到錯的！
	await get_tree().process_frame
	
	# 2. 記住標籤的原始 X 座標 (以裝備按鈕為基準)
	if btn_equip:
		default_tab_x = btn_equip.position.x
	
	# 3. 綁定三個標籤的點擊事件 (告訴系統按下誰，就要切換到哪一頁、亮哪個按鈕)
	btn_equip.pressed.connect(func(): switch_page(equip_page, btn_equip))
	btn_sticker.pressed.connect(func(): switch_page(sticker_page, btn_sticker))
	btn_map.pressed.connect(func(): switch_page(map_page, btn_map))
	
	# 4. [🌟 修復預設不凸出的問題] 
	# 遊戲剛開始時，呼叫切換頁面功能，並且給一個 true 參數。
	# 代表「不要播動畫，直接瞬間把藍色標籤的圖片跟座標設定成凸出去」。
	switch_page(equip_page, btn_equip, true)
	hide() # 隱藏起來節省系統效能
# ==========================================
# 核心功能：切換書頁 + 圖片替換 + 標籤彈出動畫
# ==========================================
# target_page = 你要打開的頁面 
# active_btn = 你點擊的那個按鈕 
# is_instant = 是否要瞬間切換 (預設是 false 播動畫，只有開局預設那次是 true)
func switch_page(target_page: Control, active_btn: TextureButton, is_instant: bool = false):
	# --- 步驟一：處理中間書頁的顯示與隱藏 ---
	# 先無腦把所有頁面隱藏，確保畫面不會疊在一起
	equip_page.hide()
	sticker_page.hide()
	map_page.hide()
	# 再單獨把玩家指定的目標頁面顯示出來
	target_page.show()
	
	# --- 步驟二：處理標籤的圖片替換 (Normal 與 Disabled) ---
	# 先把所有按鈕的「禁用狀態」解除，讓它們都變回短便利貼 (Normal)，且可以被點擊
	btn_equip.disabled = false
	btn_sticker.disabled = false
	btn_map.disabled = false
	
	# 單獨把「正在看的這一頁」的按鈕給禁用 (Disabled = true)
	# Godot 會自動把它換成你準備好的「長便利貼」，同時防止玩家重複點擊
	active_btn.disabled = true
	
	# --- 步驟三：處理標籤的滑出與縮回位移 ---
	var all_btns = [btn_equip, btn_sticker, btn_map]
	
	if is_instant:
		# 【瞬間切換模式】(給遊戲開局用的)
		# 因為素描本還藏在畫面外，播動畫沒意義。直接把座標寫死，按 Tab 上來時才會是凸的。
		for btn in all_btns:
			if btn == active_btn:
				btn.position.x = default_tab_x - POP_OUT_DISTANCE # 瞬間往左凸出去
			else:
				btn.position.x = default_tab_x # 瞬間縮回去
	else:
		# 【動畫切換模式】(給玩家遊玩時手動點擊用的)
		var tween = create_tween().set_parallel(true) 
		for btn in all_btns:
			if btn == active_btn:
				# 【被點擊的標籤】花 0.2 秒往左抽出 (TRANS_BACK 會有極佳的彈性手感)
				tween.tween_property(btn, "position:x", default_tab_x - POP_OUT_DISTANCE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				# 【沒被點擊的標籤】花 0.2 秒乖乖縮回預設位置 (TRANS_SINE 順順地回去)
				tween.tween_property(btn, "position:x", default_tab_x, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ==========================================
# 筆記本開關總控制 (給 player.gd 呼叫的接口)
# ==========================================
func toggle_notebook():
	if is_open:
		close_notebook()
	else:
		open_notebook()

# ==========================================
# 進場動畫：把素描本從螢幕底下往上滑出來
# ==========================================
func open_notebook():
	is_open = true
	show() # 先開啟顯示，準備播動畫
	
	# 避免 Godot 在呼叫 show() 的時候又雞婆把座標重置，我們打開書時強制再把標籤推出去一次！
	if current_active_btn:
		for btn in [btn_equip, btn_sticker, btn_map]:
			if btn == current_active_btn:
				btn.position.x = default_tab_x - POP_OUT_DISTANCE
			else:
				btn.position.x = default_tab_x

	# 0.3 秒內，Y軸從底部滑到 0 (螢幕頂端)。TRANS_QUART 會有一種「快速滑出，最後慢慢煞車」的高級感
	var tween = create_tween()
	tween.tween_property(self, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# ==========================================
# 退場動畫：把素描本從螢幕中間滑回底下藏起來
# ==========================================
func close_notebook():
	is_open = false
	
	# 0.25 秒內，Y軸滑回螢幕最下方 (screen_height)。TRANS_SINE 會有一種順順掉下去的重力感
	var tween = create_tween()
	tween.tween_property(self, "position:y", screen_height, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 關鍵：一定要等滑落動畫播完，才能執行 hide() 隱藏，否則畫面會直接閃退穿幫
	tween.tween_callback(self.hide)

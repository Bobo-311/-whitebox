extends Control
# ==========================================
# 📖 素描本主系統 (Notebook UI)
# ==========================================
# 這個腳本就像是整本素描本的「封面大腦」。
# 它不管裡面的裝備或道具怎麼運作，只負責三件事：
# 1. 玩家按 Tab 時，整本書從螢幕下面滑出來 / 收回去。
# 2. 玩家點擊左邊的書籤時，切換對應的內頁。
# 3. 處理書籤被點擊時，往左邊「凸出去」的動畫。

var is_open: bool = false
var screen_height: float = 0.0

# ==========================================
# 書籤動畫設定區 (標籤的預設位置與彈出距離)
# ==========================================
var default_tab_x: float = 0.0       # 系統會自己記住書籤原本的 X 座標，當作縮回來的基準線
const POP_OUT_DISTANCE: float = 30.0 # 書籤被點擊時，往左凸出去的距離 (覺得不夠明顯可以把這個數字改大)

# 記住「現在到底哪一頁是被選中的」，用來防呆跟播動畫
var current_active_btn: TextureButton

# ==========================================
# 抓取節點區 (@onready 確保畫面載入完畢才抓)
# ==========================================
# 【注意】這裡已經把刪掉的「獨立貼紙頁」去除了，只留下裝備跟地圖的書籤！
@onready var btn_equip: TextureButton = $TabButtons/Btn_Equip
@onready var btn_map: TextureButton = $TabButtons/Btn_Map

# 抓取對應的大書頁內容容器 (裝備頁、地圖頁)
@onready var equip_page = $EquipPage
@onready var map_page = $MapPage

# ==========================================
# 遊戲初始化 (_ready) - 遊戲剛啟動時的設定
# ==========================================
func _ready():
	# 1. 算出玩家螢幕的高度，然後把整本素描本推到螢幕最下面 (畫面外) 藏起來
	screen_height = get_viewport_rect().size.y
	position.y = screen_height
	
	# 強制程式「等一幀」，讓 UI 引擎把畫面徹底排版完，我們再去抓座標才不會抓錯！
	await get_tree().process_frame
	
	# 2. 記住標籤的原始 X 座標 (以裝備按鈕為基準)
	# 加 if 檢查是為了防呆，確保按鈕真的存在才去抓座標
	if btn_equip:
		default_tab_x = btn_equip.position.x
	
	# 3. 綁定剩下的兩個標籤點擊事件 (告訴系統按下誰，就要切換到哪一頁)
	if btn_equip:
		btn_equip.pressed.connect(func(): switch_page(equip_page, btn_equip))
	if btn_map:
		btn_map.pressed.connect(func(): switch_page(map_page, btn_map))
	
	# 4. 開局預設：直接把畫面切換到裝備頁，而且是「瞬間」切換 (true) 不播動畫
	if btn_equip and equip_page:
		switch_page(equip_page, btn_equip, true)
		
	# 準備完畢，先隱藏起來節省系統效能
	hide() 

# ==========================================
# 核心功能：切換書頁 + 書籤彈出動畫
# ==========================================
# target_page = 你要打開的頁面 
# active_btn = 你點擊的那個書籤按鈕 
# is_instant = 是否要瞬間切換 (預設是 false 播動畫，只有開局預設那次是 true)
func switch_page(target_page: Control, active_btn: TextureButton, is_instant: bool = false):
	# --- 步驟一：處理中間書頁的顯示與隱藏 ---
	# 先無腦把所有頁面隱藏，確保畫面不會疊在一起
	if equip_page: equip_page.hide()
	if map_page: map_page.hide()
	
	# 再單獨把玩家指定的目標頁面顯示出來
	if target_page: target_page.show()
	
	# --- 步驟二：處理標籤的狀態 (Normal 與 Disabled) ---
	# 先把所有按鈕的「禁用狀態」解除，讓它們都可以被點擊 (恢復成短便利貼)
	if btn_equip: btn_equip.disabled = false
	if btn_map: btn_map.disabled = false
	
	# 單獨把「正在看的這一頁」的按鈕給禁用 (Disabled = true)
	# 這樣不僅能防止玩家重複點擊，Godot 還會自動把它換成你設定的 Disabled 圖片 (長便利貼)
	if active_btn: active_btn.disabled = true
	current_active_btn = active_btn
	
	# --- 步驟三：處理標籤的滑出與縮回位移 ---
	# 把現在活著的按鈕裝進清單，方便一起下指令
	var all_btns = []
	if btn_equip: all_btns.append(btn_equip)
	if btn_map: all_btns.append(btn_map)
	
	if is_instant:
		# 【瞬間切換模式】(給遊戲開局用的)
		# 因為開局素描本還藏在畫面外，播動畫玩家也看不到。直接把座標寫死，按 Tab 上來時才會是凸的。
		for btn in all_btns:
			if btn == active_btn:
				btn.position.x = default_tab_x - POP_OUT_DISTANCE # 往左推
			else:
				btn.position.x = default_tab_x # 縮回原位
	else:
		# 【動畫切換模式】(給玩家遊玩時手動點擊用的)
		# set_parallel(true) 代表下面所有的動畫要「同時播放」，而不是排隊播
		var tween = create_tween().set_parallel(true) 
		for btn in all_btns:
			if btn == active_btn:
				# 被點擊的標籤：花 0.2 秒往左抽出。TRANS_BACK 會有極佳的「Q彈」手感！
				tween.tween_property(btn, "position:x", default_tab_x - POP_OUT_DISTANCE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				# 沒被點擊的標籤：花 0.2 秒乖乖縮回預設位置。TRANS_SINE 順順地回去
				tween.tween_property(btn, "position:x", default_tab_x, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ==========================================
# 捷徑防呆：開關筆記本 (主角的 _input 會來呼叫這裡)
# ==========================================
func toggle_notebook(is_instant: bool = false):
	# 如果主角大腦的狀態機說「現在正在看書」 (準備開啟)
	if DataManager.player_node.is_reading_book:
		if is_instant:
			show() # 瞬間顯示，跳過往上滑的動畫
		else:
			open_notebook() # 正常播動畫往上滑
			
	# 如果主角說「現在不看書了」 (準備關閉)
	else:
		if is_instant:
			hide() # 瞬間隱藏，跳過往下滑的動畫
		else:
			close_notebook() # 正常播動畫往下滑

# ==========================================
# 進場動畫：把素描本從螢幕底下往上滑出來
# ==========================================
func open_notebook():
	is_open = true
	show() # 先開啟顯示，否則動畫播了也看不到
	
	# 防呆機制：避免 Godot 在呼叫 show() 的時候雞婆重置座標
	# 我們打開書時，強制再把選中的標籤推出去一次，確保它不會縮回去！
	if current_active_btn:
		var all_btns = []
		if btn_equip: all_btns.append(btn_equip)
		if btn_map: all_btns.append(btn_map)
		
		for btn in all_btns:
			if btn == current_active_btn:
				btn.position.x = default_tab_x - POP_OUT_DISTANCE
			else:
				btn.position.x = default_tab_x

	# 0.3 秒內，Y軸從底部滑到 0 (螢幕頂端)。
	# TRANS_QUART 曲線會有一種「快速滑出，最後慢慢煞車」的高級翻書感。
	var tween = create_tween()
	tween.tween_property(self, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# ==========================================
# 退場動畫：把素描本從螢幕中間滑回底下藏起來
# ==========================================
func close_notebook():
	is_open = false
	
	# 0.25 秒內，Y軸滑回螢幕最下方 (screen_height)。
	# TRANS_SINE 曲線會有一種順順掉下去的重力感。
	var tween = create_tween()
	tween.tween_property(self, "position:y", screen_height, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 最關鍵的一步：一定要等「滑落動畫播完」，才能執行 hide() 把介面徹底隱藏，
	# 否則畫面會直接閃現消失，穿幫！
	tween.tween_callback(self.hide)

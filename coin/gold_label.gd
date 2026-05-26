extends Label # 繼承 Label 節點，讓我們可以控制文字顯示 gold_lable

var display_gold: float = 0.0 # 宣告浮點數：這是一個「假的」顯示數值，用來跑動畫
var lerp_speed: float = 10.0 # 宣告浮點數：數值追趕速度 (越快數字跳越快)

# --- 每幀執行的更新函數 ---
func _process(delta: float): 
	# 🌟 安全檢查：確保數據大腦 DataManager 已經載入成功
	if DataManager == null: 
		return # 如果大腦還沒好，直接跳過這幀，避免報錯
		
	# 抓取 DataManager 裡的真實金幣數量作為目標值
	var target_gold = DataManager.total_gold 
	
	# --- 核心 Lerp 圓滑邏輯 ---
	# 【特殊函數】lerp(目前值, 目標值, 比例)：讓目前值每一幀向目標值移動 10% (依照 delta 同步)
	display_gold = lerp(display_gold, float(target_gold), lerp_speed * delta)
	
	# --- 防止浮點數無限接近的抖動 ---
	# 如果「顯示值」跟「目標值」的差距小於 0.1 像素，就強制讓它們相等
	if abs(display_gold - target_gold) < 0.1:
		display_gold = target_gold
		
	# --- 更新 Label 文字內容 ---
	# 【特殊函數】str() 轉字串、round() 四捨五入成整數
	# 這樣玩家就會看到數字很順滑地從 0 一直跳到 5、10、100
	# ✅ 請改成這樣（在 round 外面再包一層 int）：
	text = str(int(round(display_gold)))

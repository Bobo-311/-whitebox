extends ProgressBar          # 繼承進度條節點

# ==========================================
# ⚙️ 視覺設定與計時器參數
# ==========================================
@export var hide_delay: float = 3.0       # 敵人被打後，血條要顯示多久才開始消失 (3秒)
@export var fade_duration: float = 0.5    # 血條漸隱消失所需的動畫時間 (0.5秒)

var hide_timer: Timer                     # 背景自動倒數的計時器
var current_fade_tween: Tween             # 記錄目前的淡出動畫，方便隨時打斷

# ==========================================
# 🚀 初始化
# ==========================================
func _ready() -> void:
	# 遊戲開局，確保血條是完全透明隱藏的
	modulate.a = 0.0
	
	# 動態生成一個計時器 (不用在編輯器手動加節點，程式自己生)
	hide_timer = Timer.new()
	hide_timer.one_shot = true            # 倒數完就停，不要無限循環
	hide_timer.timeout.connect(_on_hide_timer_timeout) # 綁定時間到的動作
	add_child(hide_timer)                 # 把計時器裝到自己身上

# ==========================================
# 💥 更新血量 (每次敵人被打時，都會呼叫這裡)
# ==========================================
func update_bar(current_hp: int, max_hp: int) -> void:
	self.max_value = max_hp  # 告訴血條最大值是多少
	
	# --- 1. 血量平滑扣減動畫 ---
	var hp_tween = get_tree().create_tween()
	hp_tween.tween_property(self, "value", current_hp, 0.2).set_trans(Tween.TRANS_SINE)
	
	# --- 2. 顯示血條並打斷淡出 ---
	# 如果血條正在慢慢消失，但玩家又補了一刀，立刻打斷消失動畫
	if current_fade_tween and current_fade_tween.is_running():
		current_fade_tween.kill()
		
	# 瞬間把血條變回完全不透明 (顯示)
	modulate.a = 1.0
	
	# --- 3. 重置隱藏計時器 ---
	# 每次被打，3 秒的計時器都會重新從頭算，確保連續攻擊時血條一直亮著
	hide_timer.start(hide_delay)

# ==========================================
# 👻 計時器時間到 (執行淡出隱藏)
# ==========================================
func _on_hide_timer_timeout() -> void:
	# 建立漸隱過場動畫
	current_fade_tween = get_tree().create_tween()
	
	# 讓血條自己的透明度 (modulate:a) 在 0.5 秒內平滑變成 0.0 (完全透明)
	current_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)

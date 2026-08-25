extends Camera2D                 # 繼承鏡頭節點

# ==========================================
# ⚙️ 終極防暈眩滑鼠探頭 (Look-Ahead) 參數
# ==========================================
@export var deadzone_radius: float = 250.0    # 🌟 死區 (250px 內滑鼠隨便繞，鏡頭完全不動)
@export var max_mouse_dist: float = 700.0     # 🌟 滑鼠拉到多遠視為「極限拉遠」
@export var max_look_distance: float = 200.0  # 🌟 探出最大距離
@export var look_smooth_speed: float = 6.0    # 🌟 平滑跟隨速度 (6.0 保持俐落感)

var current_look_offset: Vector2 = Vector2.ZERO # 記憶目前平滑後的探頭偏移

# ==========================================
# ⚙️ 衝擊式 (Trauma) 鏡頭震動參數
# ==========================================
@export var trauma_decay: float = 2.5           # 🌟 震動衰減速度 (2.0~3.0 最佳)
@export var max_shake_offset: Vector2 = Vector2(22.0, 16.0) # 🌟 位移最大像素
@export var max_roll: float = 0.045             # 🌟 畫面最大旋轉角度 (打擊感的靈魂)
@export var trauma_power: float = 2.0           # 🌟 二次方指數衰減 (讓尾震更順滑)

var trauma: float = 0.0                         # 當前衝擊值 (0.0 ~ 1.0)

func _ready() -> void:
	add_to_group("main_camera") # 🌟 加入群組，讓子彈與敵人能隨時全域呼叫震动

# ==========================================
# 🚀 每一幀運算
# ==========================================
func _process(delta: float) -> void:
	# 🌟【關鍵機制】將 delta 除以 Engine.time_scale，還原為真實時間的 delta！
	# 這樣就算 Hitstop 時停 (time_scale 接近 0)，相機衰減與探頭依然能順暢運作
	var real_delta: float = delta / max(Engine.time_scale, 0.001)

# --------------------------------------
	# 1. 計算 Ease-In 漸進式的滑鼠探頭向量
# --------------------------------------
	var target_look = Vector2.ZERO
	
	# 🌟 新增防護網：只有在「沒有播放劇情」的時候，才允許滑鼠探頭
	if DataManager.player_node and not DataManager.player_node.is_in_dialogue:
		var mouse_pos = get_local_mouse_position()
		var mouse_dist = mouse_pos.length()
		
		if mouse_dist > deadzone_radius:
			var raw_t = (mouse_dist - deadzone_radius) / (max_mouse_dist - deadzone_radius)
			raw_t = clamp(raw_t, 0.0, 1.0)
			
			var ease_t = raw_t * raw_t
			target_look = mouse_pos.normalized() * (ease_t * max_look_distance)
	
	# 💡 這個 lerp 留著！這樣劇情一開始，鏡頭就會「平滑地」回到主角正中央
	current_look_offset = current_look_offset.lerp(target_look, look_smooth_speed * real_delta)
	
	# --------------------------------------
	# 2. 計算 Trauma 衝擊震動 (含微量旋轉)
	# --------------------------------------
	var shake_offset = Vector2.ZERO
	var shake_roll = 0.0
	
	if trauma > 0.0:
		# 衝擊值隨真實時間衰減
		trauma = max(trauma - trauma_decay * real_delta, 0.0)
		
		# 使用二次方 (trauma^2) 讓大震動保有爆發力，尾震自然平滑
		var amount = pow(trauma, trauma_power)
		
		shake_roll = max_roll * amount * randf_range(-1.0, 1.0)
		shake_offset = Vector2(
			max_shake_offset.x * amount * randf_range(-1.0, 1.0),
			max_shake_offset.y * amount * randf_range(-1.0, 1.0)
		)
	
	# --------------------------------------
	# 3. 疊加兩者並套用至相機 offset 與 rotation
	# --------------------------------------
	offset = current_look_offset + shake_offset
	rotation = shake_roll

# ==========================================
# 💥 外部呼叫函數
# ==========================================
func apply_shake(strength: float) -> void:
	# 🌟 自動將原本傳入的強度（例如 5.0 ~ 15.0）換算為 0.0 ~ 1.0 的 Trauma 值並自由疊加
	var add_trauma = strength / 15.0
	trauma = min(trauma + add_trauma, 1.0)

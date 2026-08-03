extends Camera2D                 # 繼承鏡頭節點

# ==========================================
# ⚙️ 終極防暈眩滑鼠探頭 (Look-Ahead) 參數
# ==========================================
@export var deadzone_radius: float = 250.0    # 🌟 死區 (200px 內滑鼠隨便繞，鏡頭完全不動)
@export var max_mouse_dist: float = 700.0     # 🌟 滑鼠拉到多遠視為「極限拉遠」
@export var max_look_distance: float = 200.0  # 🌟【修改這行】探出最大距離：調大到 140px，視野看更遠！
@export var look_smooth_speed: float = 6.0    # 🌟 平滑跟隨速度 (6.0 保持俐落感)

var current_look_offset: Vector2 = Vector2.ZERO # 記憶目前平滑後的探頭偏移

# ==========================================
# ⚙️ 鏡頭震動 (Shake) 參數
# ==========================================
var shake_strength: float = 0.0   # 目前震動強度
var shake_decay: float = 20.0    # 震動衰減速度

# ==========================================
# 🚀 每一幀運算
# ==========================================
func _process(delta: float) -> void:
	# --------------------------------------
	# 1. 計算 Ease-In 漸進式的滑鼠探頭向量
	# --------------------------------------
	var mouse_pos = get_local_mouse_position()
	var mouse_dist = mouse_pos.length()
	
	var target_look = Vector2.ZERO
	
	# 只有滑鼠超過死區才開始計算探頭
	if mouse_dist > deadzone_radius:
		# 計算超過死區的比例 (0.0 ~ 1.0)
		var raw_t = (mouse_dist - deadzone_radius) / (max_mouse_dist - deadzone_radius)
		raw_t = clamp(raw_t, 0.0, 1.0)
		
		# 二次方 Ease-In 曲線 (出死區時極度平滑，拉遠時快速延伸)
		var ease_t = raw_t * raw_t
		
		# 計算最終平滑偏移向量
		target_look = mouse_pos.normalized() * (ease_t * max_look_distance)
	
	# 使用 lerp 平滑過渡
	current_look_offset = current_look_offset.lerp(target_look, look_smooth_speed * delta)
	
	# --------------------------------------
	# 2. 計算震動向量 (Shake)
	# --------------------------------------
	var shake_offset = Vector2.ZERO
	if shake_strength > 0:
		shake_offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
		shake_strength = lerp(shake_strength, 0.0, shake_decay * delta)
		
	# --------------------------------------
	# 3. 疊加兩者並套用至相機 offset
	# --------------------------------------
	offset = current_look_offset + shake_offset

# ==========================================
# 💥 外部呼叫函數
# ==========================================
func apply_shake(strength: float) -> void:
	shake_strength = strength

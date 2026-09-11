extends Camera2D                 # 繼承鏡頭節點

# (保留你原本的 Look-Ahead 參數...)
@export var deadzone_radius: float = 250.0    
@export var max_mouse_dist: float = 700.0     
@export var max_look_distance: float = 200.0  
@export var look_smooth_speed: float = 6.0    
var current_look_offset: Vector2 = Vector2.ZERO 

# (保留你原本的 Trauma 參數...)
@export var trauma_decay: float = 2.5           
@export var max_shake_offset: Vector2 = Vector2(22.0, 16.0) 
@export var max_roll: float = 0.045             
@export var trauma_power: float = 2.0           
var trauma: float = 0.0                         

# ==========================================
# 🌟【全新】動態縮放 (Pulse Zoom) 參數
# ==========================================
@export var zoom_recover_speed: float = 6.0     # 🌟 縮放回彈的速度 (彈簧有多緊)
var base_zoom: Vector2 = Vector2.ONE            # 記憶關卡原本設定好的縮放值
var zoom_multiplier: float = 1.0                # 當前的縮放乘數 (大於 1 代表放大)

func _ready() -> void:
	add_to_group("main_camera") 
	# 🌟 記住遊戲剛開始時，編輯器裡設定的 zoom 是多少，這就是相機永遠的「家」
	base_zoom = zoom 

# ==========================================
# 🚀 每一幀運算
# ==========================================
func _process(delta: float) -> void:
	var real_delta: float = delta / max(Engine.time_scale, 0.001)

	# --------------------------------------
	# 1. 計算 Ease-In 漸進式的滑鼠探頭向量 (你原本的邏輯)
	# --------------------------------------
	var mouse_pos = get_local_mouse_position()
	var mouse_dist = mouse_pos.length()
	var target_look = Vector2.ZERO
	
	if mouse_dist > deadzone_radius:
		var raw_t = (mouse_dist - deadzone_radius) / (max_mouse_dist - deadzone_radius)
		raw_t = clamp(raw_t, 0.0, 1.0)
		var ease_t = raw_t * raw_t
		target_look = mouse_pos.normalized() * (ease_t * max_look_distance)
	
	current_look_offset = current_look_offset.lerp(target_look, look_smooth_speed * real_delta)
	
	# --------------------------------------
	# 2. 計算 Trauma 衝擊震動 (你原本的邏輯)
	# --------------------------------------
	var shake_offset = Vector2.ZERO
	var shake_roll = 0.0
	
	if trauma > 0.0:
		trauma = max(trauma - trauma_decay * real_delta, 0.0)
		var amount = pow(trauma, trauma_power)
		shake_roll = max_roll * amount * randf_range(-1.0, 1.0)
		shake_offset = Vector2(
			max_shake_offset.x * amount * randf_range(-1.0, 1.0),
			max_shake_offset.y * amount * randf_range(-1.0, 1.0)
		)
	
	# --------------------------------------
	# 🌟 3. 自我修復的彈簧縮放 (Self-Healing Zoom)
	# --------------------------------------
	# 讓倍率隨時間自動平滑地回到 1.0
	if abs(zoom_multiplier - 1.0) > 0.001:
		zoom_multiplier = lerpf(zoom_multiplier, 1.0, zoom_recover_speed * real_delta)
	else:
		zoom_multiplier = 1.0
		
	# 真正的 zoom = 基準 zoom * 當前的動態倍率
	zoom = base_zoom * zoom_multiplier
	
	# --------------------------------------
	# 4. 疊加套用
	# --------------------------------------
	offset = current_look_offset + shake_offset
	rotation = shake_roll

# ==========================================
# 💥 外部呼叫 API
# ==========================================
func apply_shake(strength: float) -> void:
	var add_trauma = strength / 15.0
	trauma = min(trauma + add_trauma, 1.0)

# 🌟【新增的外部呼叫 API】：動態鏡頭縮放
func apply_zoom_pulse(multiplier: float) -> void:
	# 例如傳入 1.06，鏡頭會瞬間放大，然後在 _process 中自己慢慢彈回原狀
	zoom_multiplier = multiplier

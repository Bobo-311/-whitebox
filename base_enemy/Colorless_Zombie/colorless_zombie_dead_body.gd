extends CharacterBody2D

# ==========================================
# 💣 死後自爆蝌蚪設定 (可在右側 Inspector 面板微調)
# ==========================================
@export_category("💣 自爆蝌蚪炸彈設定")
@export var chase_speed: float = 750.0       # 追擊玩家的速度
@export var explosion_damage: float = 40.0   # 自爆傷害
@export var trigger_distance: float = 40.0   # 距離玩家多近時直接引爆？
@export var fuse_time: float = 3.0           # 🌟【修改設定】：限定 3 秒內沒追到也會強制自爆！

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var timer: Timer = $Timer

var player_node: Node2D = null

# 🔒 狀態鎖與內部變數
var is_exploding: bool = false               # 記錄是否已經點燃引信開始爆炸
var has_damaged_player: bool = false         # 單次傷害鎖：確保一場爆炸只扣一次血
var last_move_dir: Vector2 = Vector2.RIGHT   # 記憶最後移动方向 (決定播 explode_right 還是 explode_left)
var elapsed_time: float = 0.0                # 累積時間：用來計算紅光加速閃爍的頻率

# ==========================================
# 🚀 生命週期初始化
# ==========================================
func _ready():
	if DataManager and DataManager.player_node:
		player_node = DataManager.player_node
	else:
		player_node = get_tree().get_first_node_in_group("player")
	
	# 🌟【限時 3 秒自爆】：把原本的 5 秒改為面板設定的 fuse_time (3.0 秒)
	timer.wait_time = fuse_time
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	
	anim.animation_finished.connect(_on_animation_finished)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# 🌟【階段 1：無害的追跡者】一出生先封印 Hitbox，保證追擊途中碰到身體不會扣血
	_set_hitbox_active(false)
	
	# 初始播放往右移動
	anim.play("move_right")

# ==========================================
# 🔄 物理更新迴圈 (紅光閃爍 + 爆炸影格裁判 + 追蹤玩家)
# ==========================================
func _physics_process(delta: float):
	# 🌟【視覺核心】：持續更新定時炸彈的紅光閃爍 (越接近 3 秒閃越快)
	_update_bomb_red_flash(delta)
	
	# 🌟【階段 3：傷害綻放 (智慧影格監視)】
	if is_exploding:
		if "explode" in anim.animation:
			var current_frame = anim.frame
			var total_frames = anim.sprite_frames.get_frame_count(anim.animation)
			
			# 【正規防呆】：自動判斷你是切「後 6 格純爆炸」還是「全部 12 格」！
			# 如果是 12 格，第 6~9 格開傷害；如果是 6 格，第 0~3 格開傷害！
			var start_hit_frame = 6 if total_frames > 6 else 0
			var end_hit_frame = 9 if total_frames > 6 else 3
			
			if current_frame >= start_hit_frame and current_frame <= end_hit_frame:
				_set_hitbox_active(true)
			else:
				# 🌟【階段 5：煙消雲散】變成地上水窪時關閉傷害判定框
				_set_hitbox_active(false)
				
		return # 爆炸期間停在原地，不執行下面的追蹤邏輯
		
	# --- 以下是還沒爆炸時的追蹤邏輯 ---
	if not player_node:
		return
		
	# 1. 瘋狂追蹤玩家
	var dir = global_position.direction_to(player_node.global_position)
	last_move_dir = dir
	velocity = dir * chase_speed
	move_and_slide()
	
	# 2. 🌟【方向校正】：根據游動方向切換 move_right / move_left 並微調上下角度
	_update_swim_direction(dir)
	
	# 3. 距離判定：一旦進入引爆半徑，立刻自爆
	if global_position.distance_to(player_node.global_position) <= trigger_distance:
		_trigger_explosion()

# ==========================================
# 🔴 定時炸彈紅光系統 (隨 3 秒倒數越閃越急促)
# ==========================================
func _update_bomb_red_flash(delta: float) -> void:
	if not anim: return
	
	elapsed_time += delta
	
	# 當已經炸成黑泥水花時，將顏色洗白回正常原色，不再閃紅光
	if is_exploding:
		var total_frames = anim.sprite_frames.get_frame_count(anim.animation)
		var splash_frame = 6 if total_frames > 6 else 0
		if anim.frame >= splash_frame:
			anim.modulate = Color.WHITE
			return
			
	# 【正規炸彈算法】：根據 0 ~ 3 秒的進度 (progress)，把閃爍速度從 12 漸進拉高到 48！
	var progress = clamp(elapsed_time / fuse_time, 0.0, 1.0)
	var flash_speed = lerp(12.0, 48.0, progress)
	
	# 利用正弦波 (sin) 讓紅光在 0.0 (原色) 與 1.0 (高飽和紅光) 之間急促跳動
	var wave = (sin(elapsed_time * flash_speed) + 1.0) * 0.5
	anim.modulate = Color.WHITE.lerp(Color(3.5, 0.25, 0.25, 1.0), wave)

# ==========================================
# 🎯 游動左右分流與上下角度校正 (防翻肚、防橫飄)
# ==========================================
func _update_swim_direction(dir: Vector2) -> void:
	if dir == Vector2.ZERO: return
	
	# 往右半邊 (含正上、正下)：播 move_right 並轉向目標角度
	if dir.x >= 0:
		if anim.animation != "move_right":
			anim.play("move_right")
		anim.rotation = dir.angle()
	# 往左半邊：播 move_left 並以左向為基準微調上下仰角
	else:
		if anim.animation != "move_left":
			anim.play("move_left")
		anim.rotation = (-dir).angle()

# ==========================================
# 💥 階段 2：點燃引信 (切換左右爆炸動畫)
# ==========================================
func _on_timer_timeout():
	# 3 秒倒數時間到，強制原地自爆
	_trigger_explosion()

func _trigger_explosion():
	if is_exploding: return
	is_exploding = true
	velocity = Vector2.ZERO # 瞬間煞車停在原地
	
	# 🌟【正規接地細節】：爆炸後的黑泥水窪是平鋪在地板上的，
	# 所以引爆瞬間把圖片旋轉角度歸零 (0.0)，防止水窪斜著立在半空中！
	anim.rotation = 0.0
	
	# 根據最後游動方向，決定播放「爆炸右」還是「爆炸左」
	if last_move_dir.x >= 0:
		anim.play("explode_right")
	else:
		anim.play("explode_left")

# ==========================================
# 🛠️ 傷害判定與封印工具區
# ==========================================
func _set_hitbox_active(is_active: bool):
	hitbox.set_deferred("monitoring", is_active)
	hitbox.set_deferred("monitorable", is_active)
	var shape = hitbox.get_node_or_null("CollisionShape2D")
	if shape: 
		shape.set_deferred("disabled", not is_active)

func _on_hitbox_body_entered(body):
	if body.is_in_group("player") or body.name == "player":
		_apply_explosion_damage(body, null)

func _on_hitbox_area_entered(area):
	var parent = area.get_parent()
	if parent and (parent.is_in_group("player") or parent.name == "player"):
		_apply_explosion_damage(parent, area)

func _apply_explosion_damage(target: Node2D, target_area: Area2D = null):
	# 🌟【階段 4：單次傷害鎖】確保一場爆炸只扣一次血
	if has_damaged_player: return 
	has_damaged_player = true
	
	var knockback_dir = global_position.direction_to(target.global_position)
	if target_area and target_area.has_method("take_damage"):
		target_area.take_damage(explosion_damage, global_position, knockback_dir, false, 3.0) 
	elif target.has_method("take_damage"):
		target.take_damage(explosion_damage, global_position, knockback_dir, false, 3.0)

# 爆炸動畫播完就刪除自己
func _on_animation_finished():
	if "explode" in anim.animation:
		queue_free()

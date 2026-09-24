extends Node2D

# ==========================================
# 📊 [雷射武器參數] (可於右側 Inspector 調整)
# ==========================================
@export_group("雷射傷害設定")
@export var laser_damage: float = 30.0 # 雷射傷害通常極高

@export_group("雷射旋轉動力學")
@export var min_speed: float = 20.0     # 剛發射時的慢轉速 (度/秒)
@export var max_speed: float = 220.0    # 最終掃場狂暴轉速 (度/秒)
@export var acceleration: float = 100.0 # 加速度 (每秒增加多少轉速)

# ==========================================
# ⚙️ [系統狀態與節點綁定]
# ==========================================
var is_firing: bool = false
var is_clockwise: bool = true
var current_speed: float = 0.0 # 當前即時轉速

@onready var laser_hitbox = $LaserHitbox
@onready var hitbox_collision = $LaserHitbox/CollisionShape2D
@onready var visual_line = $LaserHitbox/Line2D

# ==========================================
# 🌱 初始化與物理更新
# ==========================================
func _ready() -> void:
	# 綁定命中玩家時的訊號 (代替手動拉線)
	laser_hitbox.area_entered.connect(_on_laser_hit_player)
	_reset_laser()

func _process(delta: float) -> void:
	# 如果沒在發射，就什麼都不做
	if not is_firing: return
	
	# 🌟【3A 級加速度邏輯】
	# 每經過一幀，就根據 delta 增加轉速，直到達到極速
	current_speed += acceleration * delta
	current_speed = min(current_speed, max_speed)
	
	# 執行旋轉
	if is_clockwise:
		rotation_degrees += current_speed * delta
	else:
		rotation_degrees -= current_speed * delta

# ==========================================
# 📡 [公開 API] 供 Boss 的 AnimationPlayer 呼叫
# ==========================================
func fire_laser(clockwise: bool) -> void:
	# 1. 初始化狀態：一律從 Boss 正下方 (90度) 開始掃
	rotation_degrees = 90.0 
	is_clockwise = clockwise
	current_speed = min_speed # 從最慢速起步
	
	# 2. 啟動【預警階段】(細線、半透明、無傷害)
	visual_line.visible = true
	visual_line.width = 5.0
	visual_line.default_color = Color(1.0, 0.0, 0.0, 0.5) 
	hitbox_collision.set_deferred("disabled", true) 
	
	# 3. 啟動【致命變身】(利用 Tween 實作 0.5 秒變粗)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(visual_line, "width", 40.0, 0.5)
	tween.tween_property(visual_line, "default_color", Color(1.0, 0.0, 0.0, 1.0), 0.5)
	
	# 4. 0.5 秒變身完成後，正式解鎖旋轉與傷害判定！
	tween.finished.connect(func():
		is_firing = true
		if is_instance_valid(hitbox_collision):
			hitbox_collision.set_deferred("disabled", false)
	)

func stop_laser() -> void:
	_reset_laser()

func _reset_laser() -> void:
	is_firing = false
	visual_line.visible = false
	hitbox_collision.set_deferred("disabled", true)

# ==========================================
# 💥 命中判定
# ==========================================
func _on_laser_hit_player(area: Area2D) -> void:
	# 確認撞到的是有扣血機制的目標
	if area.has_method("take_damage"):
		# ⚠️ 注意：因為雷射是持續接觸的，玩家的 take_damage 函數必須自帶 I-frames (無敵幀)，
		# 否則玩家會在一秒內被觸發 60 次傷害而瞬間死亡！
		area.take_damage(laser_damage)

extends Node2D

# ==========================================
# 📊 [武器運作參數]
# ==========================================
# ⚠️ 必須在 Inspector 中將 BossBullet.tscn 拖入此欄位，建立依賴注入
@export var bullet_scene: PackedScene 

@export var rotation_speed: float = 120.0 # 槍管旋轉角速度 (度/秒)
@export var fire_rate: float = 0.15      # 射擊間隔 (秒/發)

# ==========================================
# ⚙️ [系統狀態與節點綁定]
# ==========================================
var is_firing_clockwise: bool = false
var is_firing_counter: bool = false
var fire_timer: float = 0.0 # 射速累計器

# 綁定場景樹中的旋轉軸心與槍口
@onready var pivot_cw = $Pivot_Clockwise
@onready var pivot_ccw = $Pivot_Counter
@onready var muzzle_cw = $Pivot_Clockwise/Muzzle
@onready var muzzle_ccw = $Pivot_Counter/Muzzle

# ==========================================
# 🔄 [核心運作迴圈] (每幀更新)
# ==========================================
func _process(delta: float) -> void:
	# 1. 執行槍管旋轉 (帶動子節點 Muzzle 進行圓周運動)
	if is_firing_clockwise:
		pivot_cw.rotation_degrees += rotation_speed * delta
	if is_firing_counter:
		pivot_ccw.rotation_degrees -= rotation_speed * delta
		
	# 2. 射速計時與實體生成
	if is_firing_clockwise or is_firing_counter:
		fire_timer += delta
		if fire_timer >= fire_rate:
			fire_timer = 0.0 # 幀重置
			
			if is_firing_clockwise: 
				_spawn_bullet_at(muzzle_cw)
			if is_firing_counter: 
				_spawn_bullet_at(muzzle_ccw)

# ==========================================
# 📦 [工廠模式：實體生成]
# ==========================================
func _spawn_bullet_at(muzzle: Node2D) -> void:
	if not bullet_scene: return
	
	var bullet = bullet_scene.instantiate()
	
	# 對齊 Transform 矩陣 (繼承槍口的位置與角度)
	bullet.global_position = muzzle.global_position
	bullet.global_rotation = muzzle.global_rotation
	
	# 【強制解耦 (Decoupling)】
	# 將子彈掛載至全域場景 (current_scene)，使其脫離 Boss 的父子節點樹。
	# 避免 Boss 的位移或死亡連帶影響已發射的彈幕軌跡。
	get_tree().current_scene.add_child(bullet)

# ==========================================
# 📡 [公共 API (Public Methods)] 供外部大腦呼叫
# ==========================================
func start_clockwise() -> void:
	is_firing_counter = false # 先強制關閉逆時針
	is_firing_clockwise = true
	fire_timer = 0.0 

func start_counter_clockwise() -> void:
	is_firing_clockwise = false # 先強制關閉順時針
	is_firing_counter = true
	fire_timer = 0.0

func stop_all() -> void:
	is_firing_clockwise = false
	is_firing_counter = false

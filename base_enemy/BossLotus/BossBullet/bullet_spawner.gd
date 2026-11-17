
extends Node2D

# ============================================================
# 淵獄蓮華 - 彈幕生成控制器
#
# 負責：
# 1. 順時針槍管旋轉
# 2. 逆時針槍管旋轉
# 3. 按照固定射速生成 BossBullet
# 4. 將子彈獨立掛載至目前遊戲場景
#
# 保留原本 BossLotus 呼叫的公共 API
# ============================================================


# ============================================================
# 1. 彈幕運作參數
# ============================================================

@export_group("彈幕 - 運作參數")

@export var bullet_scene: PackedScene

@export_range(0.0, 720.0, 1.0)
var rotation_speed: float = 120.0

@export_range(0.01, 2.0, 0.01)
var fire_rate: float = 0.08


# ============================================================
# 2. 系統狀態
# ============================================================

var is_firing_clockwise: bool = false
var is_firing_counter: bool = false

var fire_timer: float = 0.0


# ============================================================
# 3. 節點參照
# ============================================================

@onready var pivot_cw: Node2D = $Pivot_Clockwise
@onready var pivot_ccw: Node2D = $Pivot_Counter

@onready var muzzle_cw: Node2D = $Pivot_Clockwise/Muzzle
@onready var muzzle_ccw: Node2D = $Pivot_Counter/Muzzle


# ============================================================
# 4. 每幀更新
# ============================================================

func _process(delta: float) -> void:

	# -----------------------------
	# 槍管旋轉
	# -----------------------------

	if is_firing_clockwise:

		pivot_cw.rotation_degrees += (
			rotation_speed * delta
		)

	if is_firing_counter:

		pivot_ccw.rotation_degrees -= (
			rotation_speed * delta
		)

	# -----------------------------
	# 沒有射擊時不計時
	# -----------------------------

	if not is_firing_clockwise and not is_firing_counter:
		return

	# -----------------------------
	# 射速計時
	# -----------------------------

	fire_timer += delta

	var interval: float = maxf(fire_rate, 0.01)

	while fire_timer >= interval:

		fire_timer -= interval

		if is_firing_clockwise:
			_spawn_bullet_at(muzzle_cw)

		if is_firing_counter:
			_spawn_bullet_at(muzzle_ccw)


# ============================================================
# 5. 生成子彈
#
# 子彈獨立存在於目前遊戲場景
# 不會受到 Boss 移動或死亡影響
# ============================================================

func _spawn_bullet_at(muzzle: Node2D) -> void:

	if bullet_scene == null:
		return

	var instance: Node = bullet_scene.instantiate()

	var bullet := instance as Node2D

	if bullet == null:

		instance.free()

		push_error("BossBullet 必須繼承 Node2D！")

		return

	var scene_root: Node = get_tree().current_scene

	if scene_root == null:

		bullet.free()

		push_error("目前沒有有效的遊戲場景！")

		return

	# 先加入場景樹
	scene_root.add_child(bullet)

	# 再設定全域位置與方向
	bullet.global_position = muzzle.global_position

	bullet.global_rotation = muzzle.global_rotation


# ============================================================
# 6. 公共 API
# ============================================================

# 順時針發射
func start_clockwise() -> void:

	is_firing_counter = false

	is_firing_clockwise = true

	fire_timer = 0.0


# 逆時針發射
func start_counter_clockwise() -> void:

	is_firing_clockwise = false

	is_firing_counter = true

	fire_timer = 0.0


# 停止所有發射
func stop_all() -> void:

	is_firing_clockwise = false

	is_firing_counter = false

	fire_timer = 0.0

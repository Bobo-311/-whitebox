
extends Node2D

# ============================================================
# 淵獄蓮華 - 雷射武器控制器 v5.2
#
# 功能：
# 1. 雷射由 Boss 正下方開始
# 2. 先顯示半透明紅線預警
# 3. 預警結束後啟動傷害與旋轉
# 4. 旋轉速度由慢到快
# 5. 支援順時針及逆時針
# 6. 停止時取消尚未完成的 Tween
# 7. 支援同一道雷射命中次數控制
#
# 與 Boss v5.2 的 A/B 時間軸相容
# ============================================================


# ============================================================
# 1. 雷射傷害設定
# ============================================================

@export_group("雷射 - 傷害設定")

@export_range(0.0, 200.0, 1.0)
var laser_damage: float = 30.0

# 0 = 每次雷射對同一個 Hurtbox 只造成一次傷害
# 大於 0 = 持續接觸時，按照設定秒數再次傷害
#
# 第二隻 Boss 建議先保留 0
@export_range(0.0, 5.0, 0.1)
var repeat_hit_interval: float = 0.0


# ============================================================
# 2. 雷射旋轉速度
# ============================================================

@export_group("雷射 - 旋轉動力學")

@export_range(0.0, 360.0, 1.0)
var min_speed: float = 20.0

@export_range(0.0, 720.0, 1.0)
var max_speed: float = 220.0

@export_range(0.0, 500.0, 1.0)
var acceleration: float = 100.0

# 預設發射角度
# 90 度代表朝正下方
@export_range(0.0, 360.0, 1.0)
var start_angle: float = 90.0


# ============================================================
# 3. 雷射預警效果
# ============================================================

@export_group("雷射 - 預警與外觀")

# 未指定時間時使用的預設值
@export_range(0.1, 3.0, 0.05)
var default_warning_duration: float = 0.5

@export_range(1.0, 100.0, 1.0)
var warning_width: float = 5.0

@export_range(1.0, 200.0, 1.0)
var active_width: float = 40.0

@export var warning_color: Color = Color(
	1.0, 0.0, 0.0, 0.5
)

@export var active_color: Color = Color(
	1.0, 0.0, 0.0, 1.0
)


# ============================================================
# 4. 內部狀態
# ============================================================

var is_firing: bool = false
var is_clockwise: bool = true

var current_speed: float = 0.0

# 雷射預警的 Tween
var _warning_tween: Tween

# 每次開啟或停止雷射都更新版本號
# 舊版 Tween 回呼不能啟動新版雷射
var _cast_id: int = 0

# 已被本次雷射傷害過的目標
var _hit_targets: Dictionary = {}

# 持續傷害模式的冷卻紀錄
var _hit_cooldowns: Dictionary = {}


# ============================================================
# 5. 節點參照
#
# 保留原本 LaserWeapon 的節點結構
# ============================================================

@onready var laser_hitbox: Area2D = $LaserHitbox

@onready var hitbox_collision: CollisionShape2D = (
	$LaserHitbox/CollisionShape2D
)

@onready var visual_line: Line2D = (
	$LaserHitbox/Line2D
)


# ============================================================
# 6. 初始化
# ============================================================

func _ready() -> void:

	# 保留 Area2D 的命中事件
	if not laser_hitbox.area_entered.is_connected(
		_on_laser_hit_player
	):
		laser_hitbox.area_entered.connect(
			_on_laser_hit_player
		)

	_reset_laser()


# ============================================================
# 7. 物理更新
#
# 使用 _physics_process()
# 讓雷射旋轉與碰撞偵測使用相同更新節奏
# ============================================================

func _physics_process(delta: float) -> void:

	if not is_firing:
		return

	# 旋轉速度逐漸增加
	current_speed += acceleration * delta

	current_speed = minf(
		current_speed,
		maxf(min_speed, max_speed)
	)

	# 順時針 / 逆時針旋轉
	var direction: float = 1.0

	if not is_clockwise:
		direction = -1.0

	rotation_degrees += (
		current_speed * delta * direction
	)

	# -------------------------------------
	# 持續傷害模式：更新冷卻倒數
	# -------------------------------------
	if repeat_hit_interval > 0.0:

		for target_id in _hit_cooldowns.keys():

			var remaining: float = (
				float(_hit_cooldowns[target_id]) - delta
			)

			_hit_cooldowns[target_id] = maxf(
				remaining,
				0.0
			)

	# -------------------------------------
	# 檢查目前與雷射重疊的 Hurtbox
	#
	# 避免玩家在雷射啟用瞬間
	# 已經位於雷射內，卻沒收到 area_entered
	# -------------------------------------
	for area in laser_hitbox.get_overlapping_areas():

		_try_damage_area(area)


# ============================================================
# 8. 開始雷射
#
# Boss 呼叫：
#
# fire_laser(false, 0.5)
# 逆時針 + 0.5 秒預警
#
# fire_laser(true, 0.5)
# 順時針 + 0.5 秒預警
#
# warning_seconds = -1 時使用預設預警時間
# ============================================================

func fire_laser(
	clockwise: bool,
	warning_seconds: float = -1.0
) -> void:

	# 先中斷任何舊雷射
	# 確保不會有多個預警 Tween 同時執行
	_reset_laser()

	var this_cast_id: int = _cast_id

	is_clockwise = clockwise

	rotation_degrees = start_angle
	current_speed = min_speed

	var duration: float = default_warning_duration

	if warning_seconds >= 0.0:
		duration = maxf(warning_seconds, 0.01)

	# -------------------------------------
	# 預警階段：
# 只顯示紅線，不造成傷害
	# -------------------------------------
	visual_line.visible = true
	visual_line.width = warning_width
	visual_line.default_color = warning_color

	is_firing = false

	hitbox_collision.set_deferred(
		"disabled",
		true
	)

	# -------------------------------------
	# 紅線變粗並逐漸變成實體雷射
	# -------------------------------------
	_warning_tween = create_tween().set_parallel(true)

	_warning_tween.tween_property(
		visual_line,
		"width",
		active_width,
		duration
	)

	_warning_tween.tween_property(
		visual_line,
		"default_color",
		active_color,
		duration
	)

	# -------------------------------------
	# 預警 Tween 完成後才啟動傷害
	#
	# 使用版本號檢查：
	# 如果中途 stop_laser()，
	# 舊版回呼就算執行也不會重新開火
	# -------------------------------------
	_warning_tween.finished.connect(
		func():

			if not is_inside_tree():
				return

			if this_cast_id != _cast_id:
				return

			is_firing = true

			hitbox_collision.set_deferred(
				"disabled",
				false
			)
	)


# ============================================================
# 9. 停止雷射
#
# Boss 每次掃射結束時呼叫
# ============================================================

func stop_laser() -> void:
	_reset_laser()


# ============================================================
# 10. 重置雷射
#
# 重要：
# 必須先取消舊 Tween
# 避免在 Boss 轉階、死亡或切換模式後
# 之前的延遲回呼重新啟動雷射
# ============================================================

func _reset_laser() -> void:

	# 使舊版回呼失效
	_cast_id += 1

	# 停止預警 Tween
	if _warning_tween and _warning_tween.is_running():
		_warning_tween.kill()

	_warning_tween = null

	is_firing = false
	current_speed = 0.0

	# 清空本次命中資料
	_hit_targets.clear()
	_hit_cooldowns.clear()

	# 隱藏雷射
	visual_line.visible = false

	# 關閉傷害碰撞
	hitbox_collision.set_deferred(
		"disabled",
		true
	)


# ============================================================
# 11. Area2D 命中事件
#
# 新目標進入雷射時嘗試造成傷害
# ============================================================

func _on_laser_hit_player(area: Area2D) -> void:

	_try_damage_area(area)


# ============================================================
# 12. 統一傷害判定
#
# 預設每次雷射對同一個 Hurtbox 只造成一次傷害
#
# 若 repeat_hit_interval > 0，
# 則改為指定秒數後可以再次傷害
# ============================================================

func _try_damage_area(area: Area2D) -> void:

	# 預警階段不造成傷害
	if not is_firing:
		return

	if not is_instance_valid(area):
		return

	# 只處理具有 take_damage() 的 Hurtbox
	if not area.has_method("take_damage"):
		return

	var target_id: int = area.get_instance_id()

	# -------------------------------------
	# 模式一：每道雷射只傷害一次
	# -------------------------------------
	if repeat_hit_interval <= 0.0:

		if _hit_targets.has(target_id):
			return

		_hit_targets[target_id] = true

	# -------------------------------------
	# 模式二：持續接觸定時傷害
	# -------------------------------------
	else:

		var cooldown: float = float(
			_hit_cooldowns.get(target_id, 0.0)
		)

		if cooldown > 0.0:
			return

		_hit_cooldowns[target_id] = repeat_hit_interval

	# 交給玩家 Hurtbox 轉發傷害
	area.take_damage(laser_damage)

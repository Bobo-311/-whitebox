
extends Node2D

# ============================================================
# 眠境 RE:RECOLOR
# 淵獄蓮華 - 雷射武器控制器
#
# 節點結構：
#
# LaserWeapon
# └── LaserHitbox
#     ├── CollisionShape2D
#     └── LaserSprite
#
# LaserWeapon 位於 Boss 中央。
# Sprite 與 CollisionShape2D 共用相同中心位置。
# ============================================================


# ============================================================
# 1. 傷害設定
# ============================================================

@export_group("雷射 - 傷害設定")

@export_range(0.0, 200.0, 1.0)
var laser_damage: float = 30.0

# 0 = 每次雷射只傷害同一個目標一次
# 大於 0 = 持續接觸時定時造成傷害
@export_range(0.0, 5.0, 0.1)
var repeat_hit_interval: float = 0.0


# ============================================================
# 2. 旋轉設定
# ============================================================

@export_group("雷射 - 旋轉設定")

@export_range(0.0, 360.0, 1.0)
var min_speed: float = 20.0

@export_range(0.0, 720.0, 1.0)
var max_speed: float = 220.0

@export_range(0.0, 500.0, 1.0)
var acceleration: float = 100.0

# 90 度 = 朝正下方
@export_range(0.0, 360.0, 1.0)
var start_angle: float = 90.0


# ============================================================
# 3. 雷射外觀設定
# ============================================================

@export_group("雷射 - 外觀設定")

# 雷射總長度
@export_range(128.0, 2000.0, 16.0)
var beam_length: float = 1400.0

# 碰撞框厚度
@export_range(8.0, 128.0, 1.0)
var hitbox_width: float = 56.0

# 預警透明度
@export_range(0.05, 1.0, 0.05)
var warning_alpha: float = 0.45

# 預警厚度倍率
@export_range(0.1, 6.0, 0.1)
var warning_thickness_scale: float = 1.5

# 正式攻擊厚度倍率
@export_range(0.5, 8.0, 0.1)
var active_thickness_scale: float = 4.0

# 預警時間
@export_range(0.1, 3.0, 0.05)
var default_warning_duration: float = 0.5

# 動畫播放速度
@export_range(0.1, 5.0, 0.1)
var laser_animation_speed: float = 1.0

# SpriteFrames 動畫名稱
@export var laser_animation: StringName = &"beam"


# ============================================================
# 4. 節點參照
# ============================================================

@onready var laser_hitbox: Area2D = $LaserHitbox

@onready var hitbox_collision: CollisionShape2D = (
	$LaserHitbox/CollisionShape2D
)

@onready var laser_sprite: AnimatedSprite2D = (
	$LaserHitbox/LaserSprite
)


# ============================================================
# 5. 內部狀態
# ============================================================

var is_firing: bool = false
var is_clockwise: bool = true

var current_speed: float = 0.0

var _beam_scale_x: float = 1.0

var _warning_tween: Tween

var _cast_id: int = 0

# 本次攻擊已經命中的目標
var _hit_targets: Dictionary = {}

# 持續傷害冷卻
var _hit_cooldowns: Dictionary = {}


# ============================================================
# 6. 初始化
# ============================================================

func _ready() -> void:

	if laser_hitbox == null:
		push_error("找不到 LaserHitbox")
		return

	if hitbox_collision == null:
		push_error("找不到 CollisionShape2D")
		return

	if laser_sprite == null:
		push_error("找不到 LaserSprite")
		return

	# 建立雷射幾何位置
	if not _setup_beam_geometry():
		return

	# 命中事件
	if not laser_hitbox.area_entered.is_connected(
		_on_laser_hit_player
	):
		laser_hitbox.area_entered.connect(
			_on_laser_hit_player
		)

	# 初始化狀態
	_reset_laser()


# ============================================================
# 7. 自動建立雷射位置及碰撞區域
# ============================================================

func _setup_beam_geometry() -> bool:

	var frames: SpriteFrames = laser_sprite.sprite_frames

	if frames == null:
		push_error("LaserSprite 尚未設定 SpriteFrames")
		return false

	if not frames.has_animation(laser_animation):
		push_error("找不到雷射動畫：" + String(laser_animation))
		return false

	if frames.get_frame_count(laser_animation) <= 0:
		push_error("雷射動畫沒有影格")
		return false

	# 取得第一格圖片尺寸
	var frame_texture: Texture2D = (
		frames.get_frame_texture(laser_animation, 0)
	)

	if frame_texture == null:
		push_error("無法取得雷射動畫圖片")
		return false

	var frame_size: Vector2 = frame_texture.get_size()

	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		push_error("雷射圖片尺寸不正確")
		return false

	# --------------------------------------------------------
	# A. LaserHitbox
	# --------------------------------------------------------

	# 碰撞容器位於 Boss 中央
	laser_hitbox.position = Vector2.ZERO
	laser_hitbox.rotation = 0.0
	laser_hitbox.scale = Vector2.ONE

	# --------------------------------------------------------
	# B. LaserSprite
	# --------------------------------------------------------

	# 以圖片中心作為節點中心
	laser_sprite.centered = true

	# Sprite 中心與碰撞框中心相同
	laser_sprite.position = Vector2(
		beam_length * 0.5,
		0.0
	)

	# 計算水平縮放比例
	_beam_scale_x = beam_length / frame_size.x

	# 水平填滿雷射長度
	# 垂直依照外觀倍率放大
	laser_sprite.scale = Vector2(
		_beam_scale_x,
		active_thickness_scale
	)

	laser_sprite.animation = laser_animation
	laser_sprite.speed_scale = laser_animation_speed

	laser_sprite.visible = false

	# --------------------------------------------------------
	# C. CollisionShape2D
	# --------------------------------------------------------

	# 確認碰撞形狀為矩形
	var rectangle: RectangleShape2D = (
		hitbox_collision.shape as RectangleShape2D
	)

	if rectangle == null:
		rectangle = RectangleShape2D.new()
	else:
		# 建立獨立資源，避免修改共用碰撞形狀
		rectangle = rectangle.duplicate() as RectangleShape2D

	hitbox_collision.shape = rectangle

	# 碰撞框長度及厚度
	rectangle.size = Vector2(
		beam_length,
		hitbox_width
	)

	# 碰撞中心與 Sprite 中心完全一致
	hitbox_collision.position = Vector2(
		beam_length * 0.5,
		0.0
	)

	hitbox_collision.rotation = 0.0
	hitbox_collision.scale = Vector2.ONE

	# 初始關閉碰撞
	hitbox_collision.set_deferred(
		"disabled",
		true
	)

	return true


# ============================================================
# 8. 每幀更新
# ============================================================

func _physics_process(delta: float) -> void:

	if not is_firing:
		return

	# 逐漸增加旋轉速度
	current_speed += acceleration * delta

	current_speed = minf(
		current_speed,
		maxf(min_speed, max_speed)
	)

	# 順時針 / 逆時針
	var direction: float = 1.0

	if not is_clockwise:
		direction = -1.0

	rotation_degrees += (
		current_speed * delta * direction
	)

	# 更新持續傷害冷卻
	if repeat_hit_interval > 0.0:

		for target_id in _hit_cooldowns.keys():

			var remaining: float = (
				float(_hit_cooldowns[target_id]) - delta
			)

			_hit_cooldowns[target_id] = maxf(
				remaining,
				0.0
			)

	# 檢查目前重疊的 Hurtbox
	for area in laser_hitbox.get_overlapping_areas():

		_try_damage_area(area)


# ============================================================
# 9. 開始雷射
#
# fire_laser(true)  = 順時針
# fire_laser(false) = 逆時針
#
# 可選擇預警時間
# ============================================================

func fire_laser(
	clockwise: bool,
	warning_seconds: float = -1.0
) -> void:

	# 清除舊攻擊
	_reset_laser()

	var this_cast_id: int = _cast_id

	is_clockwise = clockwise

	rotation_degrees = start_angle
	current_speed = min_speed

	var duration: float = default_warning_duration

	if warning_seconds >= 0.0:
		duration = maxf(warning_seconds, 0.01)

	# --------------------------------------------------------
	# 預警階段
	# --------------------------------------------------------

	laser_sprite.visible = true
	laser_sprite.frame = 0

	laser_sprite.speed_scale = laser_animation_speed
	laser_sprite.play(laser_animation)

	# 先顯示細雷射
	laser_sprite.scale = Vector2(
		_beam_scale_x,
		warning_thickness_scale
	)

	laser_sprite.modulate = Color(
		1.0,
		1.0,
		1.0,
		warning_alpha
	)

	# 預警期間關閉傷害
	is_firing = false

	hitbox_collision.set_deferred(
		"disabled",
		true
	)

	# --------------------------------------------------------
	# 預警結束後逐漸加粗、變亮
	# --------------------------------------------------------

	_warning_tween = create_tween()

	_warning_tween.set_parallel(true)

	_warning_tween.set_trans(Tween.TRANS_SINE)
	_warning_tween.set_ease(Tween.EASE_OUT)

	_warning_tween.tween_property(
		laser_sprite,
		"scale:y",
		active_thickness_scale,
		duration
	)

	_warning_tween.tween_property(
		laser_sprite,
		"modulate:a",
		1.0,
		duration
	)

	# 預警完成
	_warning_tween.finished.connect(
		_on_warning_finished.bind(this_cast_id)
	)


# ============================================================
# 10. 預警結束
# ============================================================

func _on_warning_finished(
	cast_id: int
) -> void:

	# 防止舊 Tween 重新啟動雷射
	if not is_inside_tree():
		return

	if cast_id != _cast_id:
		return

	_warning_tween = null

	laser_sprite.scale.y = active_thickness_scale
	laser_sprite.modulate = Color.WHITE

	# 正式開始攻擊
	is_firing = true

	hitbox_collision.set_deferred(
		"disabled",
		false
	)


# ============================================================
# 11. 停止雷射
# ============================================================

func stop_laser() -> void:

	_reset_laser()


# ============================================================
# 12. 重置雷射
# ============================================================

func _reset_laser() -> void:

	# 使舊 Tween 失效
	_cast_id += 1

	# 停止預警動畫
	if _warning_tween != null:

		if _warning_tween.is_running():
			_warning_tween.kill()

		_warning_tween = null

	is_firing = false
	current_speed = 0.0

	# 清除命中紀錄
	_hit_targets.clear()
	_hit_cooldowns.clear()

	# 關閉視覺動畫
	if laser_sprite != null:

		laser_sprite.stop()
		laser_sprite.visible = false

		laser_sprite.modulate = Color.WHITE

		laser_sprite.scale = Vector2(
			_beam_scale_x,
			active_thickness_scale
		)

	# 關閉碰撞
	if hitbox_collision != null:

		hitbox_collision.set_deferred(
			"disabled",
			true
		)


# ============================================================
# 13. Area2D 命中事件
# ============================================================

func _on_laser_hit_player(area: Area2D) -> void:

	_try_damage_area(area)


# ============================================================
# 14. 統一傷害判定
# ============================================================

func _try_damage_area(area: Area2D) -> void:

	# 預警階段不造成傷害
	if not is_firing:
		return

	if not is_instance_valid(area):
		return

	# 只處理有 take_damage() 的 Hurtbox
	if not area.has_method("take_damage"):
		return

	var target_id: int = area.get_instance_id()

	# --------------------------------------------------------
	# 單次傷害模式
	# --------------------------------------------------------

	if repeat_hit_interval <= 0.0:

		if _hit_targets.has(target_id):
			return

		_hit_targets[target_id] = true

	# --------------------------------------------------------
	# 持續傷害模式
	# --------------------------------------------------------

	else:

		var cooldown: float = float(
			_hit_cooldowns.get(target_id, 0.0)
		)

		if cooldown > 0.0:
			return

		_hit_cooldowns[target_id] = repeat_hit_interval

	# 傳遞傷害
	area.take_damage(laser_damage)

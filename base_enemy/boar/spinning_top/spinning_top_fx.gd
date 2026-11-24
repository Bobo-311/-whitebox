extends Node2D
class_name SpinningTopFX

# ============================================================
# 【失色陀螺怪 - 戰鬥特效控制器】
#
# 負責：
# 1. 蓄力危險提示
# 2. 高速旋轉揚塵
# 3. 撞牆碎屑粒子
#
# 本腳本只管理視覺效果，
# 不處理傷害、血量或狀態切換。
# ============================================================


# ============================================================
# Inspector - 蓄力特效
# ============================================================

@export_group("蓄力特效")

# 是否使用蓄力閃紅效果
@export var enable_charge_flash: bool = true

# 蓄力提示顏色
@export var charge_color: Color = Color(1.0, 0.4, 0.4)

# 閃爍強度
@export_range(0.0, 1.0, 0.05)
var flash_strength: float = 0.65


# ============================================================
# Inspector - 地面提示
# ============================================================

@export_group("地面提示")

# 不喜歡提示圈時可以直接關閉
@export var show_charge_ring: bool = true

@export var charge_ring_radius: float = 48.0

@export var ring_color: Color = Color(1.0, 0.3, 0.3, 0.4)


# ============================================================
# Inspector - 旋轉揚塵
# ============================================================

@export_group("旋轉揚塵")

@export var enable_spin_dust: bool = true

@export var dust_amount: int = 28

@export var dust_lifetime: float = 0.55

@export var dust_color: Color = Color(0.65, 0.62, 0.68, 0.6)


# ============================================================
# Inspector - 撞牆碎屑
# ============================================================

@export_group("撞牆碎屑")

@export var enable_wall_particles: bool = true

@export var wall_particle_amount: int = 24

@export var wall_particle_color: Color = Color(0.85, 0.82, 0.76)


# ============================================================
# 節點引用
# ============================================================

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("../AnimatedSprite2D")
	as AnimatedSprite2D
)


# ============================================================
# 內部變數
# ============================================================

var dust_particles: CPUParticles2D

var wall_particles: CPUParticles2D

var particle_texture: Texture2D

var is_charging: bool = false

var charge_elapsed: float = 0.0

var charge_duration: float = 1.0

var flash_phase: float = 0.0

var original_sprite_color: Color = Color.WHITE

var charge_pulse: float = 0.0


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 像素素材使用最近鄰顯示
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 自動生成像素粒子貼圖
	particle_texture = _create_particle_texture()

	# 建立兩種粒子系統
	_create_dust_particles()
	_create_wall_particles()

	# 只有蓄力期間需要每幀處理
	set_process(false)


# ============================================================
# 自動建立像素粒子貼圖
#
# 不需要額外匯入 PNG 素材。
# ============================================================

func _create_particle_texture() -> Texture2D:

	var img = Image.create_empty(
		5,
		5,
		false,
		Image.FORMAT_RGBA8
	)

	img.fill(Color.TRANSPARENT)

	# 建立不規則的小型像素碎屑
	for x in range(5):

		for y in range(5):

			if abs(x - 2) + abs(y - 2) <= 3:

				img.set_pixel(
					x,
					y,
					Color.WHITE
				)

	return ImageTexture.create_from_image(img)


# ============================================================
# 建立共用粒子淡出漸層
# ============================================================

func _create_fade_gradient(color: Color) -> Gradient:

	var gradient = Gradient.new()

	gradient.set_color(
		0,
		color
	)

	gradient.set_color(
		1,
		Color(color.r, color.g, color.b, 0.0)
	)

	return gradient


# ============================================================
# 建立高速旋轉揚塵
# ============================================================

func _create_dust_particles() -> void:

	dust_particles = CPUParticles2D.new()

	dust_particles.name = "SpinDust"

	dust_particles.emitting = false

	dust_particles.texture = particle_texture

	dust_particles.amount = maxi(dust_amount, 1)

	dust_particles.lifetime = maxf(dust_lifetime, 0.1)

	dust_particles.one_shot = false

	# 粒子留在世界座標中，
	# 不會跟著陀螺一起移動。
	dust_particles.local_coords = false

	dust_particles.spread = 55.0

	dust_particles.gravity = Vector2.ZERO

	dust_particles.initial_velocity_min = 25.0

	dust_particles.initial_velocity_max = 100.0

	dust_particles.scale_amount_min = 1.0

	dust_particles.scale_amount_max = 2.5

	dust_particles.color_ramp = _create_fade_gradient(
		dust_color
	)

	# 顯示在角色下方
	dust_particles.z_index = -1

	add_child(dust_particles)


# ============================================================
# 建立撞牆碎屑粒子
# ============================================================

func _create_wall_particles() -> void:

	wall_particles = CPUParticles2D.new()

	wall_particles.name = "WallImpact"

	wall_particles.emitting = false

	wall_particles.texture = particle_texture

	wall_particles.amount = maxi(
		wall_particle_amount,
		1
	)

	wall_particles.lifetime = 0.45

	wall_particles.one_shot = true

	# 所有粒子在短時間內爆發
	wall_particles.explosiveness = 1.0

	wall_particles.local_coords = false

	wall_particles.spread = 75.0

	wall_particles.gravity = Vector2(0.0, 100.0)

	wall_particles.initial_velocity_min = 70.0

	wall_particles.initial_velocity_max = 200.0

	wall_particles.scale_amount_min = 0.8

	wall_particles.scale_amount_max = 2.0

	wall_particles.color_ramp = _create_fade_gradient(
		wall_particle_color
	)

	wall_particles.z_index = 1

	add_child(wall_particles)


# ============================================================
# 開始蓄力特效
# ============================================================

func begin_charge(duration: float) -> void:

	stop_attack_fx()

	is_charging = true

	charge_elapsed = 0.0

	charge_duration = maxf(duration, 0.01)

	flash_phase = 0.0

	charge_pulse = 0.0

	# 記住角色原本的顏色
	if is_instance_valid(sprite):

		original_sprite_color = sprite.self_modulate

	set_process(true)


# ============================================================
# 蓄力視覺更新
#
# 越接近蓄力結束，
# 閃爍頻率越快。
# ============================================================

func _process(delta: float) -> void:

	if not is_charging:
		return

	charge_elapsed += delta

	var progress = clampf(
		charge_elapsed / charge_duration,
		0.0,
		1.0
	)

	var frequency = lerpf(
		2.0,
		7.0,
		progress
	)

	flash_phase += delta * frequency * TAU

	charge_pulse = (
		sin(flash_phase) * 0.5 + 0.5
	)

	# 角色蓄力閃紅
	if (
		enable_charge_flash
		and is_instance_valid(sprite)
	):

		sprite.self_modulate = original_sprite_color.lerp(
			charge_color,
			charge_pulse * flash_strength
		)

	queue_redraw()


# ============================================================
# 繪製地面蓄力提示圈
# ============================================================

func _draw() -> void:

	if not is_charging or not show_charge_ring:
		return

	var current_color = ring_color

	current_color.a *= (
		0.4 + charge_pulse * 0.6
	)

	# 將圓形壓扁，形成地面透視感
	draw_set_transform(
		Vector2.ZERO,
		0.0,
		Vector2(1.0, 0.55)
	)

	draw_arc(
		Vector2.ZERO,
		charge_ring_radius,
		0.0,
		TAU,
		64,
		current_color,
		2.0,
		true
	)


# ============================================================
# 開始旋轉揚塵
# ============================================================

func begin_spin(dir: Vector2) -> void:

	# 結束蓄力提示
	stop_attack_fx()

	if not enable_spin_dust:
		return

	if not is_instance_valid(dust_particles):
		return

	update_spin_direction(dir)

	dust_particles.emitting = true


# ============================================================
# 根據移動方向調整揚塵
#
# 讓塵土往移動方向的反方向噴出。
# ============================================================

func update_spin_direction(dir: Vector2) -> void:

	if not is_instance_valid(dust_particles):
		return

	if dir.is_zero_approx():
		return

	dust_particles.direction = (
		-dir.normalized()
	).rotated(-dust_particles.global_rotation)


# ============================================================
# 撞牆特效
#
# 在實際接觸牆壁的位置爆發，
# 並朝牆壁外側噴射碎屑。
# ============================================================

func play_wall_impact(
	hit_position: Vector2,
	wall_normal: Vector2
) -> void:

	stop_attack_fx()

	if not enable_wall_particles:
		return

	if not is_instance_valid(wall_particles):
		return

	wall_particles.global_position = hit_position

	var direction = wall_normal

	if direction.is_zero_approx():

		direction = Vector2.UP

	wall_particles.direction = (
		direction.normalized()
	).rotated(-wall_particles.global_rotation)

	wall_particles.restart()

	wall_particles.emitting = true


# ============================================================
# 停止攻擊中的持續性特效
#
# 注意：不會停止已經爆發的撞牆粒子。
# 讓碎屑可以自然淡出。
# ============================================================

func stop_attack_fx() -> void:

	var was_charging = is_charging

	is_charging = false

	set_process(false)

	if was_charging and is_instance_valid(sprite):

		sprite.self_modulate = original_sprite_color

	if is_instance_valid(dust_particles):

		dust_particles.emitting = false

	queue_redraw()

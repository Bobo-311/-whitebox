extends BaseCharacter
class_name BaseEnemy

# ============================================================
# 【基礎敵人設定】
# ============================================================

@export var walk_speed: int = 150
@export var melee_damage: float = 15.0
@export var coin_drop_count: int = 5


# ============================================================
# 【拋物線跳躍設定】
# ============================================================

@export_group("🐸 拋物線跳躍設定 (青蛙專用)")

@export var use_jump_movement: bool = false
@export var jump_arc_height: float = 35.0
@export var jump_air_time: float = 0.45
@export var jump_ground_time: float = 0.18
@export var jump_burst_multiplier: float = 1.8

var _jump_timer: float = 0.0
var _is_jumping_this_frame: bool = false
var _base_sprite_pos_y: float = 0.0

@export var use_diagonal_anim: bool = false


# ============================================================
# 【預載資源】
# ============================================================

const COIN_SCENE = preload("res://coin/coin.tscn")
const HIT_IMPACT_PARTICLES = preload(
	"res://近戰/hit_impact_particles.tscn"
)


# ============================================================
# 【節點引用】
# ============================================================

@onready var state_machine: StateMachine = $StateMachine
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: ProgressBar = $HealthBar
@onready var vision_ray: RayCast2D = $VisionRay
@onready var hitbox: Area2D = get_node_or_null("Hitbox")

@onready var knockback_component: KnockbackComponent = \
	get_node_or_null("KnockbackComponent")


# ============================================================
# 【狀態變數】
# ============================================================

var can_see_player: bool = false
var player_node: CharacterBody2D = null
var last_facing_vec: Vector2 = Vector2.DOWN
var has_hit_player: bool = false
var can_attack: bool = true

var original_sprite_scale: Vector2 = Vector2.ONE
var is_illuminated_by_cat: bool = false
var fade_tween: Tween = null


# ============================================================
# 【初始化】
# ============================================================

func _ready() -> void:
	super._ready()

	if animated_sprite_2d:
		original_sprite_scale = animated_sprite_2d.scale
		_base_sprite_pos_y = animated_sprite_2d.position.y

		animated_sprite_2d.modulate = Color.WHITE
		animated_sprite_2d.self_modulate = Color.WHITE

	if hitbox:
		if not hitbox.body_entered.is_connected(
			_on_hitbox_body_entered
		):
			hitbox.body_entered.connect(
				_on_hitbox_body_entered
			)

	self.visible = false
	self.modulate = Color(1.0, 1.0, 1.0, 0.0)

	if state_machine:
		state_machine.init(self)


# ============================================================
# 【物理更新】
# ============================================================

func _physics_process(_delta: float) -> void:

	# ★【核心修正】
	# 敵人死亡後，禁止繼續呼叫 move_and_slide。
	# 此時碰撞箱可能已經關閉，繼續移動將造成穿牆。
	if is_dead:
		velocity = Vector2.ZERO
		return

	move_and_slide()
	_check_hitbox_overlap()

	# 玩家視線偵測。
	if is_instance_valid(player_node):
		vision_ray.target_position = to_local(
			player_node.global_position
		)
		vision_ray.force_raycast_update()
		can_see_player = not vision_ray.is_colliding()
	else:
		can_see_player = false

	# 拋物線防浮空保護。
	if use_jump_movement and animated_sprite_2d:
		if not _is_jumping_this_frame:
			_jump_timer = 0.0

			animated_sprite_2d.position.y = move_toward(
				animated_sprite_2d.position.y,
				_base_sprite_pos_y,
				250.0 * _delta
			)

		_is_jumping_this_frame = false


# ============================================================
# 【白貓迷霧現形系統】
# ============================================================

func update_visibility() -> void:
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()

	if is_dead:
		self.visible = true
		return

	fade_tween = create_tween()

	if is_illuminated_by_cat:
		self.visible = true

		fade_tween.tween_property(
			self,
			"modulate",
			Color(1.0, 1.0, 1.0, 1.0),
			0.35
		)
	else:
		fade_tween.tween_property(
			self,
			"modulate",
			Color(1.0, 1.0, 1.0, 0.0),
			0.35
		)

		fade_tween.tween_callback(func():
			if not is_illuminated_by_cat:
				self.visible = false
		)


# ============================================================
# 【受擊與處決系統】
# ============================================================

func take_damage(
	amount: float,
	attacker_pos: Vector2 = Vector2.ZERO,
	dir: Vector2 = Vector2.ZERO,
	is_melee: bool = false,
	_extra_knockback: float = 1.0
) -> void:

	if is_dead:
		return

	current_hp = max(current_hp - amount, 0)
	update_hp_bar()

	var is_kill: bool = current_hp <= 0

	# --------------------------------------------------------
	# 1. 近戰彈藥回復
	# --------------------------------------------------------

	if is_melee and DataManager and DataManager.player_node:
		var p = DataManager.player_node

		if is_kill:
			if p.has_method("refill_full_ammo"):
				p.refill_full_ammo()
		else:
			if p.has_method("add_ammo"):
				p.add_ammo(1)

	# --------------------------------------------------------
	# 2. 計算擊退方向
	# --------------------------------------------------------

	var knockback_dir: Vector2 = (
		dir
		if dir != Vector2.ZERO
		else (global_position - attacker_pos).normalized()
	)

	# ★【核心修正】
	# 一般受擊才交給 KnockbackComponent。
	# 致命一擊改由 Die 狀態統一執行安全死亡擊退。
	if not is_kill:
		if knockback_component and knockback_dir != Vector2.ZERO:
			knockback_component.apply_knockback(
				knockback_dir,
				-1.0,
				1.0
			)

	# 保留原有背部貫穿粒子。
	spawn_back_impact_particles(
		knockback_dir,
		is_kill,
		is_melee
	)

	# 保留受擊特效與頓幀。
	play_hit_effects(
		attacker_pos,
		is_kill,
		is_melee
	)

	if is_kill:
		die()
	else:
		handle_hurt()


# ============================================================
# 【背部貫穿粒子】
# ============================================================

func spawn_back_impact_particles(
	hit_dir: Vector2,
	is_kill: bool = false,
	is_melee: bool = false
) -> void:

	if not HIT_IMPACT_PARTICLES:
		return

	var final_dir: Vector2 = (
		hit_dir
		if hit_dir != Vector2.ZERO
		else Vector2.RIGHT
	)

	var particles = HIT_IMPACT_PARTICLES.instantiate()

	var back_offset: Vector2 = final_dir.normalized() * 80.0

	particles.global_position = global_position + back_offset
	particles.rotation = final_dir.angle()

	particles.z_index = self.z_index + 1

	if is_kill and is_melee:
		particles.scale = Vector2(2.5, 2.5)
	else:
		particles.scale = Vector2(1.5, 1.5)

	get_parent().add_child(particles)

	if particles.has_method("restart"):
		particles.restart()

	particles.emitting = true


# ============================================================
# 【受擊頓幀、閃光、鏡頭震動】
# ============================================================

func play_hit_effects(
	_attacker_pos: Vector2 = Vector2.ZERO,
	is_kill: bool = false,
	is_melee: bool = false
) -> void:

	if is_kill:
		if is_melee:
			if DataManager and DataManager.has_method(
				"trigger_execution_hitstop"
			):
				DataManager.trigger_execution_hitstop(
					0.18,
					0.08
				)

			get_tree().call_group(
				"main_camera",
				"apply_shake",
				20.0
			)

		else:
			if DataManager and DataManager.has_method(
				"trigger_hitstop"
			):
				DataManager.trigger_hitstop(
					0.08,
					0.05
				)

			get_tree().call_group(
				"main_camera",
				"apply_shake",
				15.0
			)

	else:
		if DataManager and DataManager.has_method(
			"trigger_hitstop"
		):
			DataManager.trigger_hitstop(
				0.07,
				0.05
			)

		get_tree().call_group(
			"main_camera",
			"apply_shake",
			10.0
		)

	# --------------------------------------------------------
	# 精靈圖閃光與受擊變形
	# --------------------------------------------------------

	if animated_sprite_2d:
		var tween = create_tween().set_parallel(true)

		var flash_dur: float = (
			0.2
			if is_kill and is_melee
			else 0.06
		)

		if animated_sprite_2d.material is ShaderMaterial:
			var mat = animated_sprite_2d.material as ShaderMaterial

			mat.set_shader_parameter(
				"flash_modifier",
				1.0
			)

			tween.tween_property(
				mat,
				"shader_parameter/flash_modifier",
				0.0,
				flash_dur
			)

		else:
			animated_sprite_2d.modulate = (
				Color(5, 5, 5)
				if is_kill
				else Color(3, 3, 3)
			)

			tween.tween_property(
				animated_sprite_2d,
				"modulate",
				Color.WHITE,
				flash_dur
			)

		var scale_x: float = original_sprite_scale.x * (
			1.4 if is_kill and is_melee else 1.2
		)

		var scale_y: float = original_sprite_scale.y * (
			0.6 if is_kill and is_melee else 0.8
		)

		animated_sprite_2d.scale = Vector2(
			scale_x,
			scale_y
		)

		tween.tween_property(
			animated_sprite_2d,
			"scale",
			original_sprite_scale,
			0.2
		).set_trans(
			Tween.TRANS_BACK
		).set_ease(
			Tween.EASE_OUT
		)


# ============================================================
# 【受傷狀態切換】
# ============================================================

func handle_hurt() -> void:
	if is_dead:
		return

	var state_name: String = \
		state_machine.current_state.name.to_lower()

	if "stun" in state_name or "pant" in state_name:
		return

	state_machine.change_state("Hurt")


# ============================================================
# 【死亡入口】
# ============================================================

func die() -> void:
	if is_dead:
		return

	is_dead = true
	can_attack = false

	# ★ 清除當前速度。
	velocity = Vector2.ZERO

	# ★ 清除並鎖定殘留擊退力。
	if knockback_component:
		knockback_component.lock_knockback()

	# 跳躍型敵人死亡時，將圖片恢復至地面。
	if use_jump_movement and animated_sprite_2d:
		animated_sprite_2d.position.y = _base_sprite_pos_y
		_jump_timer = 0.0
		_is_jumping_this_frame = false

	# 進入共用死亡狀態。
	state_machine.change_state("Die")

	# 保留金幣掉落。
	drop_coin()


# ============================================================
# 【血條更新】
# ============================================================

func update_hp_bar() -> void:
	if hp_bar and hp_bar.has_method("update_bar"):
		hp_bar.update_bar(current_hp, max_hp)


# ============================================================
# 【動畫播放與方向判定】
# ============================================================

func play_animation(
	prefix: String,
	dir: Vector2 = Vector2.ZERO
) -> void:

	var suffix: String = ""

	var target_dir: Vector2 = (
		dir
		if dir != Vector2.ZERO
		else last_facing_vec
	)

	if use_diagonal_anim:

		var x_name: String = ""
		var y_name: String = ""

		if target_dir.x > 0:
			x_name = "right"
		elif target_dir.x < 0:
			x_name = "left"
		else:
			x_name = (
				"left"
				if target_dir.y < 0
				else "right"
			)

		if target_dir.y < 0:
			y_name = "up"
		else:
			y_name = "down"

		suffix = "_" + x_name + "_" + y_name

	else:

		if abs(target_dir.x) > abs(target_dir.y):
			suffix = (
				"_right"
				if target_dir.x > 0
				else "_left"
			)
		else:
			suffix = (
				"_down"
				if target_dir.y > 0
				else "_up"
			)

	var animation_name: String = prefix + suffix

	if animation_name == "":
		return

	if not animated_sprite_2d.sprite_frames.has_animation(
		animation_name
	):
		push_warning(
			"⚠️ 找不到動畫，請檢查拼字：",
			animation_name
		)
		return

	animated_sprite_2d.play(animation_name)


# ============================================================
# 【金幣掉落】
# ============================================================

func drop_coin() -> void:
	if not COIN_SCENE or coin_drop_count <= 0:
		return

	for i in range(coin_drop_count):

		var delay: float = randf_range(0.01, 0.1)

		get_tree().create_timer(delay).connect("timeout", func():

			var coin = COIN_SCENE.instantiate()
			var spawn_pos: Vector2 = global_position

			if DataManager and is_instance_valid(
				DataManager.player_node
			):
				var dir_to_player: Vector2 = \
					global_position.direction_to(
						DataManager.player_node.global_position
					)

				var safe_offset: Vector2 = \
					dir_to_player * randf_range(15.0, 30.0)

				var random_jitter = Vector2(
					randf_range(-50.0, 50.0),
					randf_range(-50.0, 50.0)
				)

				spawn_pos = (
					global_position
					+ safe_offset
					+ random_jitter
				)

			else:
				spawn_pos = global_position + Vector2(
					randf_range(-20.0, 20.0),
					randf_range(-20.0, 20.0)
				)

			var local_pos = get_parent().to_local(spawn_pos)

			coin.position = local_pos
			get_parent().add_child(coin)
		)


# ============================================================
# 【碰撞傷害】
# ============================================================

func _on_hitbox_area_entered(area: Area2D) -> void:

	# ★ 屍體不能觸發碰撞傷害。
	if is_dead:
		return

	var parent = area.get_parent()

	if parent is Player \
	or parent.is_in_group("player") \
	or parent.name == "player":

		_apply_damage_and_knockback(parent, area)

	elif parent is WhiteCat \
	or parent.is_in_group("white_cat"):

		if parent.has_method("take_damage"):
			parent.take_damage(
				melee_damage,
				global_position
			)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_dead:
		return

	if body is Player \
	or body.is_in_group("player") \
	or body.name == "player":

		_apply_damage_and_knockback(body, null)


func _apply_damage_and_knockback(
	target: Node2D,
	target_area: Area2D = null
) -> void:

	if is_dead:
		return

	var is_dashing: bool = false

	if state_machine.current_state:

		var current_state_name = \
			state_machine.current_state.name

		if current_state_name == "EnemyAttack" \
		or current_state_name == "BerserkCharge" \
		or current_state_name == "ShieldPush":

			is_dashing = true

	if is_dashing:
		has_hit_player = true

	var knockback_dir: Vector2 = (
		target.global_position - global_position
	).normalized()

	var extra_kb: float = (
		2.0 if is_dashing else 1.0
	)

	if target_area and target_area.has_method("take_damage"):

		target_area.take_damage(
			melee_damage,
			global_position,
			knockback_dir,
			false,
			extra_kb
		)

	elif target.has_method("take_damage"):

		target.take_damage(
			melee_damage,
			global_position,
			knockback_dir,
			false,
			extra_kb
		)


func _check_hitbox_overlap() -> void:

	if is_dead:
		return

	if not hitbox or not hitbox.monitoring:
		return

	for body in hitbox.get_overlapping_bodies():

		if body is Player \
		or body.is_in_group("player") \
		or body.name == "player":

			_apply_damage_and_knockback(body, null)


# ============================================================
# 【玩家偵測】
# ============================================================

func _on_detect_player_body_entered(body) -> void:

	if body is Player \
	or body.is_in_group("player") \
	or body.name == "player":

		player_node = body


func _on_detect_player_body_exited(body) -> void:

	if body == player_node or body.is_in_group("player"):
		player_node = null


# ============================================================
# 【暈眩系統】
# ============================================================

func apply_stun(duration: float = 1.0) -> void:

	if is_dead:
		return

	if state_machine and state_machine.has_node("Stun"):

		var stun_node = state_machine.get_node("Stun")

		if "custom_duration" in stun_node:
			stun_node.custom_duration = duration

		state_machine.change_state("Stun")


# ============================================================
# 【拋物線跳躍系統】
# ============================================================

func apply_locomotion(
	move_dir: Vector2,
	base_speed: float
) -> void:

	if is_dead:
		velocity = Vector2.ZERO
		return

	if not use_jump_movement or not animated_sprite_2d:
		velocity = move_dir * base_speed
		return

	_is_jumping_this_frame = true

	var delta: float = get_physics_process_delta_time()

	var total_cycle: float = \
		jump_air_time + jump_ground_time

	_jump_timer = fmod(
		_jump_timer + delta,
		total_cycle
	)

	if _jump_timer < jump_air_time:

		var t: float = _jump_timer / jump_air_time
		var arc_curve: float = sin(t * PI)

		animated_sprite_2d.position.y = (
			_base_sprite_pos_y
			- arc_curve * jump_arc_height
		)

		velocity = move_dir * (
			base_speed
			* jump_burst_multiplier
			* arc_curve
			* 1.4
		)

	else:

		animated_sprite_2d.position.y = _base_sprite_pos_y

		velocity = velocity.move_toward(
			Vector2.ZERO,
			base_speed * 15.0 * delta
		)


func is_jump_grounded() -> bool:
	if not use_jump_movement or not animated_sprite_2d:
		return true

	return (
		_jump_timer >= jump_air_time
		or not _is_jumping_this_frame
	)

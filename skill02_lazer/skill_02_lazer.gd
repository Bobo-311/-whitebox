extends Node2D

const IMPACT_EFFECT = preload("res://Bullet/ink_impact_effect.tscn")

@export_group("Damage Settings")
@export var base_damage: float = 15.0       # 基礎傷害 (0秒蓄力)
@export var max_bonus_damage: float = 45.0  # 滿蓄力額外加乘 (滿蓄力 = 60傷)

@export_group("Crit Settings")
@export var base_crit_rate: float = 0.05    # 基礎暴擊率 5%
@export var max_crit_rate: float = 0.50     # 滿蓄力最高暴擊率 50%
@export var crit_multiplier: float = 1.5    # 暴擊時的傷害倍率

@export var max_range: float = 1200.0       # 狙擊槍最遠射程
@export var laser_duration: float = 0.25    # 🌟 雷射殘留時間加長一點，視覺更有震撼力

@onready var raycast: RayCast2D = $RayCast2D
@onready var line_2d: Line2D = $Line2D

var direction: Vector2 = Vector2.ZERO
var shooter: CharacterBody2D = null
var received_buff: float = 1.0
var charge_stage: int = 1

func _ready() -> void:
	# 清空 line_2d 避免有編輯器殘留的線條
	if line_2d:
		line_2d.clear_points()

func fire_laser() -> void:
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	
	raycast.target_position = Vector2(max_range, 0)
	if shooter: raycast.add_exception(shooter)

	# 🌟 動態雷射粗細 (1段:8px, 2段:17px, 3段:26px)
	line_2d.width = 8.0 + ((charge_stage - 1) * 9.0)

	raycast.force_raycast_update()
	var hit_point_local = Vector2(max_range, 0)
	
	if raycast.is_colliding():
		hit_point_local = to_local(raycast.get_collision_point())
		_apply_damage(raycast.get_collider(), raycast.get_collision_point())
		spawn_impact_effect(raycast.get_collision_point())
		
		# 鏡頭震動 (1段:4.0, 2段:8.0, 3段:12.0)
		var shake_str = 4.0 + ((charge_stage - 1) * 4.0)
		get_tree().call_group("main_camera", "apply_shake", shake_str)

	line_2d.points = [Vector2.ZERO, hit_point_local]
	_animate_laser_fade()

func _apply_damage(target: Node2D, hit_pos: Vector2) -> void:
	if target == shooter or target.is_in_group("player") or target.is_in_group("white_cat"):
		return
		
	# 算出段數比例：1段=0.0(無加成), 2段=0.5(一半加成), 3段=1.0(吃滿所有加成)
	var ratio = (charge_stage - 1) / 2.0 
	var final_damage = (base_damage + (max_bonus_damage * ratio)) * received_buff
	var current_crit_rate = base_crit_rate + (max_crit_rate * ratio)
	
	var is_crit = randf() <= current_crit_rate
	if is_crit:
		final_damage *= crit_multiplier
		print("💥 暴擊！造成傷害: ", final_damage)

	if target.has_method("take_damage"):
		target.take_damage(final_damage, hit_pos, direction)
	# ... (保留你原本底下的受傷邏輯)
	
	
# 🌟 雷射光淡出動畫
func _animate_laser_fade() -> void:
	var tween = create_tween().set_parallel(true)
	tween.tween_property(line_2d, "width", 0.0, laser_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(line_2d, "modulate:a", 0.0, laser_duration)
	tween.chain().tween_callback(queue_free)

func spawn_impact_effect(pos: Vector2) -> void:
	if IMPACT_EFFECT:
		var effect = IMPACT_EFFECT.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = pos
		effect.rotation = direction.angle() - PI

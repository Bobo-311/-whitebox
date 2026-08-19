extends Node
class_name KnockbackComponent

@export var default_strength: float = 500.0   # 預設擊退力道
@export var friction: float = 2000.0          # 煞車摩擦力 (數字越小滑越久)
@export var resistance: float = 1.0           # 霸體抗性

var knockback_force: Vector2 = Vector2.ZERO
@onready var parent_body: CharacterBody2D = get_parent() as CharacterBody2D

func _physics_process(delta: float) -> void:
	if not is_instance_valid(parent_body): return
	
	if knockback_force.length() > 0.0:
		parent_body.velocity = knockback_force
		# 🌟【關鍵修改】改用跟物理移動同步的 delta！
		# 這樣在 Hitstop 頓幀期間，擊退力道就會跟著時間一起「凝結」，不會在背景被白白消耗掉！
		knockback_force = knockback_force.move_toward(Vector2.ZERO, friction * delta)

func apply_knockback(direction: Vector2, custom_strength: float = -1.0, extra_multiplier: float = 1.0) -> void:
	if resistance <= 0.0: return
	
	var base_str = custom_strength if custom_strength > 0.0 else default_strength
	var dir = direction.normalized()
	
	knockback_force = dir * (base_str * extra_multiplier) / resistance

extends Node
class_name KnockbackComponent

# ============================================================
# 【擊退參數設定】
# ============================================================

@export var default_strength: float = 500.0
@export var friction: float = 2000.0
@export var resistance: float = 1.0

# ============================================================
# 【內部變數】
# ============================================================

var knockback_force: Vector2 = Vector2.ZERO

# 鎖定後，不再接受或執行任何擊退。
var _knockback_locked: bool = false

@onready var parent_body: CharacterBody2D = \
	get_parent() as CharacterBody2D


# ============================================================
# 【物理更新】
# ============================================================

func _physics_process(delta: float) -> void:
	if not is_instance_valid(parent_body):
		return

	# 死亡或其他特殊情況下，完全停止擊退。
	if _knockback_locked:
		return

	if knockback_force.length_squared() > 0.0:
		parent_body.velocity = knockback_force

		# 保留原本與 Hitstop 同步的擊退衰減。
		knockback_force = knockback_force.move_toward(
			Vector2.ZERO,
			friction * delta
		)


# ============================================================
# 【施加擊退】
# ============================================================

func apply_knockback(
	direction: Vector2,
	custom_strength: float = -1.0,
	extra_multiplier: float = 1.0
) -> void:

	if _knockback_locked:
		return

	if resistance <= 0.0:
		return

	var base_str: float = (
		custom_strength
		if custom_strength > 0.0
		else default_strength
	)

	var dir: Vector2 = direction.normalized()

	knockback_force = (
		dir * base_str * extra_multiplier
	) / resistance


# ============================================================
# 【清除目前擊退】
# ============================================================

func clear_knockback() -> void:
	knockback_force = Vector2.ZERO

	if is_instance_valid(parent_body):
		parent_body.velocity = Vector2.ZERO


# ============================================================
# 【鎖定擊退】
# 用於死亡或禁止擊退的特殊狀態。
# ============================================================

func lock_knockback() -> void:
	_knockback_locked = true
	clear_knockback()


# ============================================================
# 【解除擊退鎖定】
# 預留給未來的復活或特殊狀態使用。
# ============================================================

func unlock_knockback() -> void:
	_knockback_locked = false
	clear_knockback()


func is_knockback_locked() -> bool:
	return _knockback_locked

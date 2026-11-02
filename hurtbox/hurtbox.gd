extends Area2D
class_name Hurtbox

# =====================================================
# 通用受傷區
# 負責將傷害轉交給直接父節點
#
# 適用：
# Player
# BaseEnemy
# 淵獄蓮華
# 淵獄蓮華觸手
#
# 不在這裡處理 HP、死亡、墨水或擊退。
# 這些由各自的主人決定。
# =====================================================

func take_damage(
	amount: float,
	hit_position: Vector2 = Vector2.ZERO,
	hit_direction: Vector2 = Vector2.ZERO,
	is_melee: bool = false,
	extra_knockback: float = 1.0
) -> void:

	var parent = get_parent()

	if not parent:
		return

	print(
		"💥【", parent.name,
		"】的 Hurtbox 被打到了，擊退倍率：",
		extra_knockback
	)

	if parent.has_method("take_damage"):

		parent.take_damage(
			amount,
			hit_position,
			hit_direction,
			is_melee,
			extra_knockback
		)

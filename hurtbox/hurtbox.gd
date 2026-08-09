extends Area2D                                # 繼承自 Area2D
class_name Hurtbox                           # 宣告為通用的「受傷區」類別

# 🌟【本次新增】：在最後面加上 extra_knockback: float = 1.0
func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	var parent = get_parent()                # 抓取真正的主人 (Player 或 Enemy)
	if not parent: return
	
	print("💥【", parent.name, "】的 Hurtbox 被打到了，擊退倍率：", extra_knockback)

	if parent.has_method("take_damage"):
		# 🌟【關鍵轉接】把 extra_knockback 完整傳遞給父節點
		parent.take_damage(amount, hit_position, hit_direction, is_melee, extra_knockback)

extends Area2D                                # 繼承自 Area2D
class_name Hurtbox                           # 宣告為通用的「受傷區」類別

# --- 接收攻擊的痛覺受器 ---
func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO) -> void:
	var parent = get_parent()                # 抓取真正的主人 (Player 或 Enemy)
	if not parent: return
	
	print("💥【", parent.name, "】的 Hurtbox 被打到了")

	if parent.has_method("take_damage"):
		parent.take_damage(amount, hit_position, hit_direction)

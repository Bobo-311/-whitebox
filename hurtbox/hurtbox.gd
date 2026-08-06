extends Area2D                                # 繼承自 Area2D
class_name Hurtbox                           # 宣告為通用的「受傷區」類別

# --- 接收攻擊的痛覺受器 ---
# 🌟 新增 is_melee 參數 (預設為 false)
func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO, is_melee: bool = false) -> void:
	var parent = get_parent()                # 抓取真正的主人 (Player 或 Enemy)
	if not parent: return
	
	print("💥【", parent.name, "】的 Hurtbox 被打到了")

	if parent.has_method("take_damage"):
		# 🌟【關鍵轉接】將 is_melee 完整傳遞給父節點 (Enemy 或 Player)
		parent.take_damage(amount, hit_position, hit_direction, is_melee)

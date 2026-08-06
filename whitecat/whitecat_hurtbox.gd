extends Hurtbox                 # 繼承通用的 Hurtbox
class_name WhiteCatHurtbox       # 白貓專用的受傷區類別

# 🌟 補上第 4 個參數 is_melee: bool = false，確保與父類別 Hurtbox 簽名完全一致
func take_damage(damage_amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false) -> void:
	var parent = get_parent()
	if not parent: return
	
	print("💥【", parent.name, "】(白貓) 的 Hurtbox 被打到了")
	
	if parent.has_method("take_damage"):
		# 轉交給白貓本體處理
		parent.take_damage(damage_amount, attacker_pos, dir, is_melee)

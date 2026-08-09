extends Hurtbox                 # 繼承通用的 Hurtbox
class_name WhiteCatHurtbox       # 白貓專用的受傷區類別

# 🌟【關鍵修復】補上第 5 個參數 extra_knockback: float = 1.0，確保與父類別 Hurtbox 簽名完全一致
func take_damage(damage_amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	var parent = get_parent()
	if not parent: return
	
	print("💥【", parent.name, "】(白貓) 的 Hurtbox 被打到了")
	
	if parent.has_method("take_damage"):
		# 🌟 將 extra_knockback 也轉交給白貓本體處理
		parent.take_damage(damage_amount, attacker_pos, dir, is_melee, extra_knockback)

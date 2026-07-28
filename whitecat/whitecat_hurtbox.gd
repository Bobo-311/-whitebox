extends Hurtbox                              # 🌟 繼承通用的 Hurtbox
class_name WhiteCatHurtbox                  # 白貓專用的受擊區類別

# 當收到傷害時，精準轉交 2 個參數給白貓本體
func take_damage(damage_amount: float, attacker_pos: Vector2 = Vector2.ZERO, _dir: Vector2 = Vector2.ZERO) -> void:
	var parent = get_parent()
	if not parent: return
	
	print("💥【", parent.name, "】(白貓) 的 Hurtbox 被打到了")

	if parent.has_method("take_damage"):
		# 🌟 這裡精準傳入白貓本體接收的 2 個參數 (傷害量, 攻擊者位置)
		parent.take_damage(damage_amount, attacker_pos)

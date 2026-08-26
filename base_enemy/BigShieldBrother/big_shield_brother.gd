extends BaseEnemy 
class_name BigShieldBrother 

@export_category("🛡️ 鐵門防禦設定")
# 預設為朝下，既然只有一面牆，這個參數其實就是寫死的 Vector2.DOWN
var shield_direction: Vector2 = Vector2.DOWN 

# 判定正面攻擊的寬容度
const BLOCK_TOLERANCE: float = 0.2

func _ready() -> void:
	super._ready()
	
	# 添加碰撞例外，讓肉身不要跟自己的實體盾牌互撞
	var shield_wall = get_node_or_null("ShieldWallBody")
	if shield_wall:
		add_collision_exception_with(shield_wall)

# ==========================================
# 🛡️ 絕對防禦：攔截受傷邏輯
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if is_dead: return 
	
	# 1. 算出攻擊打過來的「方向」
	var attack_dir = dir
	if attack_dir == Vector2.ZERO and attacker_pos != Vector2.ZERO:
		attack_dir = (global_position - attacker_pos).normalized()
		
	# 2. 核心魔法：使用「數學內積 (dot)」判斷角度
	if attack_dir.dot(shield_direction) > BLOCK_TOLERANCE:
		print("🛡️ 鐵門格擋！傷害無效！(正面絕對防禦)")
		return 
		
	# 3. 繞背成功，交給老爸扣血
	print("🩸 玩家成功繞背！大盾兄弟受傷！")
	super.take_damage(amount, attacker_pos, dir, is_melee, extra_knockback)

# ==========================================
# 🛡️ 絕對防禦：免疫正面暈眩
# ==========================================
func apply_stun(duration: float = 1.0) -> void:
	if is_dead: return 
	
	if player_node:
		var attack_dir = (global_position - player_node.global_position).normalized()
		
		if attack_dir.dot(shield_direction) > BLOCK_TOLERANCE:
			print("🛡️ 鐵門免疫了暈眩！")
			return 
			
	super.apply_stun(duration)

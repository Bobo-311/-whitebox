extends State

# ==========================================
# ⚙️ 瘋狗衝刺設定
# ==========================================
@export_category("狂暴衝刺設定")
@export var hit_cooldown: float = 0.5 # 🆕 撞到玩家後，原地停頓 0.5 秒

var charge_cooldown: float = 0.0

func enter():
	charge_cooldown = 0.0
	
	# 🆕 【正規開啟 Hitbox】
	# 變身衝刺狀態下，強制開啟老爸的 Hitbox 雷達，讓他能主動偵測玩家
	var hitbox = character.get_node_or_null("Hitbox")
	if hitbox:
		hitbox.monitoring = true

func state_physics_update(delta: float):
	# 1. 視覺/視野判定：如果玩家死了，或是躲進牆壁導致視線中斷，直接切回 Idle
	if not character.player_node or not character.can_see_player:
		character.velocity = Vector2.ZERO
		character.play_animation("idle", character.last_facing_vec)
		state_machine.change_state("Idle")
		return

	# 2. 撞擊後的停頓冷卻時間處理
	if charge_cooldown > 0:
		charge_cooldown -= delta
		character.velocity = Vector2.ZERO
		character.play_animation("idle", character.last_facing_vec)
		return

	# 3. 瘋狗模式：每一幀都計算方向並朝玩家衝刺
	var move_dir = (character.player_node.global_position - character.global_position).normalized()
	character.velocity = move_dir * character.walk_speed
	character.last_facing_vec = move_dir
	character.play_animation("run", move_dir)

	# 4. 【正規碰撞傷害】利用老爸的 Hitbox 偵測重疊
	# 只要 Hitbox 碰到玩家，就觸發老爸定義好的扣血邏輯
	var hitbox = character.get_node_or_null("Hitbox")
	if hitbox and hitbox.has_overlapping_bodies():
		for body in hitbox.get_overlapping_bodies():
			if body == character.player_node:
				# 呼叫老爸的 _apply_damage_and_knockback 函數，確保扣血與擊退都跟老爸一致
				character._apply_damage_and_knockback(body, null)
				
				# 🆕 撞到玩家後，強制進入 0.5 秒的停頓冷卻
				charge_cooldown = hit_cooldown

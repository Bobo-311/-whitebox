extends State

@export_category("狂暴衝刺設定")
@export var hit_cooldown: float = 2.0 # 撞到玩家後，原地停頓 2 秒

var charge_cooldown: float = 0.0

func enter():
	charge_cooldown = 0.0
	
	# 1. 關閉原本揮刀用的 Hitbox，解決「手太長」的問題
	var sword_hitbox = character.get_node_or_null("Hitbox")
	if sword_hitbox:
		sword_hitbox.monitoring = false
		for child in sword_hitbox.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)
	
	# 2. 開啟我們剛剛新增的專屬肉身碰撞框 BodyHitbox
	var body_hitbox = character.get_node_or_null("BodyHitbox")
	if body_hitbox:
		body_hitbox.monitoring = true
		for child in body_hitbox.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", false)

func state_physics_update(delta: float):
	# 🆕【最高優先級】：玩家死亡判定
	# 如果玩家死掉了，就直接鎖死在原地發呆，不切換狀態，保持二階的壓迫感
	if not character.player_node or (character.player_node.has_method("is_dead") and character.player_node.is_dead):
		character.velocity = Vector2.ZERO
		character.play_animation("idle", character.last_facing_vec)
		return # 直接 Return，永遠卡在這裡發呆！

	# 1. 視覺/視野判定
	# 狂暴狀態下，如果因為牆壁擋住而暫時看不到玩家，讓他原地發呆喘氣，不要切回 Idle
	if not character.can_see_player:
		character.velocity = Vector2.ZERO
		character.play_animation("idle", character.last_facing_vec)
		return

	# 2. 撞擊後的停頓冷卻時間處理
	if charge_cooldown > 0:
		charge_cooldown -= delta
		character.velocity = Vector2.ZERO
		character.play_animation("idle", character.last_facing_vec)
		
		# 【確保只衝撞不揮刀】：休息 2 秒結束後，強迫重啟衝刺狀態
		if charge_cooldown <= 0:
			enter() 
		return

	# 3. 瘋狗模式：衝刺
	var move_dir = (character.player_node.global_position - character.global_position).normalized()
	character.velocity = move_dir * character.walk_speed
	character.last_facing_vec = move_dir
	character.play_animation("run", move_dir)

	# 4. 【改用 BodyHitbox 並且偵測 Body】
	var body_hitbox = character.get_node_or_null("BodyHitbox")
	if body_hitbox and body_hitbox.has_overlapping_bodies():
		for body in body_hitbox.get_overlapping_bodies():
			# 只要重疊的 body 是玩家，就扣血！
			if body == character.player_node or body.is_in_group("player") or body.name == "player":
				character._apply_damage_and_knockback(body, null)
				charge_cooldown = hit_cooldown

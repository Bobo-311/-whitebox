extends State # dango_chase.gd

var chase_speed: float = 180.0 

func state_physics_update(_delta: float):
	# 1️⃣ 🌟【修正為掃描 Area】：檢查 Hitbox 裡有沒有玩家的 Hurtbox！
	var hitbox = character.get_node_or_null("Hitbox")
	if hitbox:
		for area in hitbox.get_overlapping_areas(): # 改成 areas！
			if area is Hurtbox: # 只要掃到玩家的受傷區
				state_machine.change_state("Pant") # 立刻強制發呆！
				return

	# 2️⃣ 如果玩家死掉、走出圈圈、或被牆擋住
	if not character.player_node or not character.can_see_player:
		state_machine.change_state("Move") 
		return

	# 3️⃣ 追擊邏輯
	var chase_dir = (character.player_node.global_position - character.global_position).normalized()
	character.velocity = chase_dir * chase_speed
	character.last_facing_vec = chase_dir
	character.play_animation("move", chase_dir)

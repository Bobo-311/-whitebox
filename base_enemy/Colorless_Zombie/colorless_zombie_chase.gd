extends State

@export var chase_speed: float = 200.0     # 追擊速度
@export var attack_distance: float = 150.0 # 🌟 離玩家 150 距離就開始播放攻擊動畫！

func enter():
	character.play_animation("run") 
	
	# 🌟【關鍵修正】：追擊時把 Hitbox 關閉！
	# 這樣殭屍用身體撞到玩家就不會扣血了，純粹只是推擠。
	if character.hitbox:
		character.hitbox.set_deferred("monitoring", false)

func state_physics_update(_delta: float):
	# 1. 視野丟失判定
	if not character.player_node or not character.can_see_player:
		state_machine.change_state("Move")
		return

	# 2. 攻擊距離判定
	var dist = character.global_position.distance_to(character.player_node.global_position)
	if dist <= attack_distance:
		state_machine.change_state("Attack")
		return

	# 3. 往玩家方向狂奔
	var dir = (character.player_node.global_position - character.global_position).normalized()
	character.velocity = dir * chase_speed
	character.last_facing_vec = dir
	character.play_animation("run", dir)

extends State

@export_category("🏹 風箏走位設定")
@export var retreat_speed: float = 100.0   # 倒退嚕的速度 (企劃可調)
@export var attack_range: float = 200.0    # 吐毒的安全距離 (企劃可調)

func state_physics_update(_delta: float):
	# 1. 找不到玩家就不做事
	if not character.player_node: return 

	# 2. 隨時計算玩家的距離與方向
	var target_pos = character.player_node.global_position
	var dist = character.global_position.distance_to(target_pos)
	var dir = character.global_position.direction_to(target_pos)

	# 3. 判斷要退還是要停
	if dist > attack_range:
		# 距離夠遠：原地煞車停下，死死盯著玩家
		character.velocity = Vector2.ZERO
		character.play_animation("idle", dir)
		# (TODO: 以後這裡會切換去吐毒沼)
	else:
		# 距離太近：面朝玩家，但身體往反方向退
		character.velocity = (dir * -1) * retreat_speed
		character.last_facing_vec = dir 
		character.play_animation("move", dir)

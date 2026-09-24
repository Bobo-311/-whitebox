extends State

# 攻擊距離：距離小於這個數值，就煞車揮刀 (可以在屬性面板微調)
@export var attack_range: float = 150.0 

func enter():
	# 進入追擊時，播放run (走路) 動畫
	character.play_animation("move", character.last_facing_vec)

func state_physics_update(_delta: float):
	# 防呆：如果玩家不見了，退回待機
	if not character.player_node or not character.can_see_player:
		state_machine.change_state("move")
		return

	# 計算野蠻人與玩家的直線距離
	var distance_to_player = character.global_position.distance_to(character.player_node.global_position)
	
	# 如果進入揮砍範圍
	if distance_to_player <= attack_range:
		# 走到面前了！煞車，並切換到 Attack 狀態
		character.velocity = Vector2.ZERO
		state_machine.change_state("Attack")
		return

	# 還沒到，繼續走向玩家 (並且更新面朝方向)
	var move_dir = (character.player_node.global_position - character.global_position).normalized()
	character.velocity = move_dir * character.walk_speed
	character.last_facing_vec = move_dir
	character.play_animation("move", move_dir)

# --- EnemyIdle.gd ---
extends State

func enter():
	character.velocity = Vector2.ZERO # 速度歸零停在原地
	character.play_animation("idle")  # 播放待機動畫

func state_physics_update(_delta: float):
	# 🌟【教學重點：加入真實視野判定 can_see_player】
	# 條件：玩家在藍色圈內 (有目標) 且 雷射光暢通 (有看到肉體)
	if character.player_node and character.can_see_player: 
		state_machine.change_state("EnemyRun") # 真真實實看到了，才開始追擊！
		return                
		
	state_machine.change_state("EnemyMove")#沒看到玩家，直接把主導權交給 EnemyMove

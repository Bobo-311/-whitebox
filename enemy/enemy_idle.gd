# --- EnemyIdle.gd ---
extends State

func enter():
	character.velocity = Vector2.ZERO # 速度歸零停在原地
	character.play_animation("idle")  # 播放待機動畫

func state_physics_update(_delta: float):
	if character.player_node: # 如果發呆時看到玩家
		state_machine.change_state("EnemyRun") # 立刻追擊
		return               
		
	elif randf() > 0.98:      # 每幀有 2% 的機率隨機切換回漫遊狀態
		state_machine.change_state("EnemyMove")

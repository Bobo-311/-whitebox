extends State                    # 繼承自狀態模板

var hurt_timer: float = 0.4      # 受傷硬直計時器：預設被打退 0.4 秒

func enter():                    # 進入受傷狀態時執行
	hurt_timer = 0.4             # 重置受傷時間
	character.can_attack = false # 被打飛時沒收攻擊權力
	character.play_animation("hurt") # 播放受傷挨打的動畫

func state_physics_update(delta: float): # 每一幀物理更新
	hurt_timer -= delta          # 扣除受傷時間

	# 🌟 接管擊退物理：把速度強制設定為地基算好的「擊退力道」
	character.velocity = character.knockback_force
	
	# 滑行煞車：讓擊退力道每幀減少 15%，產生摩擦地面的感覺
	character.knockback_force = character.knockback_force.lerp(Vector2.ZERO, 0.15)

	if hurt_timer <= 0:          # 如果 0.4 秒硬直結束
		if character.current_hp > 0: # 如果野豬還活著
			character.can_attack = true # 恢復攻擊權力

			if character.player_node:   # 如果視野內還有玩家
				state_machine.change_state("EnemyRun")  # 進入追擊狀態
			else:                       # 如果玩家不見了
				state_machine.change_state("EnemyMove") # 進入隨機漫遊狀態

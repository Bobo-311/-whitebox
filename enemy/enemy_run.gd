extends State                    # 繼承自狀態模板

func state_physics_update(_delta: float): # 追擊狀態每一幀的更新
	if character.can_attack == false: # 如果攻擊還在冷卻中
		return                   # 就什麼都不做，原地發呆看著玩家
		
	if character.player_node == null: # 如果目標玩家突然消失(離開視野或死掉)
		state_machine.change_state("EnemyMove") # 放棄追擊，切換回隨機漫遊狀態
		return                   # 結束這一幀

	var dir = (character.player_node.global_position - character.global_position).normalized() # 計算指向玩家的方向向量
	var dist = character.global_position.distance_to(character.player_node.global_position) # 計算與玩家之間的直線距離

	character.last_facing_vec = dir # 隨時更新野豬面朝的方向為玩家的方向

	if dist <= 500 and character.can_attack: # 如果距離小於 500 (進入攻擊圈) 且 攻擊冷卻完畢
		if dist > 350:           # 情況A：距離偏遠 (350 ~ 500)
			state_machine.change_state("EnemyShoot") # 100% 機率切換到吐波導彈狀態
		elif dist < 200:         # 情況B：距離貼臉 (小於 200)
			state_machine.change_state("EnemyAttack") # 100% 機率切換到肉身衝撞攻擊
		else:                    # 情況C：中距離 (200 ~ 350)
			if randi() % 2 == 0: # 隨機骰子：取 2 的餘數 (50% 機率)
				state_machine.change_state("EnemyShoot") # 50% 吐波導彈
			else:                
				state_machine.change_state("EnemyAttack")# 50% 肉身衝撞
		return                   # 決定好攻擊後立刻跳出

	else:                        # 如果距離大於 500，還沒進攻擊圈
		character.velocity = dir * character.sprint_speed # 把速度設為：朝向玩家方向 * 追擊速度
		character.play_animation("run", dir) # 播放追擊奔跑動畫
		
		# 🌟 新增：如果野豬在狂奔追逐的過程中撞死在牆上
		if character.is_on_wall(): # 如果引擎判定撞牆
			print("【系統】野豬跑步追擊時撞死在牆上了！") # 後台印出提示
			state_machine.change_state("EnemyStun") # 直接進入暈眩狀態！

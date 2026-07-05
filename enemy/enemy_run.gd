extends State                    # 繼承自狀態模板 enemy_run

func state_physics_update(_delta: float): # 追擊狀態每一幀的更新
	if character.can_attack == false: # 如果攻擊還在冷卻中
		return                   # 就什麼都不做，原地發呆看著玩家
		
	# 🌟【核心修改：視野斷線的放棄機制】
	# 如果玩家離開了藍圈 (null) 或者 躲到了柱子後面 (雷射被擋住 = false)
	if character.player_node == null or character.can_see_player == false: 
		state_machine.change_state("EnemyMove") # 視線被切斷，野豬直接放棄，切回隨機漫遊
		return

	var dir = (character.player_node.global_position - character.global_position).normalized() # 計算指向玩家的方向向量
	var dist = character.global_position.distance_to(character.player_node.global_position) # 計算與玩家之間的直線距離

	character.last_facing_vec = dir # 隨時更新野豬面朝的方向為玩家的方向

	# 🌟 就是這裡！你想改距離，直接改下面這幾個數字：
	if dist <= 400 and character.can_attack: # 500 是「開始攻擊的最大極限距離」
		if dist > 300:           # 大於 350：保證吐波導彈
			state_machine.change_state("EnemyShoot") 
		elif dist < 250:         # 小於 200：太近了，保證肉身衝撞
			state_machine.change_state("EnemyAttack") 
		else:                    # 200 ~ 350 之間：隨機 50% 吐波、50% 衝撞
			if randi() % 2 == 0: 
				state_machine.change_state("EnemyShoot") 
			else:                
				state_machine.change_state("EnemyAttack")
		return                   # 決定好攻擊後立刻跳出

	else:                        # 如果距離大於 500，還沒進攻擊圈
		character.velocity = dir * character.sprint_speed # 把速度設為：朝向玩家方向 * 追擊速度
		character.play_animation("run", dir) # 播放追擊奔跑動畫
		
		# 🌟 核心修正：加入正面撞擊判定，避免擦牆暈眩
		if character.is_on_wall(): # 如果引擎判定撞牆
			# 計算速度方向與牆壁法線的夾角，小於 -0.5 才是正面迎頭撞上
			if character.velocity.normalized().dot(character.get_wall_normal()) < -0.5:
				print("【系統】野豬正面跑步撞死在牆上了！") # 後台印出提示
				state_machine.change_state("EnemyStun") # 直接進入暈眩狀態！

extends State # 繼承自狀態機模板 player_move

func state_physics_update(delta: float): # 每一物理幀執行
	
	# --- 動作指令偵測 (最高優先級，確保能中斷移動) ---
	if Input.is_action_just_pressed("dash"):      
		state_machine.change_state("PlayerDash") 
		return 
		
	if Input.is_action_just_pressed("attack"):    
		state_machine.change_state("PlayerAttack") 
		return 
		
	# --- 停止移動偵測 ---
	if character.input_direction == Vector2.ZERO: 
		state_machine.change_state("PlayerIdle") 
		return 

	# --- 擊退鎖定 ---
	# 若擊退組件發力中，暫停輸入覆蓋，讓物理滑行自然完成
	if character.knockback_component and character.knockback_component.knockback_force.length() > 0.0:
		character.play_animation("move")
		return 

	# --- 🌟 執行移動 ---
	# 【改動】：拔除了 is_overheated 的速度減半懲罰，還原為暢快的等速移動。
	character.velocity = character.input_direction * character.walk_speed 
	character.play_animation("move")

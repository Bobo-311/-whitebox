extends State # 繼承自狀態機的 State 模板，代表這是一個可切換的狀態 player_move

func state_physics_update(delta: float): # 內建虛擬函數：在物理引擎的每一幀(1/60秒)都會被大腦呼叫
	
	# --- 🌟 動作指令偵測 (最高優先級，確保邊走邊按會有反應) ---
	if Input.is_action_just_pressed("dash"):      # 偵測玩家是否按下了翻滾衝刺鍵 (Dash)
		state_machine.change_state("PlayerDash") # 命令大腦切換到翻滾狀態
		return # 直接跳出函數，不執行後面的移動邏輯
		
	if Input.is_action_just_pressed("attack"):    # 偵測玩家是否按下了攻擊鍵 (Attack)
		state_machine.change_state("PlayerAttack") # 命令大腦切換到攻擊狀態
		return # 直接跳出函數
		
	if Input.is_action_just_pressed("heal"):      # 偵測玩家是否按下了補血鍵 (Heal)
		state_machine.change_state("PlayerHeal") # 命令大腦切換到補血狀態
		return # 直接跳出函數

	# --- 停止移動偵測 ---
	if character.input_direction == Vector2.ZERO: # 條件判斷：如果玩家沒有輸入任何方向鍵 (原地站著)
		state_machine.change_state("PlayerIdle") # 命令大腦切換回待機狀態 (PlayerIdle)
		return # 直接跳出函數

	# --- 🌟 核心：動態跑速計算 (過熱減速懲罰) ---
	var current_speed: float = character.walk_speed # 宣告一個暫存變數，先把玩家正常的走路速度裝進去
	
	if character.is_overheated: # 檢查玩家大腦：現在是不是處於過熱/力竭狀態？
		current_speed = character.walk_speed * 0.5 # 如果處於過熱狀態，把速度強制打對折，呈現無力感

	# --- 執行移動 ---
	# 賦予玩家移動物理量：將玩家按下的方向向量，乘上剛剛算好的最終速度
	character.velocity = character.input_direction * current_speed 
	
	character.play_animation("move") # 呼叫玩家本體的動畫函數，播放移動動畫

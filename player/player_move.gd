extends State

func enter():
	pass

# 🌟 這裡的函數名稱必須加上 state_
func state_physics_update(_delta: float):
	# 1. 從大腦 (player.gd) 取得玩家目前的 WASD 輸入向量
	var direction = character.input_direction

	# 2. 【狀態切換判斷】
	# 如果玩家鬆開了方向鍵，切換回待機狀態
	if direction == Vector2.ZERO:
		state_machine.change_state("PlayerIdle")
		return

	# 如果玩家按下翻滾鍵，且 CD 轉好了，切換到翻滾狀態
	if Input.is_action_just_pressed("dash") and character.is_dash_ready:
		state_machine.change_state("PlayerDash")
		return

	# 3. 【處理移動與動畫】
	# 給予玩家速度
	character.velocity = direction * character.walk_speed
	
	# 自動判定 8 方向動畫
	character.play_animation("move")

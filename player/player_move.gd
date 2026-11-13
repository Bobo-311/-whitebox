# --- PlayerMove.gd ---
extends State

func enter():
	pass

# 🌟 大腦每一物理幀都會呼叫這裡，處理玩家「走路中」的行為
func state_physics_update(_delta: float):
	# 取得玩家現在按下的 WASD 向量
	var direction = character.input_direction

	# ==========================================
	# 【狀態切換判斷】(優先權從高到低)
	# ==========================================
	
	# 🌟【最優先：無縫起手揮刀】
	# 類似《黑帝斯》：走路途中只要按下攻擊鍵，立刻中斷移動，強行切入攻擊狀態。
	# (進入攻擊狀態後會強制煞車定桿，所以絕對不會邊走邊砍)
	if Input.is_action_just_pressed("attack"):
		state_machine.change_state("PlayerAttack")
		return # 立刻中斷這個腳本，不往下執行，保證乾淨俐落

	# 【第二優先：翻滾衝刺】
	if Input.is_action_just_pressed("dash") and character.is_dash_ready:
		state_machine.change_state("PlayerDash")
		return

	# 【第三優先：停下腳步退回待機】
	if direction == Vector2.ZERO:
		state_machine.change_state("PlayerIdle")
		return

	# ==========================================
	# 【處理正常移動與動畫】
	# ==========================================
	# 如果沒按攻擊也沒按翻滾，就正常給予速度並播放走路動畫
	character.velocity = direction * character.walk_speed
	character.play_animation("move")

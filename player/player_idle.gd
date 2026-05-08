# --- PlayerIdle.gd ---
extends State

func enter():
	character.velocity = Vector2.ZERO             # 速度歸零
	character.play_animation("idle")  

func state_physics_update(_delta: float):
	if character.input_direction != Vector2.ZERO: # 偵測到移動輸入
		state_machine.change_state("PlayerMove") 
	if Input.is_action_just_pressed("attack"):    # 偵測攻擊
		state_machine.change_state("PlayerAttack") 
	if Input.is_action_just_pressed("heal"):      # 偵測補血
		state_machine.change_state("PlayerHeal")

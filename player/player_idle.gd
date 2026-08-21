# --- PlayerIdle.gd ---
extends State

func enter():
	# 🌟【關鍵修復】只要 KnockbackComponent 還在發力滑行，就不在進入待機時強行歸零！
	if not (character.knockback_component and character.knockback_component.knockback_force.length() > 0.0):
		character.velocity = Vector2.ZERO
		
	character.play_animation("idle")  

func state_physics_update(_delta: float):
	# 🌟【擊退保護】若正處於擊退滑行狀態，暫停待機邏輯干預，讓組件平滑煞車
	if character.knockback_component and character.knockback_component.knockback_force.length() > 0.0:
		return

	if character.input_direction != Vector2.ZERO: # 偵測到移動輸入
		state_machine.change_state("PlayerMove") 
		return
		
	if Input.is_action_just_pressed("attack"):    # 偵測攻擊
		state_machine.change_state("PlayerAttack") 
		return
		

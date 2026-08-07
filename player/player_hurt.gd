# --- PlayerHurt.gd ---
extends State

var timer: float = 0.3           # 玩家受傷硬直：0.3 秒

func enter():
	timer = 0.3
	character.play_animation("hurt")
	
	# 🌟【關鍵修復 1】受傷紅閃特效
	character.animated_sprite_2d.modulate = Color.RED # 身體變紅
	var tween = character.get_tree().create_tween()
	tween.tween_property(character.animated_sprite_2d, "modulate", Color.WHITE, 0.3)
	
	# 🌟【關鍵修復 2】將震動數值從 80.0 降至 3.5，並統一修正群組名稱為 "main_camera"
	# 傳入 3.5 會換算出約 0.23 的溫和 Trauma，讓受傷有抖動反饋，但完全不影響視線！
	get_tree().call_group("main_camera", "apply_shake", 7.0)

func state_physics_update(delta: float):
	timer -= delta
	
	if timer <= 0:
		state_machine.change_state("PlayerIdle")

func exit():
	character.animated_sprite_2d.modulate = Color.WHITE # 保險恢復顏色

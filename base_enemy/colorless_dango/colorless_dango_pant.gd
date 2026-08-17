extends State

var pant_timer: float = 1.0 # 企劃設定：撞到人之後發呆 1 秒

func enter():
	pant_timer = 1.0
	character.velocity = Vector2.ZERO # 原地煞車
	character.play_animation("idle", character.last_facing_vec) # 播放發呆動畫

func state_physics_update(delta: float):
	pant_timer -= delta
	if pant_timer <= 0:
		state_machine.change_state("Chase") # 1 秒後，繼續追！

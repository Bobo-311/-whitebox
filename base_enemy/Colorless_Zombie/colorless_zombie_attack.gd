extends State

var has_finished_attack: bool = false # 防止重複切換的開關

func enter():
	character.velocity = Vector2.ZERO # 停在原地
	has_finished_attack = false
	
	# 🌟 剛進入攻擊狀態時，先關閉 Hitbox，確保「抬手前搖」絕對安全
	if character.hitbox:
		character.hitbox.set_deferred("monitoring", false)
	
	character.play_animation("attack")
	print("【系統】進入 Attack 狀態！開始揮手！")

func exit():
	# 離開時買個保險，一定會關閉 Hitbox
	if character.hitbox:
		character.hitbox.set_deferred("monitoring", false)

func state_physics_update(_delta: float):
	var anim = character.animated_sprite_2d
	var current_frame = anim.frame
	var anim_name = anim.animation
	
	# 確保現在真的是在播放攻擊動畫
	if "attack" in anim_name:
		
		# 🌟 1. 精準打擊：第 7 到 10 幀才開啟傷害！(刀光出現)
		if current_frame >= 7 and current_frame <= 10:
			character.hitbox.set_deferred("monitoring", true)
		else:
			character.hitbox.set_deferred("monitoring", false)
			
		# 🌟 2. 暴力防呆切換：看到最後一幀就踢去發呆！
		var max_frame = anim.sprite_frames.get_frame_count(anim_name) - 1
		
		if current_frame == max_frame and not has_finished_attack:
			has_finished_attack = true
			print("【攻擊腳本】揮手完畢！準備切換到 Pant 狀態！")
			state_machine.change_state("Pant")

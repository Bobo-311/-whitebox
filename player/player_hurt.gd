# --- PlayerHurt.gd ---
extends State

var timer: float = 0.3           # 玩家受傷硬直：0.3 秒

func enter():
	timer = 0.3
	character.play_animation("hurt")
	character.velocity = character.knockback_force # 接管擊退力道
	
	character.animated_sprite_2d.modulate = Color.RED # 身體變紅
	var tween = character.get_tree().create_tween()
	tween.tween_property(character.animated_sprite_2d, "modulate", Color.WHITE, 0.3)
	
	# 🌟 新增：呼叫鏡頭震動 (強度設定為 10.0，你可以自己調大小)
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera:
		camera.apply_shake(50.0)

func state_physics_update(delta: float):
	timer -= delta
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15) # 摩擦滑行
	if timer <= 0:
		state_machine.change_state("PlayerIdle")

func exit():
	character.animated_sprite_2d.modulate = Color.WHITE # 保險恢復顏色

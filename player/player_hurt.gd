# --- PlayerHurt.gd ---
extends State

var timer: float = 0.3           # 玩家受傷硬直：0.3 秒

func enter():
	timer = 0.3
	character.play_animation("hurt")
	
	# 🌟【關鍵修復 1】移除 character.velocity = character.knockback_force！
	# 擊退速度在 Player.gd 的 take_damage 觸發時已由 KnockbackComponent 接管。
	
	character.animated_sprite_2d.modulate = Color.RED # 身體變紅
	var tween = character.get_tree().create_tween()
	tween.tween_property(character.animated_sprite_2d, "modulate", Color.WHITE, 0.3)
	
	# 呼叫鏡頭震動
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(80.0)

func state_physics_update(delta: float):
	timer -= delta
	
	# 🌟【關鍵修復 2】完全移除 character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15)！
	# 原本這行程式碼會在每一幀把速度急速拉回 ZERO，直接覆蓋掉 KnockbackComponent 的 Friction 阻尼計算！
	
	if timer <= 0:
		state_machine.change_state("PlayerIdle")

func exit():
	character.animated_sprite_2d.modulate = Color.WHITE # 保險恢復顏色

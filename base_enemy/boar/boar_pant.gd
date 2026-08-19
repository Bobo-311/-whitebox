extends State #boar_pant

var pant_timer: float = 2.0      
var flash_tween: Tween           

func enter(): 
	pant_timer = 2.0             
	character.play_animation("idle", character.last_facing_vec) 
	
	# 🆕【本次修改】喘氣閃綠光 (揮空專屬)
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	flash_tween = character.get_tree().create_tween().bind_node(character) 
	flash_tween.set_loops() 
	flash_tween.tween_property(character.animated_sprite_2d.material, "shader_parameter/state_color", Color.GREEN, 0.2) 
	flash_tween.tween_property(character.animated_sprite_2d.material, "shader_parameter/state_color", Color.WHITE, 0.2)

func state_physics_update(delta: float): 
	pant_timer -= delta 
	
	# 🌟【專屬煞車系統】：奪回摩擦力控制權！
	# 無論 KnockbackComponent 推得多大力，在這裡都會被這行強制套用 15% 的沉重煞車感。
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15)
		
	if pant_timer <= 0: 
		if character.player_node and character.can_see_player:
			state_machine.change_state("Chase") 
		else:
			state_machine.change_state("Move")
			
func exit(): 
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 【離開狀態時，強制洗白】
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)
	character.can_attack = true

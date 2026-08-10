extends State

var stun_timer: float = 3.0      
var flash_tween: Tween           

func enter():                    
	stun_timer = 3.0             
	character.play_animation("idle", character.last_facing_vec)  

	# 🆕【本次修改】暈眩閃紫光 (使用 Color(0.8, 0.2, 1.0) 讓紫色更鮮豔)
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	flash_tween = character.get_tree().create_tween().bind_node(character) 
	flash_tween.set_loops()      
	flash_tween.tween_property(character.animated_sprite_2d.material, "shader_parameter/state_color", Color(0.8, 0.2, 1.0), 0.2) 
	flash_tween.tween_property(character.animated_sprite_2d.material, "shader_parameter/state_color", Color.WHITE, 0.2)   

func state_physics_update(delta: float): 
	stun_timer -= delta        
	
	# 🌟【專屬煞車系統】：奪回摩擦力控制權！
	# 與喘氣狀態一樣，套用 15% 的減速魔法，讓暈眩後的滑行距離感完全統一。
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15)
		
	if stun_timer <= 0:        
		if character.player_node and character.can_see_player:
			state_machine.change_state("EnemyRun")
		else:
			state_machine.change_state("EnemyMove")

func exit():                     
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 【離開狀態時，強制洗白改成這樣】
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)
	character.can_attack = true

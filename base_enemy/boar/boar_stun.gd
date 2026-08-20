extends State #boar_stun

var stun_timer: float = 3.0      
var flash_tween: Tween           
var custom_duration: float = 0.0 # 🌟 新增：這就是我們的「預約信箱」

func enter():                    
	# 🌟 聰明的判斷：如果有人投遞了預約秒數，就用他的；沒有的話，預設就是 3 秒！
	if custom_duration > 0.0:
		stun_timer = custom_duration
		custom_duration = 0.0 # 🌟 用完立刻把信箱清空，避免影響下次野豬自己撞牆！
	else:
		stun_timer = 3.0 # 野豬撞牆或撞玩家的預設 3 秒
		
	character.play_animation("idle", character.last_facing_vec)  

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
			state_machine.change_state("Chase")
		else:
			state_machine.change_state("Move")

func exit():                     
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 【離開狀態時，強制洗白改成這樣】
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)
	character.can_attack = true

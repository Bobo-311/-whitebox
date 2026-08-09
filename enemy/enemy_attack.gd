extends State # 繼承自狀態模板 enemy_attack

var is_charging: bool = true 
var charge_timer: float = 0.6 
var dash_timer: float = 1.5 
var dash_dir: Vector2 = Vector2.ZERO 
var flash_tween: Tween 

func enter(): 
	character.can_attack = false 
	character.has_hit_player = false 
	is_charging = true 
	charge_timer = 0.6 
	dash_timer = 1.5 

	character.velocity = Vector2.ZERO 
	
	if character.player_node: 
		dash_dir = (character.player_node.global_position - character.global_position).normalized() 
	else: 
		dash_dir = character.last_facing_vec 
	
	character.last_facing_vec = dash_dir 
	character.play_animation("idle", dash_dir) 

	# 🆕【本次修改】蓄力閃紅光 (統一使用 modulate 確保生效)
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	flash_tween = character.get_tree().create_tween().bind_node(character) 
	flash_tween.set_loops() 
	flash_tween.tween_property(character.animated_sprite_2d.material, "shader_parameter/state_color", Color.RED, 0.15) 
	flash_tween.tween_property(character.animated_sprite_2d.material, "shader_parameter/state_color", Color.WHITE, 0.15)

func state_physics_update(_delta: float): 
	if is_charging: 
		character.velocity = Vector2.ZERO 
		charge_timer -= _delta 
		if charge_timer <= 0: 
			_start_dash() 
	else: 
		dash_timer -= _delta 
		character.velocity = dash_dir * (character.sprint_speed * 3.0) 
		character.play_animation("run", dash_dir) 

		if character.has_hit_player: 
			_end_dash("hit_player") 
			return

		if dash_timer < 1.4 and character.is_on_wall(): 
			var wall_normal = character.get_wall_normal() 
			character.move_and_collide(wall_normal * 30.0) 
			character.get_tree().call_group("main_camera", "apply_shake", 6.0) 
			_end_dash("stun") 
			return

		if dash_timer <= 0: 
			_end_dash("miss") 
			return

func _start_dash(): 
	is_charging = false 
	character.has_hit_player = false 
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 【衝刺開始時，強制洗白改成這樣】
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)

func _end_dash(outcome: String): 
	character.velocity = Vector2.ZERO 

	# 🆕【本次修改】撞牆 或 撞到玩家 ➔ 全部統一進入暈眩 (EnemyStun)
	if outcome == "stun" or outcome == "hit_player": 
		state_machine.change_state("EnemyStun") 
		
	# 🆕【本次修改】什麼都沒撞到 (揮空) ➔ 進入喘氣 (EnemyPant)
	elif outcome == "miss": 
		state_machine.change_state("EnemyPant") 

func exit(): 
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 【離開狀態時，強制洗白改成這樣】
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)

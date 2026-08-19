extends State # 繼承自狀態模板 boar_attack

var is_charging: bool = true 
var charge_timer: float = 0.6 
var dash_timer: float = 1.5 
var dash_dir: Vector2 = Vector2.ZERO 
var flash_tween: Tween 

# 🌟 補上衝刺速度變數 (數值可以自由調整)
@export var sprint_speed: float = 200.0


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

	# 🌟【舊有修改】蓄力閃紅光 (統一使用 modulate 確保生效)
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
		character.velocity = dash_dir * (sprint_speed * 3.0)
		character.play_animation("run", dash_dir) 

		# 🌟🌟🌟【全新修改：狀態機獨立雷達系統】🌟🌟🌟
		# 取代原本的 character.has_hit_player，讓攻擊狀態自己偵測有沒有撞到人！
		var hitbox = character.get_node_or_null("Hitbox")
		if hitbox:
			for area in hitbox.get_overlapping_areas():
				if area is Hurtbox: # 如果掃描到玩家的受傷區
					print("【系統】野豬撞到玩家了！立刻煞車！")
					_end_dash("hit_player") # 傳遞撞到玩家的結果
					return # 立刻終止物理更新，不讓牠繼續跑
		# 🌟🌟🌟---------------------------------🌟🌟🌟

		# 🌟【舊有邏輯】判定撞牆
		if dash_timer < 1.4 and character.is_on_wall(): 
			var wall_normal = character.get_wall_normal() 
			character.move_and_collide(wall_normal * 30.0) 
			character.get_tree().call_group("main_camera", "apply_shake", 6.0) 
			_end_dash("stun") 
			return

		# 🌟【舊有邏輯】判定沒氣 (揮空)
		if dash_timer <= 0: 
			_end_dash("miss") 
			return

func _start_dash(): 
	is_charging = false 
	character.has_hit_player = false 
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 🌟【舊有修改】衝刺開始時，強制洗白
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)
	# 🌟🌟🌟【新增】：衝刺真正開始的瞬間，才把攻擊判定(刺)打開！
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", false)

func _end_dash(outcome: String): 
	character.velocity = Vector2.ZERO
	
	# 🌟🌟🌟【新增】：不管撞到牆、撞到人還是揮空，攻擊結束立刻把判定(刺)收起來！
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true)

	# 🌟【重點修改】撞牆 或 撞到玩家 ➔ 全部統一進入新節點 "Stun"
	if outcome == "stun" or outcome == "hit_player": 
		state_machine.change_state("Stun") 
		
	# 🆕【本次修改】什麼都沒撞到 (揮空) ➔ 進入喘氣 (EnemyPant)
	elif outcome == "miss": 
		state_machine.change_state("Pant") 

func exit(): 
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() 
	# 🌟【舊有修改】離開狀態時，強制洗白
	character.animated_sprite_2d.material.set_shader_parameter("state_color", Color.WHITE)
	
	# 🌟🌟🌟【新增】：保險機制，只要離開攻擊狀態，絕對強制關閉判定！
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true)

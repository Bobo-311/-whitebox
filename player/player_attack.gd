extends State # 繼承自狀態模板

# 預載粒子特效 (避免揮刀時卡頓)
const INK_SLASH_PARTICLES = preload("res://近戰/ink_slash_particles.tscn")

func enter(): # 大腦切換到攻擊狀態時執行
	# 🌟【改動】：徹底拔除 use_sp 審查，玩家可無限制普攻輸出
	
	character.velocity = Vector2.ZERO # 強制煞車，避免揮刀滑步
	character.play_animation("attack") 
	
	# 播放揮劍音效
	var sfx_sword = character.get_node_or_null("SFXSword") 
	if sfx_sword: 
		sfx_sword.play() 
	
	spawn_slash_particles() # 生成墨水殘影

	# 抓取對應方向的判定框
	var sword_hitbox = character.get_node("Hitbox") 
	var target_coll = sword_hitbox.get_node("CollisionShape_" + character.facing_direction) 
	
	sword_hitbox.monitoring = true 
	target_coll.disabled = false   
	
	# 【正規作法】：對齊物理幀，確保 Area2D 重疊判定更新完畢，消除空揮延遲感
	await character.get_tree().physics_frame
	
	var targets = sword_hitbox.get_overlapping_areas() 
	
	# 逐一結算傷害
	for t in targets: 
		if t is Hurtbox and t.get_parent() != character: # 確保砍到的不是自己
			var final_damage: float = character.get_current_basic_attack_damage()
			var attack_dir: Vector2 = (t.global_position - character.global_position).normalized()
			# 傳入 true 觸發近戰專屬處決/補彈機制
			t.take_damage(final_damage, character.global_position, attack_dir, true)
	
	# 關閉判定框
	target_coll.disabled = true     
	sword_hitbox.monitoring = false 
	
	# 保留 0.2 秒收刀後搖，動作結束後切回待機
	await character.get_tree().create_timer(0.2).timeout 
	state_machine.change_state("PlayerIdle") 

# 生成墨水殘影方向控制
func spawn_slash_particles() -> void:
	if not INK_SLASH_PARTICLES: return
	
	var particles = INK_SLASH_PARTICLES.instantiate()
	var spawn_offset = Vector2.ZERO
	var attack_dir = Vector2.RIGHT
	
	match character.facing_direction:
		"right":
			spawn_offset = Vector2(25, -5)
			attack_dir = Vector2.RIGHT
		"left":
			spawn_offset = Vector2(-25, -5)
			attack_dir = Vector2.LEFT
		"up":
			spawn_offset = Vector2(0, -30)
			attack_dir = Vector2.UP
		"down":
			spawn_offset = Vector2(0, 20)
			attack_dir = Vector2.DOWN
			
	particles.global_position = character.global_position + spawn_offset
	particles.rotation = attack_dir.angle()
	# 加到地圖層級，避免玩家走動帶著粒子走
	character.get_parent().add_child(particles)

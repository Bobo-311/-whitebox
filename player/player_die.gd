extends State # 繼承自狀態模板 player_die

func enter(): # 進入死亡狀態時執行
	# 🌟【修改：精準播放】
	# 死亡動畫通常不分方向，直接指定動畫名稱最保險，避免後綴出錯。
	# 請確保你的 AnimatedSprite2D 裡面確實有一個名叫 "die_down" (或 "die") 的動畫！
	if character.animated_sprite_2d:
		# 這裡假設你的死亡動畫叫 "die_down"，如果只有 "die"，請改成 "die"
		character.animated_sprite_2d.play("dead_down") 
	
	# 強制關閉肉體碰撞，避免屍體擋路
	var col = character.get_node_or_null("CollisionShape2D") 
	if col: col.set_deferred("disabled", true) 
	
	# 🌟【修改：等待動畫】
	# 不要急著跑後面的邏輯，先等倒地動畫播完！這能確保玩家一定看得到自己倒地。
	if character.animated_sprite_2d:
		await character.animated_sprite_2d.animation_finished
	
	# 動畫播完後，才開始處理噴錢與生靈魂
	_handle_death_penalty()
	
	# 呼叫重啟遊戲流程
	_restart_game()

# 物理幀更新 (讓可能殘留的微小速度徹底歸零)
func state_physics_update(delta: float): 
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15) 
	character.move_and_slide() # 確保屍體受到阻力停下

# 處理噴錢與生成靈魂的邏輯 (從原本的 enter 裡抽出來，保持整潔)
func _handle_death_penalty():
	if DataManager: 
		var penalty = int(DataManager.total_gold / 2) 
		DataManager.total_gold -= penalty 
		
		DataManager.has_soul_on_ground = true 
		DataManager.soul_spawn_pos = character.global_position 
		DataManager.soul_stored_gold = penalty 
		DataManager.soul_map_path = character.get_tree().current_scene.scene_file_path
		
		print("【系統】玩家死亡！遺失金幣：", penalty) 
		
		var soul_scene = load("res://soul/Soul.tscn") 
		if soul_scene: 
			var soul = soul_scene.instantiate() 
			soul.global_position = character.global_position 
			soul.lost_gold = penalty 
			soul.scale = Vector2(2.0, 2.0) 
			character.get_tree().current_scene.call_deferred("add_child", soul) 

# 處理重啟遊戲
func _restart_game(): 
	# 讓屍體在地上躺 2 秒鐘 (加上前面播動畫的時間，大約就是 3 秒)
	await character.get_tree().create_timer(2.0).timeout 
	
	if DataManager.save_map_path != "":
		character.get_tree().change_scene_to_file(DataManager.save_map_path)
	else:
		character.get_tree().reload_current_scene()

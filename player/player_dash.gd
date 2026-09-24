extends State # 繼承自狀態模板 player_dash

func enter(): # 當狀態機切換到衝刺翻滾狀態時執行
	# 🌟【改動】：拔除扣體力，改為檢查玩家本體的 Dash 開關 (is_dash_ready)
	# 【正規作法】：只有開關為 true (冷卻完畢) 才放行，防禦玩家狂按無效動作
	if character.is_dash_ready: 
		
		# 1. 翻滾成功，立刻關閉開關，並把計時器填滿開始倒數
		character.is_dash_ready = false
		character.dash_cd_timer = character.dash_cd_time 
		
		# 2. 賦予爆發力與無敵幀 (維持原有完美邏輯)
		character.velocity = character.input_direction * character.dash_speed 
		character.is_dashing = true 
		
		character.play_animation("move") # 播放移動動畫墊檔
		character.modulate.a = 0.5       # 半透明靈體感
		
		# 播放 AnimationPlayer 裡面寫好的無敵幀開關時間軸
		var anim_player = character.get_node("AnimationPlayer") 
		if anim_player: 
			anim_player.play("dash_iframes") 
		
		# 3. 翻滾維持 0.2 秒後結束，命令大腦切回待機
		await character.get_tree().create_timer(character.dash_duration).timeout 
		state_machine.change_state("PlayerIdle") 
		
	else: 
		# CD 還沒轉好，不給翻，強制退回待機
		state_machine.change_state("PlayerIdle") 

func exit(): # 善後清理函數
	character.is_dashing = false # 關閉動作鎖
	character.modulate.a = 1.0   # 恢復實體透明度
	
	# 強制呼叫 RESET 洗回預設屬性，作為終極保險，防止卡無敵框
	var anim_player = character.get_node("AnimationPlayer") 
	if anim_player: 
		anim_player.play("RESET")

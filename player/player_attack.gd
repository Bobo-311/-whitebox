extends State # 讓這個腳本繼承自狀態機的 State 模板 player_attack

func enter(): # 當狀態機切換到這個攻擊狀態時執行一次
	# 🌟 第一步：先向身體申請扣除體力
	if character.use_sp(7.0): # 呼叫玩家的 use_sp 函數申請扣除 7 點體力，並檢查是否成功
		
		character.velocity = Vector2.ZERO # 攻擊成功，揮刀時不能走路，強制將移動速度歸零
		character.play_animation("attack") # 呼叫玩家播放揮刀砍擊的動畫
		
		var sfx_sword = character.get_node_or_null("SFXSword") # 在玩家身上尋找名稱為 SFXSword 的音效節點
		if sfx_sword: # 如果有找到音效節點
			sfx_sword.play() # 播放揮劍的聲音效果
		
		var sword_hitbox = character.get_node("Hitbox") # 抓取玩家身上負責近戰攻擊判定的 Hitbox 節點
		var target_coll = sword_hitbox.get_node("CollisionShape_" + character.facing_direction) # 依照玩家目前面朝的方向，尋找對應的碰撞形狀節點
		
		sword_hitbox.monitoring = true # 將 Hitbox 的偵測雷達開啟，允許感應其他區域
		target_coll.disabled = false   # 將對應方向的碰撞形狀啟用，讓它具備實體感應能力
		
		await character.get_tree().create_timer(0.25).timeout # 使用等待指令暫停 0.25 秒，配合動畫播到武器揮出去的那一瞬間 (前搖)
		
		var targets = sword_hitbox.get_overlapping_areas() # 抓取目前重疊在劍氣感應區裡的所有 Area2D 目標
		
		for t in targets: # 使用迴圈，逐一檢查砍到的每一個目標物
			if t is Hurtbox and t.get_parent() != character: # 條件判斷：確保砍到的是 Hurtbox 組件，且該組件的主人不是玩家自己
				
				var final_damage: float = character.basic_attack_damage * character.get_oversaturation_buff() # 計算傷害：玩家基礎攻擊力乘以過飽和系統給予的倍率
				
				t.take_damage(final_damage, character.global_position) # 呼叫目標 Hurtbox 的受傷函數，傳入算好的傷害量與玩家目前的絕對座標
				
				if t.get_parent() is Enemy: # 條件判斷：如果這個 Hurtbox 的主人屬於敵人 (Enemy) 類別
					character.add_energy(5) # 呼叫玩家身體的函數，回復 5 點能量作為命中獎勵
		
		target_coll.disabled = true     # 傷害判定結算完畢，將該方向的碰撞形狀重新關閉
		sword_hitbox.monitoring = false # 將 Hitbox 的偵測雷達關閉，結束攻擊判定
		
		await character.get_tree().create_timer(0.25).timeout # 再次使用等待指令暫停 0.25 秒，讓收招動畫完整播完 (後搖)
		state_machine.change_state("PlayerIdle") # 整個攻擊動作與動畫結束，命令大腦切換回待機狀態

	else: # 如果體力扣除失敗 (體力不足或是系統正在過熱中)
		print("體力不足或系統過熱，無法揮刀！") # 在後台印出拒絕揮刀的警告訊息
		state_machine.change_state("PlayerIdle") # 強制中斷流程，命令大腦退回待機狀態

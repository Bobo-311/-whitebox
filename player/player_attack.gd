#player_attack
extends State # 讓這個腳本繼承自狀態機的 State 模板

func enter(): # 當大腦切換到「攻擊狀態」時，立刻執行此函數
	# 第一步：先向身體申請扣除揮刀所需的體力
	if character.use_sp(7.0): # 呼叫玩家的 use_sp 函數申請扣除 7 點體力，並檢查是否扣除成功
		
		character.velocity = Vector2.ZERO # 攻擊成功，揮刀時嚴禁滑步，強制將玩家移動速度歸零
		character.play_animation("attack") # 呼叫玩家腳本，播放對應方向的揮刀動畫
		
		var sfx_sword = character.get_node_or_null("SFXSword") # 在玩家身上尋找名稱為 SFXSword 的音效播放器節點
		if sfx_sword: # 防呆檢查：如果有找到音效節點
			sfx_sword.play() # 播放揮劍的咻咻聲音效
		
		var sword_hitbox = character.get_node("Hitbox") # 抓取玩家身上負責近戰攻擊判定的 Hitbox (Area2D) 節點
		var target_coll = sword_hitbox.get_node("CollisionShape_" + character.facing_direction) # 依照玩家目前面朝的方向，找出真正該啟用的那個碰撞框形狀
		
		sword_hitbox.monitoring = true # 將 Hitbox 的偵測雷達開啟，開始監聽有沒有碰到敵人
		target_coll.disabled = false   # 將我們剛剛找出的那個方向的碰撞框啟用，賦予它實體感應能力
		
		await character.get_tree().create_timer(0.25).timeout # 使用等待指令暫停 0.25 秒，配合動畫播到「武器揮出去」那一瞬間的發力延遲
		
		var targets = sword_hitbox.get_overlapping_areas() # 抓取此時此刻，重疊在感應區裡的所有物體 (回傳陣列)
		
		for t in targets: # 使用迴圈，逐一檢查刀子砍到的每一個目標物
			if t is Hurtbox and t.get_parent() != character: # 條件判斷：確保砍到的是受傷判定區 (Hurtbox)，且該區域的主人不是玩家自己 (避免砍到自己)
				
				# 🌟🌟🌟 [特別函數的應用點] 🌟🌟🌟
				# 1. 呼叫 get_current_basic_attack_damage() 拿普攻基底傷害 (沒發動是 15，發動起床氣是 20.25)
				# 2. 呼叫 get_oversaturation_buff() 拿過飽和倍率 (沒滿能量是 1.0，滿能量是 1.5)
				# 3. 兩個數字相乘，算出這一刀最終極的真實傷害！
				var final_damage: float = character.get_current_basic_attack_damage() * character.get_oversaturation_buff() 
				
				t.take_damage(final_damage, character.global_position) # 呼叫敵人 Hurtbox 的受傷函數，傳入算好的最終傷害量與玩家座標
				
				if t.get_parent() is Enemy: # 條件判斷：如果這個 Hurtbox 的主人確實屬於敵人 (Enemy) 類別
					character.add_energy(5) # 呼叫玩家身體的函數，回復 5 點能量作為砍中敵人的獎勵
		
		target_coll.disabled = true     # 傷害判定結算完畢，將該方向的碰撞框重新關閉 (收刀)
		sword_hitbox.monitoring = false # 將 Hitbox 的偵測雷達關閉，結束這回合的攻擊判定
		
		await character.get_tree().create_timer(0.25).timeout # 再次使用等待指令暫停 0.25 秒，讓角色的收招動作動畫完整播完
		state_machine.change_state("PlayerIdle") # 整個攻擊動作完整結束，命令大腦切換回「待機狀態 (Idle)」

	else: # 如果一開始體力扣除失敗 (沒體力了，或是系統正在過熱中)
		print("體力不足或系統過熱，無法揮刀！") # 在後台印出拒絕揮刀的警告訊息
		state_machine.change_state("PlayerIdle") # 強制中斷攻擊流程，命令大腦立刻退回「待機狀態」

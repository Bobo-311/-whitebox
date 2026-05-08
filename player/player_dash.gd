extends State # 讓這個腳本繼承自狀態機的 State 模板

func enter(): # 當狀態機切換到衝刺翻滾狀態時執行一次
	# 🌟 第一步：先向身體申請扣除體力
	if character.use_sp(7.0): # 呼叫玩家的 use_sp 函數申請扣除 7 點體力，並檢查是否成功
		
		character.velocity = character.input_direction * character.dash_speed # 衝刺成功，將玩家目前按下的方向向量乘以衝刺爆發速度，賦予玩家移動力
		character.is_dashing = true # 將玩家身上的衝刺標記開關打開為 true
		
		character.play_animation("move") # 呼叫玩家播放移動動畫來作為衝刺的墊檔視覺效果
		character.modulate.a = 0.5       # 將玩家身體圖片的 Alpha 透明度改為 0.5，呈現半透明的無敵靈體感
		
		var anim_player = character.get_node("AnimationPlayer") # 在玩家身上抓取 AnimationPlayer 動畫時間軸節點
		if anim_player: # 如果有成功抓到該節點
			anim_player.play("dash_iframes") # 命令它播放名為 dash_iframes 的無敵幀動畫 (用來關閉受傷區)
		
		await character.get_tree().create_timer(character.dash_duration).timeout # 使用等待指令，暫停執行直到翻滾的總設定時間 (0.2秒) 走完
		
		state_machine.change_state("PlayerIdle") # 翻滾時間結束，命令大腦切換回待機狀態
		
	else: # 如果體力扣除失敗 (體力不足或是系統正在過熱中)
		print("體力不足或系統過熱，無法翻滾！") # 在後台印出拒絕翻滾的警告訊息
		state_machine.change_state("PlayerIdle") # 強制中斷流程，命令大腦退回待機狀態

func exit(): # 當大腦準備離開衝刺狀態，切換到下一個狀態前執行一次的善後函數
	character.is_dashing = false # 將玩家身上的衝刺標記開關關閉，恢復為 false
	character.modulate.a = 1.0   # 將玩家身體圖片的 Alpha 透明度改回 1.0，從半透明恢復成實體
	
	var anim_player = character.get_node("AnimationPlayer") # 再次抓取動畫時間軸節點
	if anim_player: # 如果有抓到節點
		anim_player.play("RESET") # 呼叫 RESET 動畫，強制將所有被動過的屬性 (如無敵框的開關) 洗回原始預設值，作為終極保險

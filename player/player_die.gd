extends State # 繼承自狀態模板

func enter(): # 進入死亡狀態時執行
	character.play_animation("dead") # 播放玩家死亡倒地動畫
	
	if DataManager: # 如果全域大腦節點存在
		var penalty = int(DataManager.total_gold / 2) # 將身上總金幣除以二並取整數
		DataManager.total_gold -= penalty # 大腦總金額直接扣除這一半金幣
		
		DataManager.has_soul_on_ground = true # 告訴大腦：現在有靈魂掉在外面了
		DataManager.soul_spawn_pos = character.global_position # 記錄靈魂掉落的精確座標
		DataManager.soul_stored_gold = penalty # 把剛剛扣掉的錢交給大腦的靈魂紀錄保管
		
		print("【系統】玩家死亡！遺失金幣：", penalty) # 後台印出噴錢提示
		
		var soul_scene = load("res://soul/Soul.tscn") # 載入你路徑正確的靈魂場景
		if soul_scene: # 如果載入檔案成功
			var soul = soul_scene.instantiate() # 將靈魂場景實例化出來
			soul.global_position = character.global_position # 將靈魂位置設定在玩家死掉的地方
			soul.lost_gold = penalty # 將懲罰金額塞進這個靈魂實體的變數裡
			soul.scale = Vector2(2.0, 2.0) # 將靈魂放大 2 倍解決你說太小的問題
			character.get_tree().current_scene.call_deferred("add_child", soul) # 延遲將靈魂加進關卡地圖中
	
	var col = character.get_node_or_null("CollisionShape2D") # 抓取玩家的肉體碰撞節點
	if col: col.set_deferred("disabled", true) # 強制關閉碰撞避免屍體擋路
	
	character.velocity = character.knockback_force # 套用野豬撞擊的最後擊退力道
	_restart_game() # 呼叫重啟遊戲流程

func state_physics_update(delta: float): # 物理幀更新
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15) # 加上摩擦力讓屍體慢慢煞車停下

func _restart_game(): # 處理重啟遊戲
	await character.get_tree().create_timer(3.0).timeout # 讓屍體在地上躺 3 秒鐘
	character.get_tree().reload_current_scene() # 重新載入關卡，觸發重生點與靈魂重生的機制

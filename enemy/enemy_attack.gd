extends State                    # 繼承自狀態模板

var is_charging: bool = true     # 狀態開關：記錄是否正在「蓄力」，預設為 true
var charge_timer: float = 0.6    # 計時器：蓄力動作維持 0.6 秒
var dash_timer: float = 1.5      # 計時器：衝刺狂飆最多維持 1.5 秒
var dash_dir: Vector2 = Vector2.ZERO # 向量變數：記錄衝刺方向
var flash_tween: Tween           # 動畫控制器：處理身體紅光閃爍效果

func enter():                    # 切換到攻擊狀態時執行
	character.can_attack = false # 拔除攻擊權力，避免重複攻擊
	character.has_hit_player = false # 重置「咬過玩家」標記
	
	is_charging = true           # 重置為：正在蓄力
	charge_timer = 0.6           # 重置蓄力倒數計時器
	dash_timer = 1.5             # 重置衝刺極限計時器

	# 終極保險：一進入攻擊狀態，確保嘴巴是閉著的！
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true)

	character.velocity = Vector2.ZERO # 強迫野豬定在原地煞車
	if character.player_node:    # 檢查是否鎖定到玩家目標
		dash_dir = (character.player_node.global_position - character.global_position).normalized() # 瞄準玩家的軌跡
	else:                        # 如果沒鎖定到玩家
		dash_dir = character.last_facing_vec # 使用原本最後面朝的方向
	
	character.last_facing_vec = dash_dir # 更新面朝方向
	character.play_animation("idle", dash_dir) # 播放待機動畫假裝蓄力

	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 砍掉殘留閃爍特效
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立新 Tween
	flash_tween.set_loops()      # 無限迴圈播放
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.RED, 0.15) # 變紅
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.15) # 變白

func state_physics_update(_delta: float): # 物理幀更新
	if is_charging: # 如果目前還在蓄力階段
		charge_timer -= _delta # 扣除經過時間
		if charge_timer <= 0: # 倒數完畢
			_start_dash() # 啟動衝刺
	else:
		# --- 階段二：無情狂飆 ---
		dash_timer -= _delta # 扣除經過的時間
		character.velocity = dash_dir * (character.sprint_speed * 3.0) # 3倍速度衝向玩家
		character.play_animation("run", dash_dir) # 播放奔跑動畫

		# 結局 A (優先判定)：撞到玩家！
		if character.has_hit_player: # 如果咬中玩家
			_end_dash("hit_player") # 傳遞 "hit_player" 結局
			return # 跳出更新函數

		# 結局 B (次要判定)：撞牆暈眩
		if dash_timer < 1.4 and character.is_on_wall(): # 條件：衝刺超過 0.1 秒，且碰到實體牆壁
			# 🌟 核心防呆：檢查是否為「正面撞擊」而不是「擦邊滑過」
			# get_wall_normal() 會取得牆壁面向的方向。如果衝刺方向跟牆壁方向相反 (小於 -0.5)，代表迎頭撞上！
			if dash_dir.dot(character.get_wall_normal()) < -0.5:
				print("【系統】野豬正面撞牆啦！直接暈眩！") # 後台印出提示
				_end_dash("stun") # 傳遞 "stun" 結局
				return # 跳出函數

		# 結局 C：揮棒落空
		if dash_timer <= 0: # 衝刺時間耗盡
			_end_dash("miss") # 傳遞 "miss" 結局
			return # 跳出函數

func _start_dash():              # 處理開始衝刺的準備工作
	is_charging = false          # 關閉蓄力開關
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 停止閃爍特效
	character.animated_sprite_2d.self_modulate = Color.WHITE # 恢復純白
	
	# 正式衝鋒的瞬間，把嘴巴(碰撞形狀)打開！
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", false) 

func _end_dash(outcome: String): # 處理衝刺結束的分配工作
	# 衝刺結束，立刻把嘴巴關閉！避免幽靈傷害
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true) 

	if outcome == "stun":        # 如果是 "stun" (正面撞牆)
		state_machine.change_state("EnemyStun") # 切換到暈眩狀態
		
	elif outcome == "hit_player":# 如果是 "hit_player" (咬中玩家)
		var pant_state = state_machine.states.get("enemypant") # 找出喘氣節點
		if pant_state: pant_state.pant_timer = 2.5 # 總時間給 2.5 秒
		state_machine.change_state("EnemyPant") # 切換到喘氣狀態
		
	elif outcome == "miss":      # 如果是 "miss" (落空)
		var pant_state = state_machine.states.get("enemypant") # 找出喘氣節點
		if pant_state: pant_state.pant_timer = 3.0 # 落空比較累，給 3.0 秒
		state_machine.change_state("EnemyPant") # 切換到喘氣狀態

func exit():                     # 退出攻擊狀態時的終極保險
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 砍掉未完成閃爍
	character.animated_sprite_2d.self_modulate = Color.WHITE # 恢復白色
	
	# 終極保險：離開攻擊狀態時，確保嘴巴絕對是關閉的！
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true)

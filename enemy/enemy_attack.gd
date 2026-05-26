extends State # 繼承自狀態模板 enemy_attack

var is_charging: bool = true # 狀態開關：記錄是否正在「蓄力發呆」，預設為真
var charge_timer: float = 0.6 # 宣告蓄力倒數計時器，維持 0.6 秒
var dash_timer: float = 1.5 # 宣告衝刺極限計時器，狂飆最多維持 1.5 秒
var dash_dir: Vector2 = Vector2.ZERO # 向量變數：記錄這一次衝刺的固定方向
var flash_tween: Tween # 動畫控制器：處理蓄力時的紅光閃爍特效

func enter(): # 當狀態機切換進入攻擊狀態時執行
	character.can_attack = false # 拔除攻擊權力，進入冷卻狀態
	character.has_hit_player = false # 重置「是否咬過玩家」的判定標籤
	is_charging = true # 進入蓄力階段
	charge_timer = 0.6 # 設定蓄力秒數
	dash_timer = 1.5 # 設定衝刺上限秒數

	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D") # 抓取嘴巴的碰撞形狀節點
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true) # 蓄力期間先關閉嘴巴，避免誤傷

	character.velocity = Vector2.ZERO # 蓄力時強制野豬定在原地
	if character.player_node: # 條件：如果目前有鎖定到玩家目標
		dash_dir = (character.player_node.global_position - character.global_position).normalized() # 瞄準玩家現在的座標算出衝刺向量
	else: # 如果沒目標
		dash_dir = character.last_facing_vec # 沿用最後面朝的方向
	
	character.last_facing_vec = dash_dir # 更新野豬大腦中的面朝方向
	character.play_animation("idle", dash_dir) # 播放待機動畫來假裝蓄力

	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 如果上次動畫還在跑，先強制砍掉
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立新的動畫控制器
	flash_tween.set_loops() # 設定動畫無限循環播放
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.RED, 0.15) # 0.15 秒變紅色
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.15) # 0.15 秒變回原色

func state_physics_update(_delta: float): # 物理幀更新邏輯 (每秒執行 60 次)
	if is_charging: # 階段一：原地蓄力中
		charge_timer -= _delta # 扣除蓄力時間
		if charge_timer <= 0: # 如果時間倒數完畢
			_start_dash() # 啟動野豬衝鋒
	else: # 階段二：無情狂飆中
		dash_timer -= _delta # 扣除衝刺剩餘秒數
		character.velocity = dash_dir * (character.sprint_speed * 3.0) # 給予 3 倍速的物理推進力
		character.play_animation("run", dash_dir) # 播放奔跑動畫

		if character.has_hit_player: # 結局 A：成功咬到玩家
			_end_dash("hit_player") # 觸發「撞到玩家」的後續處理
			return

		# 🌟 核心修正：撞牆判定。只要衝刺一小段時間後碰到任何實體牆壁
		if dash_timer < 1.4 and character.is_on_wall(): 
			# 🌟 拔除嚴格的角度檢測：只要撞到牆就當作 Bonk！
			# 額外加入「物理反彈」：往後退 10 像素避免卡進牆縫
			var wall_normal = character.get_wall_normal() # 取得牆壁的面向
			character.move_and_collide(wall_normal * 30.0) # 利用牆壁法線把野豬瞬間「彈」開一小段距離
			
			print("【系統】野豬撞牆硬著陸！強制停下！") # 後台提示
			_end_dash("stun") # 觸發「暈眩」結局
			return

		if dash_timer <= 0: # 結局 C：衝刺到底沒撞到東西
			_end_dash("miss") # 觸發「落空」結局
			return

func _start_dash(): # 處理從蓄力切換到衝刺的瞬間
	is_charging = false # 關閉蓄力狀態開關
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 衝刺開始，關閉閃爍特效
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制恢復原始色彩
	
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D") # 抓取嘴巴
	if hitbox_shape: hitbox_shape.set_deferred("disabled", false) # 衝鋒瞬間把傷害判定打開

func _end_dash(outcome: String): # 衝刺結算中心
	character.velocity = Vector2.ZERO # 🌟 結束瞬間強制沒收所有速度，解決溜冰問題
	
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D") # 抓取嘴巴
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true) # 關機，防止幽靈傷害

	if outcome == "stun": # 結局是撞牆暈眩
		state_machine.change_state("EnemyStun") # 進入紫色閃爍暈眩狀態
		
	elif outcome == "hit_player": # 結局是撞到玩家
		var pant_state = state_machine.states.get("enemypant") # 抓取喘氣腳本
		if pant_state: pant_state.pant_timer = 2.5 # 給予 2.5 秒喘氣時間
		state_machine.change_state("EnemyPant") # 進入喘氣狀態
		
	elif outcome == "miss": # 結局是揮棒落空
		var pant_state = state_machine.states.get("enemypant") # 抓取喘氣腳本
		if pant_state: pant_state.pant_timer = 3.0 # 給予 3 秒喘氣時間
		state_machine.change_state("EnemyPant") # 進入喘氣狀態

func exit(): # 徹底退出攻擊狀態時的終極清理
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 確保紅光閃爍已關閉
	character.animated_sprite_2d.self_modulate = Color.WHITE # 確保顏色恢復正常
	var hitbox_shape = character.get_node_or_null("Hitbox/CollisionShape2D") # 抓取嘴巴
	if hitbox_shape: hitbox_shape.set_deferred("disabled", true) # 確保離開此狀態時嘴巴是閉上的

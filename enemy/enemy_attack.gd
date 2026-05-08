extends State                    # 繼承自狀態模板

var is_charging: bool = true     # 開關：記錄目前是否正在蓄力階段
var charge_timer: float = 0.6    # 計時器：蓄力需要 0.6 秒
var dash_timer: float = 1.5      # 計時器：衝刺狂飆最多維持 1.5 秒
var dash_dir: Vector2 = Vector2.ZERO # 記錄衝刺的方向
var flash_tween: Tween           # 宣告一個 Tween 用來處理身體閃爍效果

func enter():                    # 切換到攻擊狀態時執行
	character.can_attack = false # 拔除攻擊權力，進入攻擊冷卻
	character.has_hit_player = false # 重置「咬過玩家」的標記為 false
	
	is_charging = true           # 重置狀態為：正在蓄力
	charge_timer = 0.6           # 重置蓄力時間
	dash_timer = 1.5             # 重置衝刺極限時間

	character.velocity = Vector2.ZERO # 蓄力時強迫野豬定在原地煞車
	if character.player_node:    # 如果有鎖定玩家目標
		dash_dir = (character.player_node.global_position - character.global_position).normalized() # 算出瞄準玩家的方向向量
	else:                        # 如果沒鎖定玩家
		dash_dir = character.last_facing_vec # 就用原本最後面朝的方向
	
	character.last_facing_vec = dash_dir # 更新野豬面朝方向
	character.play_animation("idle", dash_dir) # 播放待機動畫假裝蓄力

	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 如果之前有未完成的閃爍就砍掉
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立一個綁在野豬身上的新 Tween 動畫
	flash_tween.set_loops()      # 設定為無限迴圈播放
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.RED, 0.15) # 用 0.15 秒把身體變紅
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.15) # 再用 0.15 秒變回白色

func state_physics_update(_delta: float):
	if is_charging:
		# --- 階段一：蓄力 ---
		charge_timer -= _delta
		if charge_timer <= 0:
			_start_dash() 
	else:
		# --- 階段二：狂飆 ---
		dash_timer -= _delta
		character.velocity = dash_dir * (character.sprint_speed * 3.0) 
		character.play_animation("run", dash_dir)

		# 🌟 結局 A (優先判定)：撞到玩家！
		# 把這個移到最上面。這樣就算玩家是一道肉牆，也會優先被當成「咬中目標」
		if character.has_hit_player:
			_end_dash("hit_player")
			return

		# 🌟 結局 B (次要判定)：撞牆暈眩
		# 如果沒咬到玩家，而且引擎判定撞到牆了，才算真的撞牆
		if dash_timer < 1.4 and character.is_on_wall():
			print("【系統】野豬衝刺撞牆啦！直接暈眩！")
			_end_dash("stun")
			return

		# 🌟 結局 C：揮棒落空
		if dash_timer <= 0:
			_end_dash("miss")
			return

func _start_dash():              # 開始衝刺的輔助函數
	is_charging = false          # 關閉蓄力狀態
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 停止紅色閃爍
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制將身體顏色恢復白色
	
	var hitbox = character.get_node_or_null("Hitbox") # 尋找嘴巴(Hitbox)節點
	if hitbox: hitbox.set_deferred("monitoring", true) # 安全地強制開啟嘴巴雷達 (避免編輯器Bug)

func _end_dash(outcome: String): # 結束衝刺的輔助函數，接收結局字串
	var hitbox = character.get_node_or_null("Hitbox") # 尋找嘴巴(Hitbox)節點
	if hitbox: hitbox.set_deferred("monitoring", false) # 安全地強制關閉嘴巴雷達，避免後續亂咬人

	character.get_tree().create_timer(3.0).connect("timeout", func(): character.can_attack = true) # 啟動隱形的 3 秒計時器，時間到恢復攻擊權力

	if outcome == "stun":        # 如果結局是撞牆
		state_machine.change_state("EnemyStun") # 切換到暈眩狀態
	elif outcome == "hit_player":# 如果結局是咬中玩家
		var pant_state = state_machine.states.get("enemypant") # 去大腦找出「喘氣」狀態
		if pant_state: pant_state.pant_timer = 1.5 # 把喘氣時間設定為 2 秒
		state_machine.change_state("EnemyPant") # 切換到喘氣狀態休息
	elif outcome == "miss":      # 如果結局是落空
		var pant_state = state_machine.states.get("enemypant") # 去大腦找出「喘氣」狀態
		if pant_state: pant_state.pant_timer = 2 # 沒咬中比較累，喘氣時間設為 2 秒
		state_machine.change_state("EnemyPant") # 切換到喘氣狀態休息

func exit():                     # 離開攻擊狀態時的保險機制
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 如果還有閃爍特效沒關，強行砍掉
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制恢復白色
	var hitbox = character.get_node_or_null("Hitbox") # 找尋嘴巴
	if hitbox: hitbox.set_deferred("monitoring", false) # 強制關閉嘴巴雷達當作終極保險

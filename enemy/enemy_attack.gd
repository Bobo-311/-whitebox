extends State                    # 繼承自狀態模板，讓這個腳本可以被大腦(StateMachine)呼叫

var is_charging: bool = true     # 宣告狀態開關：記錄目前是否正在「蓄力準備」階段，預設為 true
var charge_timer: float = 0.6    # 宣告浮點數計時器：蓄力動作需要維持 0.6 秒
var dash_timer: float = 1.5      # 宣告浮點數計時器：衝刺狂飆最多只能維持 1.5 秒 (防呆，避免無限衝刺)
var dash_dir: Vector2 = Vector2.ZERO # 宣告向量變數：用來記錄衝刺的方向，預設為零向量
var flash_tween: Tween           # 宣告一個 Tween 動畫控制器，用來處理身體紅光閃爍效果

func enter():                    # 內建虛擬函數：當大腦剛剛切換到這個「攻擊狀態」時，會立刻執行一次
	character.can_attack = false # 拔除野豬的攻擊權力，確保牠不會在攻擊中途又觸發下一次攻擊
	character.has_hit_player = false # 重置「咬過玩家」的標記為 false，準備這回合的全新判定
	
	is_charging = true           # 將狀態重置為：正在蓄力
	charge_timer = 0.6           # 將蓄力倒數計時器重置為 0.6 秒
	dash_timer = 1.5             # 將衝刺極限計時器重置為 1.5 秒

	character.velocity = Vector2.ZERO # 蓄力時強迫野豬的移動物理量歸零，讓牠定在原地煞車
	if character.player_node:    # 條件判斷：檢查野豬的視野(雷達)是否有鎖定到玩家目標
		dash_dir = (character.player_node.global_position - character.global_position).normalized() # 【特殊函數】normalized() 負責把方向向量縮放到長度為 1，只保留純粹的「方向」，算出瞄準玩家的軌跡
	else:                        # 條件判斷：如果沒鎖定到玩家 (可能玩家跑出視野了)
		dash_dir = character.last_facing_vec # 就退而求其次，使用野豬原本最後面朝的方向
	
	character.last_facing_vec = dash_dir # 更新野豬目前的面朝方向，確保圖片不會轉錯邊
	character.play_animation("idle", dash_dir) # 呼叫野豬本體播放待機動畫，假裝正在蓄力準備

	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 如果上次攻擊殘留了未完成的閃爍特效，強制砍掉避免報錯
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立一個綁定在野豬身上的新 Tween 動畫
	flash_tween.set_loops()      # 指示 Tween 動畫設定為無限迴圈播放
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.RED, 0.15) # 花費 0.15 秒把野豬身體顏色漸變成紅色
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.15) # 再花 0.15 秒漸變回白色，製造警示閃爍感

func state_physics_update(_delta: float): # 內建虛擬函數：物理引擎的每一幀(1/60秒)都會執行
	if is_charging: # 條件判斷：如果目前還在蓄力階段
		# --- 階段一：蓄力等待 ---
		charge_timer -= _delta # 讓蓄力計時器扣除這一幀經過的時間
		if charge_timer <= 0: # 如果蓄力時間倒數完畢
			_start_dash() # 呼叫自訂函數，正式啟動衝刺
	else:
		# --- 階段二：無情狂飆 ---
		dash_timer -= _delta # 讓衝刺極限計時器扣除經過的時間
		character.velocity = dash_dir * (character.sprint_speed * 3.0) # 給予野豬物理量：衝刺方向 乘以 3倍的衝刺速度
		character.play_animation("run", dash_dir) # 播放奔跑的動畫

		# 結局 A (優先判定)：撞到玩家！
		if character.has_hit_player: # 如果野豬嘴巴的 Hitbox 有感應到玩家的受傷區
			_end_dash("hit_player") # 呼叫結束衝刺函數，並傳遞字串 "hit_player" 代表這個結局
			return # 🌟 直接跳出物理更新函數，不再執行下面的程式碼

		# 結局 B (次要判定)：撞牆暈眩
		if dash_timer < 1.4 and character.is_on_wall(): # 條件：衝刺必須超過 0.1 秒，且內建函數 is_on_wall() 判定撞到實體牆壁
			print("【系統】野豬衝刺撞牆啦！直接暈眩！") # 後台印出提示
			_end_dash("stun") # 呼叫結束衝刺函數，傳遞 "stun" 代表撞牆結局
			return # 🌟 直接跳出函數

		# 結局 C：揮棒落空
		if dash_timer <= 0: # 如果衝刺時間(1.5秒)耗盡了，卻都沒有撞到牆也沒撞到人
			_end_dash("miss") # 呼叫結束衝刺函數，傳遞 "miss" 代表落空結局
			return # 🌟 直接跳出函數

func _start_dash():              # 自訂函數：處理開始衝刺時的準備工作
	is_charging = false          # 關閉蓄力狀態開關，宣告進入衝刺階段
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 停止身上的紅色警示閃爍特效
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制將身體顏色恢復回純白色
	
	var hitbox = character.get_node_or_null("Hitbox") # 尋找野豬嘴巴(Hitbox)攻擊感應節點
	if hitbox: hitbox.set_deferred("monitoring", true) # 【特殊函數】set_deferred 會在物理幀結束時才安全地開啟嘴巴雷達，避免報錯

func _end_dash(outcome: String): # 自訂函數：處理衝刺結束的分配工作，接收一個「結局字串」
	var hitbox = character.get_node_or_null("Hitbox") # 尋找嘴巴(Hitbox)節點
	if hitbox: hitbox.set_deferred("monitoring", false) # 安全地強制關閉嘴巴雷達，避免野豬停下來還咬到人

	# 🌟 隱形計時器已被拔除！攻擊權力將改由 Pant 狀態的 exit() 來歸還！

	if outcome == "stun":        # 條件判斷：如果傳入的結局是 "stun" (撞牆)
		state_machine.change_state("EnemyStun") # 直接命令大腦切換到暈眩狀態 (EnemyStun)
		
	elif outcome == "hit_player":# 條件判斷：如果結局是 "hit_player" (咬中玩家)
		var pant_state = state_machine.states.get("enemypant") # 去狀態機大腦裡找出名為「enemypant」的狀態節點
		if pant_state: pant_state.pant_timer = 2.5 # 修改喘氣腳本裡的計時器，總時間給 2.5 秒
		state_machine.change_state("EnemyPant") # 命令大腦切換到喘氣狀態
		
	elif outcome == "miss":      # 條件判斷：如果結局是 "miss" (落空)
		var pant_state = state_machine.states.get("enemypant") # 找出喘氣狀態節點
		if pant_state: pant_state.pant_timer = 3.0 # 落空比較累，總時間給 3.0 秒
		state_machine.change_state("EnemyPant") # 命令大腦切換到喘氣狀態

func exit():                     # 內建虛擬函數：當大腦準備離開攻擊狀態前，執行的終極保險機制
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 如果切換狀態時還有閃爍特效沒關，強行砍掉
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制恢復成白色，避免卡在紅光
	var hitbox = character.get_node_or_null("Hitbox") # 找尋嘴巴節點
	if hitbox: hitbox.set_deferred("monitoring", false) # 強制關閉嘴巴雷達當作終極保險

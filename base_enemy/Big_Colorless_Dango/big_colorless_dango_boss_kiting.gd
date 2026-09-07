extends State

# ==========================================
# ⚙️ 企劃面板設定 (依照終極版 GDD 數值)
# ==========================================
@export_category("🧠 Boss 決策大腦 (終極版)")

@export_group("移動速度")
@export var chase_speed: float = 60.0      # 壓迫速度 (緩慢逼近)
@export var retreat_speed: float = 80.0    # 危險區倒退嚕速度

@export_group("距離閾值 (甜區設定)")
@export var cheese_distance: float = 600.0       # > 600 進入極遠逃課區
@export var retreat_distance: float = 300.0      # < 300 進入危險逼近區 (GDD設定)
@export var close_counter_distance: float = 100.0 # < 100 極近距離觸發 V 字防守

@export_group("技能冷卻時間 (CD)")
@export var poison_cd_time: float = 5.0       # 技能一 (麻油菸彈遠程)
@export var poison_close_cd_time: float = 8.0 # 技能一 (近身反制V字)
@export var minion_cd_time: float = 6.0       # 技能二 (團子主動牽制)

# ==========================================
# ⚙️ 特殊技能冷卻設定
# ==========================================
@export_group("王a燈 (牆角大跳) 設定")
@export var jump_strike_cd_time: float = 12.0  # 技能冷卻時間 (不能讓牠一直跳)
@export var jump_strike_trigger_dist: float = 60.0 # 🌟 新增：多近才算被「壁咚」？
var jump_strike_cd: float = 0.0                # 當前冷卻倒數計時器

@export_group("開發偵錯")
@export var show_debug_print: bool = true 

# ⏳ 內部 CD 計時器
var poison_cd: float = 2.0       
var poison_close_cd: float = 0.0
var minion_cd: float = 0.0       #  新增吐團子 CD

func enter():
	if show_debug_print:
		print("🟢 【大腦】進入決策模式！")

func state_physics_update(delta: float):
	# 1. ⏳ 運轉技能冷卻時間
	if poison_cd > 0: poison_cd -= delta
	if poison_close_cd > 0: poison_close_cd -= delta
	if minion_cd > 0: minion_cd -= delta
	if jump_strike_cd > 0: jump_strike_cd -= delta # 🌟 更新大跳 CD

	# 2. 🛡️ 防呆：抓取玩家實體
	if not character.player_node and DataManager and DataManager.player_node:
		character.player_node = DataManager.player_node
		character.can_see_player = true
	
	# 🌟【新增這一段：鞭屍防護機制】
	# 如果玩家不存在，或者玩家已經死了 (假設玩家有 is_dead 變數)
	if not character.player_node or ("is_dead" in character.player_node and character.player_node.is_dead):
		# 玩家死了，Boss 失去目標，立刻煞車發呆，停止大腦運作！
		character.velocity = Vector2.ZERO
		character.play_animation("idle", character.last_facing_vec)
		return # <--- 關鍵！直接 return，下面所有的攻擊判斷都不會跑！

	# 3. 📏 計算真實距離與方向向量
	var target_pos = character.player_node.global_position
	var dist = character.global_position.distance_to(target_pos)
	var dir = character.global_position.direction_to(target_pos)

	if show_debug_print:
		print("📏 距離:", round(dist), " | 撞牆:", character.is_on_wall())

	# ==========================================
	# ⚡ 優先級決策樹 (依照距離精準分工)
	# ==========================================
	# 🚨【優先級 0：無路可退的絕境 (牆角大跳突圍)】🚨
	# 條件：Boss 身體撞到牆 (is_on_wall) + 玩家極度貼臉 (< 60) + 技能 CD 好了
	# 注意：這裡把距離設為 60，比 V 字防守的 100 更短，代表這是「真．貼臉」的最終反制。
	if character.is_on_wall() and dist < jump_strike_trigger_dist and jump_strike_cd <= 0:
		jump_strike_cd = jump_strike_cd_time # 重置 CD
		state_machine.change_state("JumpStrike") # 🌟 切換到大跳狀態！
		return # 👈 關鍵！直接 return，中斷下面所有邏輯
	# 【優先級 1：極度危機】玩家貼臉 (< 100) -> 腳下吐毒 V字牆！

	if dist < close_counter_distance:
		if poison_close_cd <= 0:
			poison_close_cd = poison_close_cd_time        
			state_machine.change_state("SpitPoisonClose") 
			return 

	# 【優先級 2：危險逼近區】玩家逼近 (< 300) -> 倒退嚕 & 沿牆側滑
	if dist < retreat_distance:
		var retreat_dir = dir * -1
		character.last_facing_vec = dir # 視線永遠死盯玩家
		
		# 🌟【沿牆側滑核心數學】🌟
		if character.is_on_wall():
			# 取得牆壁的「法線」
			var wall_normal = character.get_wall_normal()
			var slide_dir = retreat_dir.slide(wall_normal).normalized()
			
			# 【遊戲思考：防抖動設計 (Anti-Jitter)】
			# 即使卡在死角，我們「依然給予速度」去推牆壁！
			# 為什麼？因為如果我們把速度變成 0，大胖呆就會離開牆壁，is_on_wall() 會變成 false，
			# 導致下一幀又開始倒退嚕，然後又撞牆，發生瘋狂抽搐。
			character.velocity = slide_dir * retreat_speed
			
			# 🌟【神級死角偵測：真實速度驗證】
			# 我們給了推牆的速度，但如果上一幀「真正的移動速度」極小，代表被 90 度死角卡死了！
			# 我們不去改速度（讓牠繼續穩穩地貼著牆），我們只「竄改動畫」！
			if character.get_real_velocity().length() < 10.0:
				character.play_animation("idle", dir) # 退無可退，困獸對峙！
			else:
				character.play_animation("move", dir) # 成功側滑
		else:
			# 背後沒牆，正常倒退嚕
			character.velocity = retreat_dir * retreat_speed
			character.play_animation("move", dir)
			
		return 

	# 【優先級 3：極遠逃課區】玩家太遠 (> 600) -> 吐追擊小怪！
	if dist > cheese_distance:
		character.last_facing_vec = dir
		if minion_cd <= 0:
			minion_cd = minion_cd_time
			# 🌟 切換到吐團子專用狀態 (下一站我們再來做這個節點)
			state_machine.change_state("SpitMinion") 
			return
		else:
			# CD 中，身體緩慢往前壓迫，逼玩家回來
			character.velocity = dir * chase_speed
			character.play_animation("move", dir)
			return

	# 【優先級 4：主力交戰區】距離 300 ~ 600 之間 -> 變身砲台狂吐毒！
	character.velocity = Vector2.ZERO 
	character.last_facing_vec = dir
	
	if poison_cd <= 0:
		poison_cd = poison_cd_time               
		state_machine.change_state("SpitPoison") 
		return
		
	# 所有技能 CD 中，原地發呆死盯玩家，等待最佳時機
	character.play_animation("idle", dir)

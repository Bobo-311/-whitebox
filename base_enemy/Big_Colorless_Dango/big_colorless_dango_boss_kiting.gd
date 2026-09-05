extends State

# ==========================================
# ⚙️ 企劃面板設定 (三段式風箏 + 砲台)
# ==========================================
@export_category("🧠 Boss 決策大腦 (終極版)")

@export_group("移動速度")
@export var chase_speed: float = 60.0      # 🌟 往前追的速度 (緩慢壓迫，數值通常比後退慢)
@export var retreat_speed: float = 80.0    # 往後退的速度 (緊急避險)

@export_group("距離閾值 (甜區設定)")
@export var chase_distance: float = 600.0        # 🌟 大於多少開始追？(防逃課極限距離)
@export var retreat_distance: float = 200.0      # 小於多少開始退？(防禦圈)
@export var close_counter_distance: float = 50.0 # 極近距離反制觸發點

@export_group("技能冷卻時間 (CD)")
@export var poison_cd_time: float = 5.0       # 技能一：常規遠程吐毒 (5秒)
@export var poison_close_cd_time: float = 8.0 # 技能一：極近防身反制 (8秒)

@export_group("開發偵錯")
@export var show_debug_print: bool = true 

# ⏳ 內部 CD 計時器 (給常規毒 2 秒初始緩衝)
var poison_cd: float = 2.0       
var poison_close_cd: float = 0.0

func enter():
	if show_debug_print:
		print("🟢 【大腦】進入決策模式！冷卻時間持續運轉...")

func state_physics_update(delta: float):
	# 1. ⏳ 運轉技能冷卻時間
	if poison_cd > 0: poison_cd -= delta
	if poison_close_cd > 0: poison_close_cd -= delta

	# 2. 🛡️ 防呆：抓取玩家實體
	if not character.player_node and DataManager and DataManager.player_node:
		character.player_node = DataManager.player_node
		character.can_see_player = true

	if not character.player_node:
		character.velocity = Vector2.ZERO
		return

	# 3. 📏 計算真實距離與方向向量
	var target_pos = character.player_node.global_position
	var dist = character.global_position.distance_to(target_pos)
	var dir = character.global_position.direction_to(target_pos)

	if show_debug_print:
		print("📏 距離: ", round(dist), " | 遠程毒CD: ", snapped(poison_cd, 0.1), " | 速度: ", character.velocity)

	# ==========================================
	# ⚡ 優先級決策樹 (Priority-Driven AI)
	# ==========================================
	
	# 【優先級 1：極度危機】玩家貼臉 (< 50) -> 吐腳下！
	if dist < close_counter_distance:
		if poison_close_cd <= 0:
			poison_close_cd = poison_close_cd_time        
			state_machine.change_state("SpitPoisonClose") 
			return 

	# 【優先級 2：中度危機】玩家逼近 (< 200) -> 倒退嚕！
	if dist < retreat_distance:
		character.velocity = (dir * -1) * retreat_speed 
		character.last_facing_vec = dir 
		character.play_animation("move", dir)
		return 

	# 【優先級 3：防逃課追擊】玩家太遠 (> 600) -> 往前逼近！
	# (把企劃原本的 chase 邏輯完美加回！)
	if dist > chase_distance:
		character.velocity = dir * chase_speed
		character.last_facing_vec = dir
		character.play_animation("move", dir)
		return

	# 【優先級 4：絕對甜區】距離介於 200 ~ 600 之間 -> 煞車開火！
	character.velocity = Vector2.ZERO 
	character.last_facing_vec = dir
	
	if poison_cd <= 0:
		poison_cd = poison_cd_time               
		state_machine.change_state("SpitPoison") 
		return
		
	# 技能 CD 中，原地發呆死盯玩家
	character.play_animation("idle", dir)

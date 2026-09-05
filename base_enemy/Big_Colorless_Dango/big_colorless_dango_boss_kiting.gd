extends State

# ==========================================
# ⚙️ 參數設定 (全部開放到 Inspector 給企劃調整)
# ==========================================
@export_category("🏹 Boss 智能走位 (三段式風箏)")

@export_group("移動速度")
@export var chase_speed: float = 120.0     # 往前追的速度
@export var retreat_speed: float = 80.0    # 往後退的速度

@export_group("距離閾值 (甜區設定)")
@export var chase_distance: float = 1000.0  # 🌟 大於多少開始追？(針對大體型 Boss，設 500 較合理)
@export var retreat_distance: float = 500.0# 🌟 小於多少開始退？(甜區下限)
# (備註：介於 250 ~ 500 之間，就是 Boss 的「絕對甜區」，牠會停下來發呆準備放招)

@export_group("開發偵錯")
@export var show_debug_print: bool = true  # 🌟 打開它，後台會瘋狂印出真實距離，幫你抓手感！

func enter():
	print("🟢 【大腦報告】進入 Boss 專屬移動狀態！(甜區走位啟動)")

func state_physics_update(_delta: float):
	# 1. 🛡️ 最強防呆：抓取玩家實體
	if not character.player_node and DataManager and DataManager.player_node:
		character.player_node = DataManager.player_node
		character.can_see_player = true

	# 找不到玩家就乖乖煞車停好
	if not character.player_node:
		character.velocity = Vector2.ZERO
		return

	# 2. 📏 計算真實數學距離與方向向量
	var target_pos = character.player_node.global_position
	var dist = character.global_position.distance_to(target_pos)
	var dir = character.global_position.direction_to(target_pos)

	# 🛠️ 偵錯器：告訴你現在到底多遠，方便你調整上面的 Inspector 參數
	if show_debug_print:
		print("📏 [真實距離偵測]: ", round(dist), " | 速度: ", character.velocity)

	# 3. 🧠 核心 AI：三段式甜區判斷
	if dist > chase_distance:
		# 【狀況 A：玩家太遠】-> 主動往前追擊
		character.velocity = dir * chase_speed
		character.last_facing_vec = dir
		character.play_animation("move", dir)
		
	elif dist < retreat_distance:
		# 【狀況 B：玩家太近 (貼臉)】-> 往反方向倒退嚕 (Kiting)
		character.velocity = (dir * -1) * retreat_speed
		character.last_facing_vec = dir
		character.play_animation("move", dir)
		
	else:
		# 【狀況 C：處於甜區 (距離剛好)】-> 原地煞車死盯玩家
		# (TODO: 未來要加吐毒沼的技能，就是寫在這個區塊！)
		character.velocity = Vector2.ZERO
		character.play_animation("idle", dir)

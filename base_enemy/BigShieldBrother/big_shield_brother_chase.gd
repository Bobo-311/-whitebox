extends State # 繼承狀態模板

@export_category("🏃 追擊狀態設定")

# 【攻擊發動距離】
# 當他跟玩家的距離小於這個數值時，就會觸發鐵門頂撞！
@export var attack_range: float = 250.0       
# 【追擊動畫】
# 追著玩家跑時要播放什麼動畫 (預設為 move)
@export var chase_anim: String = "run"      

func enter():
	pass # 進入這個狀態時不用特別做什麼，交給物理更新處理

func state_physics_update(_delta: float):
	# 1. 防呆機制：如果玩家死了、消失了，或者被牆壁擋住了
	if not character.player_node or not character.can_see_player:
		character.velocity = Vector2.ZERO # 煞車
		character.play_animation("idle") # 播發呆動畫
		state_machine.change_state("Idle") # 大腦切換回 Idle 狀態
		return

	# 2. 測量距離：拿出捲尺，量一下自己跟玩家離多遠
	var distance_to_player = character.global_position.distance_to(character.player_node.global_position)
	
	# 如果距離小於我們設定的 75.0 (夠近了！)
	if distance_to_player <= attack_range:
		state_machine.change_state("ShieldPush") # 大腦瞬間切換到「衝撞狀態」
		return

	# 3. 繼續追蹤：如果距離還沒到，就算出往玩家方向的向量
	var move_dir = (character.player_node.global_position - character.global_position).normalized()
	
	# 給予肉身物理速度 (方向 * 走路速度)
	character.velocity = move_dir * character.walk_speed
	
	# 記錄面向，並播放對應 4 方位的動畫
	# (因為鐵門永遠朝下，所以往上追玩家時，看起來就像倒退嚕)
	character.last_facing_vec = move_dir
	character.play_animation(chase_anim, move_dir)

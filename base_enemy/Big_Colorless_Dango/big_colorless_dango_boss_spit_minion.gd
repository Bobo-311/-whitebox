extends State

# ==========================================
# ⚙️ 技能二：主動牽制 (防逃課吐怪)
# ==========================================
@export_category("🟣 技能二：防逃課牽制")
@export var minion_scene: PackedScene      # 裝填：小團子場景 (colorless_dango.tscn)
@export var spit_duration: float = 1.5     # 狀態硬直：大胖呆吐完怪後，要在原地喘息多久才能動？
@export var min_spawn: int = 1             # 最少吐幾隻小怪
@export var max_spawn: int = 3             # 最多吐幾隻小怪

# 🌟【新增：精準落點控制旋鈕】(取代原本不受控的初速推力)
@export_group("拋物線落點設定")
@export var throw_distance: float = 400.0  # 吐多遠？(決定小怪落地後，這道肉牆與 Boss 的距離)
@export var flight_time: float = 0.6       # 滯空時間：小怪飛在空中的總秒數 (控制節奏，太快像子彈，太慢沒壓迫感)
@export var jump_height: float = 120.0     # 拋物線高度：純視覺效果，小怪會飛多高再掉下來

var timer: float = 0.0 # 內部倒數計時器

# ==========================================
# 🎬 狀態進場：前搖與鎖定
# ==========================================
func enter():
	timer = spit_duration
	character.velocity = Vector2.ZERO # 煞車停好，避免滑步吐怪
	
	# 👁️ 計算玩家方向，讓 Boss 在吐怪瞬間「死盯著玩家」
	var dir = Vector2.DOWN
	if character.player_node:
		dir = character.global_position.direction_to(character.player_node.global_position)
		character.last_facing_vec = dir
		
	# 播放發呆動畫當作「施法前搖」
	character.play_animation("idle", dir)
	
	# 啟動嘔吐小怪的實例化流程
	_spit_routine()

# ==========================================
# ⏳ 狀態更新：硬直結束切換
# ==========================================
func state_physics_update(delta: float):
	timer -= delta
	if timer <= 0:
		state_machine.change_state("move") # 吐完收工，把身體控制權交還給大腦繼續風箏

# ==========================================
# 🤮 核心演出：精準扇形分佈與拋物線 (Target-Driven Spawning)
# ==========================================
func _spit_routine() -> void:
	# 🛡️ 防呆：檢查有沒有裝填小怪場景
	if not minion_scene: return
	
	# 🎲 骰子：隨機決定這次吐幾隻 (例如骰到 3 隻)
	var count = randi_range(min_spawn, max_spawn)
	
	for i in range(count):
		# 🛡️ 防呆：如果吐到一半 Boss 被打死了，立刻停止吐怪
		if not is_instance_valid(character) or character.is_dead: 
			break
			
		# 1️⃣ 實例化小怪，並加入到世界中
		var minion = minion_scene.instantiate()
		character.get_parent().add_child(minion)
		
		# 📍 起點設定：從大胖呆的上半部 (嘴巴) 出發，不要從腳底板生出來
		minion.global_position = character.global_position + Vector2(0, -40)
		
		if character.player_node:
			# 算出從 Boss 指向玩家的基準線
			var dir_to_player = character.global_position.direction_to(character.player_node.global_position)
			
			# 🌟【正規作法：完美扇形分佈 (Fan Spread)】🌟
			# 遊戲思考：如果吐多隻怪，我們不能隨機亂噴，會重疊。我們要算出一個「扇形」讓牠們整齊排開。
			var angle_offset = 0.0
			if count > 1:
				var spread_arc = 60.0 # 扇形的總展開角度 (60度代表左右各30度)
				# 數學公式：算出第一隻在最左邊，最後一隻在最右邊，中間均分
				# 以 3 隻為例，算出來的角度會是：-30度, 0度, +30度
				angle_offset = -(spread_arc / 2.0) + (i * (spread_arc / (count - 1)))
			
			# 根據算出的角度，把原本指向玩家的箭頭稍微旋轉
			var throw_dir = dir_to_player.rotated(deg_to_rad(angle_offset))
			
			# 🎯【精準落點計算 (Target Position)】
			# 物理引擎不可靠，我們直接算死目標：小怪現在的位置 + (發射方向 * 我們設定的固定距離 400)
			var target_pos = minion.global_position + (throw_dir * throw_distance)
			
			# 🧠【遊戲思考：拔掉 AI 插頭 (Airborne/Stunned State)】
			# 動作遊戲中，被擊飛或拋出的怪物，在半空中是沒有智商的，必須強制關閉牠的決策樹。
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false)
			
			# 強制讓空中的小怪面向飛行的方向，並播放 move 動畫假裝在飛
			if "last_facing_vec" in minion:
				minion.last_facing_vec = throw_dir
				minion.play_animation("move", throw_dir)
			
			# 🚀【雙軌 Tween 動畫 (偽 3D 拋物線)】
			# Tween 1：控制地面 X/Y 軸直線移動 (從 Boss 腳下精準滑向剛剛算好的 target_pos)
			var move_tween = create_tween()
			move_tween.tween_property(minion, "global_position", target_pos, flight_time)
			
			# Tween 2：控制精靈圖(Sprite) 往上飛再往下掉，營造 Z 軸立體感
			var sprite = minion.get_node_or_null("AnimatedSprite2D")
			if sprite:
				var arc_tween = create_tween()
				# 上升段 (Ease Out 減速對抗地心引力)
				arc_tween.tween_property(sprite, "position:y", -jump_height, flight_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				# 下降段 (Ease In 加速掉回地板)
				arc_tween.tween_property(sprite, "position:y", 0.0, flight_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			
			# ⚡【落地喚醒 (On Landing)】
			# 當移動的 Tween 跑完 (代表精準降落到指定座標了)
			move_tween.finished.connect(func():
				# 確保小怪還活著 (沒有在半空中被玩家砍死)
				if is_instance_valid(minion) and "state_machine" in minion:
					# 把大腦插頭插回去，小怪正式開始追殺玩家！
					minion.state_machine.set_physics_process(true) 
			)
			
		# 🎵【吐怪節奏 (Spawn Rhythm)】
		# 每吐完一隻，強制暫停 0.3 秒再吐下一隻。營造機關槍「噗、噗、噗」的連發壓迫感。
		if i < count - 1:
			await get_tree().create_timer(0.3).timeout

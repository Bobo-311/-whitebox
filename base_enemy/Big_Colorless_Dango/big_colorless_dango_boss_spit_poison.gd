extends State

# ==========================================
# ⚙️ 發射台組態 (開放給右側 Inspector 面板調整)
# ==========================================
@export_category("🟢 技能一：麻油菸彈 (發射台)")
@export var bomb_scene: PackedScene      # 裝填子彈：把做好的毒彈場景拖進來
@export var attack_duration: float = 2.0 # 攻擊硬直：大胖呆吐毒時，要原地罰站幾秒？

@export_group("視覺預警 (Telegraphing)")
@export var flash_color: Color = Color(0.2, 0.9, 0.2, 1.0) # 預警顏色：吐毒前閃什麼顏色的光？

@export_group("子彈數量設定")
@export var ranged_bomb_count: int = 3   # 遠程模式：固定吐幾顆？
@export var melee_bomb_count: int = 2    # 近戰模式：固定吐幾顆？

@export_group("近身變體與智能落點")
@export var is_melee_counter: bool = false    # 這是近身反制專用的節點嗎？(打勾代表是)
@export var melee_push_distance: float = 40.0 # 智能落點：毒沼要往玩家的方向「推」多遠？

var timer: float = 0.0

# ==========================================
# 🎬 狀態進場：發動攻擊 & 視覺前搖
# ==========================================
func enter():
	timer = attack_duration
	
	# 🛡️ 煞車鎖死：強迫速度變成 0，大胖呆就不會邊吐邊滑步
	character.velocity = Vector2.ZERO 
	
	# 👁️ 轉向玩家：吐毒的一瞬間，眼睛死盯著玩家
	var dir = Vector2.DOWN
	if character.player_node:
		dir = character.global_position.direction_to(character.player_node.global_position)
		character.last_facing_vec = dir
	
	# 🎭 動畫：因為目前沒有專屬吐毒動畫，先播 idle 發呆，假裝在蓄力
	character.play_animation("idle", dir) 
	
	# 🟢 呼叫下面的函數，讓身體閃綠光
	_play_poison_flash()
	
	# 🚀 呼叫下面的函數，開始噴出子彈
	_fire_bombs()

# ==========================================
# ⏳ 狀態更新：硬直倒數
# ==========================================
func state_physics_update(delta: float):
	timer -= delta
	
	# 罰站時間結束，把身體控制權還給大腦 (切回 move 狀態)
	if timer <= 0:
		state_machine.change_state("move") 

# ==========================================
# 🧹 狀態退場：洗白顏色
# ==========================================
func exit():
	# 如果大胖呆吐到一半被打斷 (例如被打死)，必須強制把身體洗回白色，不然會一輩子卡在綠色
	if character.animated_sprite_2d:
		var mat = character.animated_sprite_2d.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("state_color", Color.WHITE)

# ==========================================
# 🟢 視覺演出：綠光閃爍 
# ==========================================
func _play_poison_flash() -> void:
	if not character.animated_sprite_2d: return
	
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if mat:
		var tween = create_tween()
		tween.tween_property(mat, "shader_parameter/state_color", flash_color, 0.1)
		tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, attack_duration - 0.1)

# ==========================================
# 🚀 發射流程 (核心邏輯)
# ==========================================
func _fire_bombs() -> void:
	if not bomb_scene: return
	
	# 決定要吐幾顆：看面板有沒有打勾？
	# 如果有打勾 (近戰)，就拿近戰的數量；沒打勾 (遠程)，就拿遠程的數量。
	var count = melee_bomb_count if is_melee_counter else ranged_bomb_count
	
	for i in range(count):
		# 如果大胖呆在吐毒的間隔被砍死了，立刻停止，不要死後還吐。
		if not is_instance_valid(character) or character.is_dead: 
			break 
		
		# 1. 生出一顆毒彈，放進遊戲世界
		var bomb = bomb_scene.instantiate()
		character.get_parent().add_child(bomb) 
		
		# 2. 決定這顆毒彈要砸在哪裡 (target_pos)
		var target_pos = character.global_position # 預設起點是 Boss 腳下
		
		if is_melee_counter and character.player_node:
			# 🌟【修改：正規作法 - 法向量 V 字分佈 (Orthogonal Spread)】
			
			# 步驟 A: 取得從 Boss 指向玩家的基準線 (正前方)
			var dir_to_player = character.global_position.direction_to(character.player_node.global_position)
			
			# 步驟 B: 決定左右散開的角度
			# 如果是第 1 顆 (i=0)，角度為 -45 度 (左前)；第 2 顆 (i=1) 為 +45 度 (右前)
			# (用 i % 2 的好處是，就算企劃以後把近戰改成吐 4 顆，牠也會聰明地左右左右輪流吐)
			var angle_deg = -45.0 if i % 2 == 0 else 45.0
			
			# 步驟 C: 將基準線旋轉這個角度 (Godot 物理運算使用弧度 rad，所以要用 deg_to_rad 轉換)
			var final_dir = dir_to_player.rotated(deg_to_rad(angle_deg))
			
			# 步驟 D: 將旋轉後的箭頭，乘上面板設定的推擠距離
			var push_offset = final_dir * melee_push_distance
			
			# 步驟 E: 最終落點 = Boss腳下 + V型推擠 
			# (【遊戲思考】：我們把隨機雜訊刪掉了，因為真正的防守陷阱必須 100% 精準封鎖走位)
			target_pos += push_offset
			
		elif character.player_node:
			# 【遠程模式】：直接抓玩家當下的座標。如果要連吐多顆，就加上大範圍散佈 (spread)，變成地雷陣。
			var spread = Vector2(randf_range(-70, 70), randf_range(-70, 70)) if count > 1 else Vector2.ZERO
			target_pos = character.player_node.global_position + spread
			
		# 3. 把毒彈放在 Boss 身上，然後呼叫毒彈裡面的 launch_to 讓它起飛砸向落點
		bomb.global_position = character.global_position
		if bomb.has_method("launch_to"):
			bomb.launch_to(target_pos)
			
		# 4. 吐完一顆，暫停 0.25 秒再吐下一顆，製造節奏感
		if i < count - 1:
			await get_tree().create_timer(0.25).timeout

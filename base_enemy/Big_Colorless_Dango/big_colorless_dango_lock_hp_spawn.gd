extends State

# --- 開放面板調整，方便企劃隨時修改數值 ---
@export_category("🛡️ 鎖血召喚設定 (紫光保齡球)")

@export_group("時間與機制")
@export var invincible_duration: float = 1.5    # 無敵總時長。
@export var spawn_delay: float = 1.0            # 🌟 發呆幾秒後才把小怪吐出來？(營造聚氣的壓迫感)
@export var flash_color: Color = Color(0.8, 0.2, 1.0, 1.0) # 發光顏色

@export_group("召喚物設定")
@export var minion_scene: PackedScene           # 裝填小團子場景
@export var minion_spawn_count: int = 2         # 一次吐幾隻
@export var minion_spit_force: float = 750.0    # 🌟 修改：噴飛力道大幅提升！因為這是用來撞飛玩家的武器。

@export_group("視覺衝擊")
@export var screen_shake_intensity: float = 20.0 # 震屏強度 (調強一點，展現爆發感)
# 🌟【新增】：宣告爆開時要閃爍的危險紅光顏色 (紅光加滿、綠藍光歸零)
@export var danger_flash_color: Color = Color(1.0, 0.2, 0.2, 1.0)

var state_timer: float = 0.0  # 內部計時器
var has_spawned: bool = false # 狀態標記：記錄這回合是不是已經吐過了

# 📍 補在 LockHpSpawn.gd 最上方的變數區
@export var shrink_factor: float = 0.85 # 階梯式縮放係數：每次縮小為 85%
# 📍 1. 局部修改 LockHpSpawn 的 enter()
func enter():
	state_timer = 0.0   
	has_spawned = false 
	
	character.velocity = Vector2.ZERO # 1. 煞車停好
	
	# 2. 開啟無敵保護
	if "is_invincible" in character:
		character.is_invincible = true   
	
	# 3. 讓 Boss 轉向玩家
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
	
	# 🌟【正規作法】：不管今天是第幾個鎖血門檻 (80%, 60%, 40%, 20%)，
	# 全面強制播放 bomb (充氣爆炸動畫)，營造「每掉 20% 血就炸開脫皮一次」的強烈視覺！
	character.play_animation("bomb", character.last_facing_vec)
	
	# ⏱️ 將 bomb 動畫速度微調為 1.25 倍，確保在 1.0 秒的 spawn_delay 準時炸開
	if character.animated_sprite_2d:
		character.animated_sprite_2d.speed_scale = 1.25
	# 🌟【正規作法】：一進場（一被砍到扣血鎖血的瞬間），就立刻啟動持續閃紅光，一路閃到爆炸結束！
	_play_danger_flash()
	
func state_physics_update(delta: float):
	state_timer += delta 
	
	# 時間到了設定的延遲秒數 (1.0秒，剛好對齊 bomb 動畫充氣到極限炸開的瞬間)
	if state_timer >= spawn_delay and not has_spawned:
		has_spawned = true 
		
		# 吐出保齡球小怪，透過「肉塊飛散」的視覺來解釋本體變小的合理性
		_spawn_minions(minion_spawn_count)
		
		# 瞬間呼叫強烈震屏，增加打擊感與壓迫感
		var camera = character.get_tree().get_first_node_in_group("camera")
		if camera and camera.has_method("apply_shake"):
			camera.apply_shake(screen_shake_intensity)
		
		# 🌟【新增這行】：在爆炸的同時，強制讓身體閃一下危險的紅光！
		_play_danger_flash()
	# 🌟 總無敵時間 (1.5秒) 結束，狀態安全退場
	if state_timer >= invincible_duration:
		state_machine.change_state("move") 

# --- 內部功能函數 ---

func _play_custom_flash():
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if not mat: return
	
	var tween = create_tween()
	# 瞬間變色，接著慢慢褪色回純白
	tween.tween_property(mat, "shader_parameter/state_color", flash_color, 0.1)
	tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, invincible_duration - 0.1)

func _spawn_minions(count: int):
	if not character.minion_scene: return 
	
	for i in range(count):
		var minion = character.minion_scene.instantiate()
		character.get_parent().add_child(minion)
		
		# 保齡球是貼地射出的，所以我們讓它從肚子的位置 (Y微調) 出來
		minion.global_position = character.global_position + Vector2(0, -10)
		
		if character.player_node:
			# 算出指向玩家的基準線
			var dir_to_player = character.global_position.direction_to(character.player_node.global_position)
			
			# 🌟【正規作法：V字防守陣型 (Peel Spread)】
			var angle_offset = 0.0
			if count > 1:
				var spread_arc = 60.0 # 總張角 60 度
				angle_offset = -(spread_arc / 2.0) + (i * (spread_arc / (count - 1)))
				
			var throw_dir = dir_to_player.rotated(deg_to_rad(angle_offset))
			
			# 🧠【拔掉大腦插頭 (Disable AI)】
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false)
			
			# 🚀【極速發射】直接給予超高物理推力，讓子彈飛！
			if "velocity" in minion:
				minion.velocity = throw_dir * minion_spit_force
				if "last_facing_vec" in minion:
					minion.last_facing_vec = throw_dir
					minion.play_animation("move", throw_dir)
			
			# 🏀【微小的偽 3D 沉重彈跳視覺 (Heavy Bounce Juice)】
			var sprite = minion.get_node_or_null("AnimatedSprite2D")
			if sprite:
				var flight_time = 0.4 # 保齡球很重，所以滯空時間比一般吐怪短，落地極快
				var tween = create_tween()
				
				# 微微離地 (-30)
				tween.tween_property(sprite, "position:y", -30.0, flight_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				# 重重砸地 (0)
				tween.chain().tween_property(sprite, "position:y", 0.0, flight_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				
				# ⚡ 落地喚醒 (On Landing)
				tween.chain().tween_callback(func():
					if is_instance_valid(minion):
						# 落地瞬間強行踩死煞車，消除物理動能
						minion.velocity = Vector2.ZERO 
						# 插回大腦插頭，小怪開始追人！
						if "state_machine" in minion and minion.state_machine:
							minion.state_machine.set_physics_process(true) 
				)

# 📍 局部修改 2：更新底部的閃紅光函數，讓它涵蓋整段無敵時間 (invincible_duration)
# ==========================================
# 🔴 視覺演出：從蓄力到爆炸結束的持續危險紅光
# ==========================================
func _play_danger_flash() -> void:
	if not character.animated_sprite_2d: return
	
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if mat:
		var tween = create_tween()
		# 1. 瞬間染上危險紅光
		tween.tween_property(mat, "shader_parameter/state_color", danger_flash_color, 0.1)
		
		# 2. 在整段 invincible_duration (1.5秒) 爆炸過程結束前夕，慢慢褪回白色準備縮小
		# 我們把時間設定為 invincible_duration - 0.1 秒，讓紅光完美覆蓋整段蓄力與碎裂期
		tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, invincible_duration - 0.1)

# 📍 局部修改 2：在 exit() 裡執行「本體脫殼縮水」
func exit():
	# 1. 離開狀態時解除無敵與洗白材質顏色
	if "is_invincible" in character:
		character.is_invincible = false
		
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("state_color", Color.WHITE)
		
	# 恢復動畫正常播放倍速
	if character.animated_sprite_2d:
		character.animated_sprite_2d.speed_scale = 1.0
		
	# 🌟【正規作法：階梯式動態縮放 (Tiered Dynamic Scaling)】
	# 當 1.5 秒的 bomb 碎裂動畫完全播完、準備切回 move 的瞬間：
	# 將本體的 Scale 乘上 0.85。連續 4 次鎖血下來，王會精準變小一圈，
	# 碰撞箱也會同步縮小，讓玩家感受到「越打越靈活、越打越難纏」的恐怖進化！
	character.scale *= shrink_factor

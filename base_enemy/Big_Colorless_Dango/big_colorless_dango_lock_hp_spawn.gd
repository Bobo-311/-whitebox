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

var state_timer: float = 0.0  # 內部計時器
var has_spawned: bool = false # 狀態標記：記錄這回合是不是已經吐過了

func enter():
	state_timer = 0.0   
	has_spawned = false 
	
	character.velocity = Vector2.ZERO # 1. 煞車停好
	
	# 2. 開啟無敵保護
	if "is_invincible" in character:
		character.is_invincible = true   
	
	# 3. 讓 Boss 轉向，死盯著玩家準備發射
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
	character.play_animation("idle", character.last_facing_vec)
	
	_play_custom_flash() # 4. 播紫光
	
func state_physics_update(delta: float):
	state_timer += delta 
	
	# 🌟 核心邏輯 1：時間到了設定的「延遲秒數 (1.0)」，且還沒吐過，就發射保齡球！
	if state_timer >= spawn_delay and not has_spawned:
		_spawn_minions(minion_spawn_count)
		has_spawned = true 
		
		# 吐怪瞬間呼叫強烈震屏！
		var camera = character.get_tree().get_first_node_in_group("camera")
		if camera and camera.has_method("apply_shake"):
			camera.apply_shake(screen_shake_intensity)
	
	# 🌟 核心邏輯 2：總時間到了設定的「無敵時間 (1.5)」，結束狀態
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

func exit():
	# 離開時務必解除無敵與洗白顏色
	if "is_invincible" in character:
		character.is_invincible = false
		
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("state_color", Color.WHITE)

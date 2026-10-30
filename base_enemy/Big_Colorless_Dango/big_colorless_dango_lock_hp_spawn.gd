extends State # 繼承基礎狀態類別，交由狀態機 (StateMachine) 統一管理生命週期

# ==========================================
# ⚙️ 序列化設定面板 (開放給 Inspector 隨時微調數值)
# ==========================================
@export_category("🛡️ 鎖血召喚設定 (全程閃紅光預警＋等比例縮小版)")

@export_group("⏱️ 自爆與硬直時間軸 (核心節奏)")
@export var bomb_charge_time: float = 1.3       # 階段1 [閃紅光充氣期]：邊閃紅光邊充氣幾秒後引爆？
@export var post_explode_recovery: float = 0.5  # 階段2 [爆炸與喘息期]：炸開後在原地停留休息幾秒才恢復行動？
@export var shrink_factor: float = 0.85         # 等比例縮放係數：每次鎖血爆開後，長寬等比例縮小為 85%

@export_group("👶 召喚物設定")
@export var minion_scene: PackedScene           # 彈藥庫：裝填要吐出來的小團子場景 (.tscn)
@export var minion_spawn_count: int = 2         # 召喚數量：每次鎖血爆開時，同時吐出幾隻小團子
@export var minion_spit_force: float = 750.0    # 噴射推力：將小團子當成保齡球噴出去的初始物理速度

@export_group("💥 視覺衝擊與自爆閃紅光")
@export var screen_shake_intensity: float = 25.0 # 爆炸瞬間的相機震屏強度
# 🌟【局部修改 1：Shader 專用自爆鮮紅光】透過 Shader 的 state_color 讓本體在充氣期間強烈閃紅光！
@export var bomb_red_color: Color = Color(1.0, 0.15, 0.15, 1.0)

# (舊版參數保留相容，防止 .tscn 場景檔報警告)
@export_group("舊版相容保留 (勿動)")
@export var invincible_duration: float = 1.5
@export var spawn_delay: float = 1.0
@export var flash_color: Color = Color(0.8, 0.2, 1.0, 1.0)
@export var danger_flash_color: Color = Color(1.0, 0.2, 0.2, 1.0)

# ==========================================
# 🔒 內部狀態計時與防呆記憶變數
# ==========================================
var state_timer: float = 0.0        # 狀態內部碼錶：記錄進入鎖血狀態後經過了幾秒
var has_exploded: bool = false      # 單次爆炸鎖：記錄這一次鎖血是不是已經引爆並吐過小怪了
var _base_sprite_pos: Vector2       # 座標記憶：記住精靈圖原本的局部座標，供蓄力顫抖與跳躍落地精準歸位

# ==========================================
# 🎬 階段一：進入狀態 (復原正確長寬比例 + 啟動 bomb 動畫與紅光閃爍)
# ==========================================
func enter():
	state_timer = 0.0                 # 1. 重置內部計時碼錶歸零
	has_exploded = false              # 2. 重置引爆標記為「尚未引爆」
	character.velocity = Vector2.ZERO # 3. 瞬間踩死煞車，讓 Boss 停在原地開始充氣預警
	
	# 4. 開啟無敵保護鎖，防止 Boss 在自爆預警與硬直期間被玩家灌死
	if "is_invincible" in character:
		character.is_invincible = true   
	
	# 5. 更新 Boss 最後面向：讓牠正對著玩家的方向充氣與噴射小怪
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
	
	# 6. 🌟【局部修改 2：修正被壓扁的 Bug！】
	if character.animated_sprite_2d:
		_base_sprite_pos = Vector2.ZERO # 強制鎖定圖片局部原點為 (0, 0)
		
		# 【關鍵修復】：因為被打進鎖血的瞬間，老爸 BaseEnemy 的 play_hit_effects() 會把圖片壓扁成 (1.2, 0.8)，
		# 所以我們這裡直接強制把圖片比例重置回老爸開局存好的 original_sprite_scale，絕對不會再變扁！
		character.animated_sprite_2d.scale = character.original_sprite_scale
		character.animated_sprite_2d.position = _base_sprite_pos
		
		# 第一時間關閉老爸 BaseEnemy 殘留的受擊死白光 (flash_modifier = 0.0)
		var mat = character.animated_sprite_2d.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("flash_modifier", 0.0)
			mat.set_shader_parameter("state_color", bomb_red_color) # 第一幀直接先亮一下紅光！
			
		# 強制關閉 bomb 爆炸動畫的循環播放 (Loop)，避免炸完又自動跳回第 0 格
		if character.animated_sprite_2d.sprite_frames.has_animation("bomb"):
			character.animated_sprite_2d.sprite_frames.set_animation_loop("bomb", false)
			
		# 設定充氣爆炸動畫倍速
		character.animated_sprite_2d.speed_scale = 0.9
		
	# 呼叫本體開始播放 bomb (充氣爆炸) 動畫
	character.play_animation("bomb", character.last_facing_vec)

# ==========================================
# 🔄 物理更新迴圈 (全程 Shader 閃紅光預警 ➔ 引爆 ➔ 原地喘息硬直)
# ==========================================
func state_physics_update(delta: float):
	state_timer += delta # 每一物理幀推進碼錶時間
	
	# ------------------------------------------------------------------
	# 🔴【階段 1：自爆紅光預警期 (0.0 秒 ~ bomb_charge_time 1.3 秒)】
	# ------------------------------------------------------------------
	if not has_exploded and character.animated_sprite_2d:
		# 計算目前距離引爆的進度百分比 (0.0 剛開始 ➔ 1.0 即將引爆)
		var progress = clamp(state_timer / bomb_charge_time, 0.0, 1.0)
		
		# 🌟【局部修改 3：直接驅動 Shader 的 state_color 進行炸彈紅光閃爍！】
		# 【正規作法】：因為團子王身上掛著 ShaderMaterial，必須改動 shader_parameter/state_color 才看得到紅光！
		# 閃爍頻率從每秒約 3 次 (20.0) 隨時間加速到每秒約 10 次 (65.0)，越接近爆炸閃得越急促！
		var flash_speed = lerp(20.0, 65.0, progress)
		# 利用 cos 波讓一進場第 0 秒就是 1.0 (亮紅光)，接著在「原色 (0.0)」與「亮紅 (1.0)」之間強烈跳動
		var red_wave = (cos(state_timer * flash_speed) + 1.0) * 0.5
		
		# 在引爆前的最後 0.2 秒，強制鎖定在最紅的狀態
		if progress > 0.85:
			red_wave = 1.0
			
		var current_tint = Color.WHITE.lerp(bomb_red_color, red_wave)
		
		# 同時更新 Shader 的 state_color 與節點的 self_modulate，確保 100% 閃出鮮紅光！
		var mat = character.animated_sprite_2d.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("flash_modifier", 0.0) # 每幀壓住死白光，防止被受擊 Tween 蓋成白色
			mat.set_shader_parameter("state_color", current_tint)
		character.animated_sprite_2d.self_modulate = current_tint
		
		# 配合自爆閃紅光，讓身體產生越抖越劇烈的充氣顫抖 (1px 漸強至 5px)
		var shake_amt = lerp(1.0, 5.0, progress)
		character.animated_sprite_2d.position = _base_sprite_pos + Vector2(
			randf_range(-shake_amt, shake_amt),
			randf_range(-shake_amt, shake_amt)
		)
		# 每一幀強制鎖定原始長寬比，防止老爸受擊 Tween 在前 0.2 秒把王壓扁
		character.animated_sprite_2d.scale = character.original_sprite_scale
	
	# ------------------------------------------------------------------
	# 💥【階段 2：引爆瞬間！(當碼錶到達 1.3 秒 bomb_charge_time)】
	# ------------------------------------------------------------------
	if state_timer >= bomb_charge_time and not has_exploded:
		has_exploded = true # 上鎖：確保這波自爆只會觸發一次
		
		# 1. 停止充氣顫抖，將精靈圖位置與比例歸位
		if character.animated_sprite_2d:
			character.animated_sprite_2d.position = _base_sprite_pos
			character.animated_sprite_2d.scale = character.original_sprite_scale
			
		# 2. 噴射出保齡球小怪
		_spawn_minions(minion_spawn_count)
		
		# 3. 觸發相機強烈震屏，展現大爆炸威力
		var camera = character.get_tree().get_first_node_in_group("camera")
		if camera and camera.has_method("apply_shake"):
			camera.apply_shake(screen_shake_intensity)
			
		# 4. 執行「外殼繼續閃紅炸開 + 本體等比例縮小並原地休息」
		_execute_explosion_and_shrink()
		
	# ------------------------------------------------------------------
	# 😮‍💨【階段 3：爆炸後原地喘息硬直結束，恢復移動】
	# ------------------------------------------------------------------
	if has_exploded and state_timer >= (bomb_charge_time + post_explode_recovery):
		state_machine.change_state("move") 

# ==========================================
# 💥 視覺核心：外殼紅光炸散 ＋ 本體等比例縮小（不壓扁！）
# ==========================================
func _execute_explosion_and_shrink() -> void:
	var anim = character.animated_sprite_2d # 取得本體動畫節點
	if not anim: return # 防呆檢查
	
	# --- 步驟 A：【生成留在原地炸開的碎肉外殼】 ---
	var remnant = AnimatedSprite2D.new()        # 建立臨時的動畫節點作為「炸開的巨大外殼」
	remnant.sprite_frames = anim.sprite_frames  # 共用團子王的動畫圖庫
	remnant.animation = anim.animation          # 鎖定為當下正在播的 bomb 動畫
	remnant.frame = anim.frame                  # 直接從炸開的這一格繼續往下播
	remnant.speed_scale = 0.7                   # 放慢碎肉散開速度，讓爆炸畫面維持更久
	remnant.offset = anim.offset                # 同步中心偏移量
	remnant.centered = anim.centered            # 同步置中設定
	remnant.flip_h = anim.flip_h                # 同步左右翻轉方向
	remnant.self_modulate = Color(1.8, 0.35, 0.35, 1.0) # 炸開瞬間維持紅熱色澤
	
	character.get_parent().add_child(remnant)   # 將爆炸外殼掛載到世界地圖層
	remnant.global_position = anim.global_position # 對齊爆炸當下的世界座標
	remnant.global_scale = anim.global_scale    # 鎖定為「縮小前的巨大尺寸」留在原地炸開
	remnant.z_index = character.z_index + 1     # 圖層設為 +1，蓋在最前面
	remnant.play()                              # 開始播放後半段碎肉飛散動畫
	
	# 讓碎肉外殼在地上停留後平滑淡出並銷毀
	var rem_tween = create_tween().bind_node(remnant)
	rem_tween.tween_property(remnant, "self_modulate", Color.WHITE, 0.35)
	rem_tween.tween_interval(0.25)
	rem_tween.tween_property(remnant, "modulate:a", 0.0, 0.4)
	rem_tween.tween_callback(remnant.queue_free)
	
	# --- 步驟 B：【本體洗回原色、等比例縮小 85%（完全不壓扁！）】 ---
	anim.self_modulate = Color.WHITE # 將脫殼後的小本體洗回正常顏色
	anim.speed_scale = 1.0           # 將動畫播放速度恢復為正常的 1.0 倍
	anim.scale = character.original_sprite_scale # 🌟 強制鎖定原始長寬比例，絕不壓扁！
	
	var mat = anim.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("flash_modifier", 0.0)
		mat.set_shader_parameter("state_color", Color.WHITE) # 洗白 Shader 紅光，恢復正常團子王外觀
	
	# 🌟 執行等比例縮放：X 與 Y 同步乘上 0.85，維持完美圓潤比例！
	character.scale *= shrink_factor
	
	# 切換為 idle 待機動畫，在原地小跳步落地後安靜休息到硬直結束
	character.play_animation("idle", character.last_facing_vec)
	
	# 只做單純的 Y 軸高度往上跳出再落地，完全不動 scale 長寬比！
	var hop_tween = create_tween()
	hop_tween.tween_property(anim, "position:y", _base_sprite_pos.y - 45.0, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(anim, "position:y", _base_sprite_pos.y, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# ==========================================
# 👶 召喚物系統：保齡球小團子噴射邏輯
# ==========================================
func _spawn_minions(count: int):
	if not character.minion_scene: return 
	
	for i in range(count):
		var minion = character.minion_scene.instantiate()
		character.get_parent().add_child(minion)
		
		minion.global_position = character.global_position + Vector2(0, -10)
		
		if character.player_node:
			var dir_to_player = character.global_position.direction_to(character.player_node.global_position)
			
			var angle_offset = 0.0
			if count > 1:
				var spread_arc = 60.0
				angle_offset = -(spread_arc / 2.0) + (i * (spread_arc / (count - 1)))
				
			var throw_dir = dir_to_player.rotated(deg_to_rad(angle_offset))
			
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false)
			
			if "velocity" in minion:
				minion.velocity = throw_dir * minion_spit_force
				if "last_facing_vec" in minion:
					minion.last_facing_vec = throw_dir
					minion.play_animation("move", throw_dir)
			
			var sprite = minion.get_node_or_null("AnimatedSprite2D")
			if sprite:
				var flight_time = 0.4
				var tween = create_tween()
				
				tween.tween_property(sprite, "position:y", -30.0, flight_time / 2.0)\
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tween.chain().tween_property(sprite, "position:y", 0.0, flight_time / 2.0)\
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				
				tween.chain().tween_callback(func():
					if is_instance_valid(minion):
						minion.velocity = Vector2.ZERO 
						if "state_machine" in minion and minion.state_machine:
							minion.state_machine.set_physics_process(true) 
				)

# ==========================================
# 🚪 離開狀態清理 (確保長寬比例與材質 100% 乾淨復原)
# ==========================================
func exit():
	if "is_invincible" in character:
		character.is_invincible = false
		
	if character.animated_sprite_2d:
		character.animated_sprite_2d.speed_scale = 1.0
		character.animated_sprite_2d.position = _base_sprite_pos
		# 🌟 離開時再次確保精靈圖比例等於開局原始比例，徹底杜絕壓扁變形！
		character.animated_sprite_2d.scale = character.original_sprite_scale
		character.animated_sprite_2d.self_modulate = Color.WHITE
		character.animated_sprite_2d.modulate = Color.WHITE
		
		var mat = character.animated_sprite_2d.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("flash_modifier", 0.0)
			mat.set_shader_parameter("state_color", Color.WHITE)

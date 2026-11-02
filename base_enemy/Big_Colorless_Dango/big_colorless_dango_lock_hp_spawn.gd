extends State # 繼承基礎狀態類別，交由狀態機 (StateMachine) 統一管理生命週期

# ==========================================
# ⚙️ 序列化設定面板 (開放給 Inspector 隨時微調數值)
# ==========================================
@export_category("🛡️ 鎖血召喚設定 (全程閃紅光預警＋等比例縮小版)")

@export_group("⏱️ 自爆與硬直時間軸 (核心節奏)")
@export var bomb_charge_time: float = 1.3       # 階段1 [閃紅光充氣期]：邊閃紅光邊充氣幾秒後，動畫準備進入引爆？
@export var post_explode_recovery: float = 0.5  # 階段2 [爆炸與喘息期]：炸開後在原地停留休息幾秒才恢復行動？(0.5秒給玩家喘息)
@export var shrink_factor: float = 0.85         # 等比例縮放係數：每次鎖血爆開後，長寬等比例縮小為 85%

@export_group("👶 召喚物設定")
@export var minion_scene: PackedScene           # 彈藥庫：裝填要吐出來的小團子場景 (.tscn)
@export var minion_spawn_count: int = 2         # 召喚數量：每次鎖血爆開時，同時吐出幾隻小團子
@export var minion_spit_force: float = 750.0    # 噴射推力：將小團子當成保齡球噴出去的初始物理速度

@export_group("💥 視覺衝擊與三段紅光設定")
@export var screen_shake_intensity: float = 25.0 # 爆炸瞬間的相機震屏強度 (25.0 會有強烈震動感)
# 🌟【微調顏色】：把 HDR 數值降下來，並混入一點藍綠色(0.6)，讓它看起來像「充血」而不是「發光」
@export var charge_base_red: Color = Color(1.3, 0.6, 0.6, 1.0)  # 底色微紅
@export var charge_flash_red: Color = Color(2.0, 0.4, 0.4, 1.0)   # 閃爍暗紅
@export var explode_peak_red: Color = Color(2.8, 0.2, 0.2, 1.0)   # 爆炸瞬間的血紅

# ==========================================
# 🔒 內部狀態計時與防呆記憶變數
# ==========================================
var state_timer: float = 0.0                 # 狀態內部碼錶：計算狀態經過的時間
var has_exploded: bool = false               # 單次爆炸鎖：確保小怪與縮小邏輯只會執行一次
var _base_sprite_pos: Vector2 = Vector2.ZERO # 座標記憶：鎖定精靈圖局部原點 (0,0)，供顫抖歸位使用

# ==========================================
# 🎬 階段一：進入狀態 (啟動充氣、材質獨立化與紅光預警)
# ==========================================
func enter():
	state_timer = 0.0                 # 重置內部計時碼錶
	has_exploded = false              # 重置引爆標記為尚未引爆
	character.velocity = Vector2.ZERO # 瞬間踩死煞車，讓 Boss 停在原地
	
	# 開啟無敵保護鎖，防止 Boss 在充氣預警時被玩家連段灌死
	if "is_invincible" in character:
		character.is_invincible = true   
	
	# 更新面向：強制轉向玩家，確保噴小怪的方向正確
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
	
	# 處理精靈圖與 Shader 的初始化
	if character.animated_sprite_2d:
		var anim = character.animated_sprite_2d
		_base_sprite_pos = Vector2.ZERO
		
		# 🌟 恢復原始比例，消除老爸 BaseEnemy 受擊瞬間造成的壓扁變形
		anim.scale = character.original_sprite_scale
		anim.position = _base_sprite_pos
		
		# 🌟【關鍵防呆：材質獨立化 (Duplicate)】
		# 為了避免改動 Shader 紅光時影響到場上其他小怪，強制複製一份獨立的材質給這隻王！
		if anim.material != null:
			anim.material = anim.material.duplicate()
			var mat = anim.material as ShaderMaterial
			mat.set_shader_parameter("flash_modifier", 0.0)      # 關掉死白光
			mat.set_shader_parameter("state_color", charge_base_red) # 立刻染上基礎紅光
			
		# 強制關閉 bomb 動畫的迴圈，確保它只播一次
		if anim.sprite_frames.has_animation("bomb"):
			anim.sprite_frames.set_animation_loop("bomb", false)
			
		# 設定充氣動畫倍速為 0.9 倍，讓 1.3 秒的預警過程更長更飽滿
		anim.speed_scale = 0.9
		
		# 🌟【全新機制：精準影格對位】
		# 綁定 frame_changed 訊號，讓動畫親自告訴我們什麼時候播到了第 17 幀！
		if not anim.frame_changed.is_connected(_on_bomb_frame_changed):
			anim.frame_changed.connect(_on_bomb_frame_changed)
		
	# 呼叫本體開始播放 bomb 充氣動畫
	character.play_animation("bomb", character.last_facing_vec)

# ==========================================
# 🔄 階段二：物理更新迴圈 (控制紅光閃爍 ➔ 炸開後的發呆硬直)
# ==========================================
func state_physics_update(delta: float):
	state_timer += delta # 每一物理幀推進碼錶時間
	
	# ------------------------------------------------------------------
	# 🔴【充氣期：在引爆前全程驅動 Shader 閃爍紅光與顫抖】
	# ------------------------------------------------------------------
	if not has_exploded and character.animated_sprite_2d:
		var anim = character.animated_sprite_2d
		# 計算充氣進度 (0.0 剛開始 ➔ 1.0 即將引爆)
		var progress = clamp(state_timer / bomb_charge_time, 0.0, 1.0)
		
		# 🌟【微調頻率】：把 25.0~75.0 降為 12.0~35.0 (約每秒心跳 2 下加速到 5 下)
		# 這樣看起來會有「咚...咚...咚..咚.咚.咚！」的定時炸彈沉重感！
		var flash_speed = lerp(12.0, 35.0, progress)
		var wave = (cos(state_timer * flash_speed) + 1.0) * 0.5
		
		# 在「底色紅」與「高亮閃紅」之間來回過渡
		var current_red = charge_base_red.lerp(charge_flash_red, wave)
		
		# 最後 0.2 秒即將炸開前，把紅光往「極限深紅」推，營造引爆臨界點
		if progress > 0.85:
			var peak_t = (progress - 0.85) / 0.15
			current_red = current_red.lerp(explode_peak_red, peak_t)
			
		# 把算出來的顏色塞給專屬 Shader 的 state_color！
		var mat = anim.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("state_color", current_red)
		
		# 強制鎖定長寬比，防止老爸的受擊 Tween 在前段干擾
		anim.scale = character.original_sprite_scale
		
		# 讓身體產生 1.5px 漸強至 6.0px 的隨機顫抖，看起來快要撐爆了
		var shake_amt = lerp(1.5, 6.0, progress)
		anim.position = _base_sprite_pos + Vector2(
			randf_range(-shake_amt, shake_amt),
			randf_range(-shake_amt, shake_amt)
		)
		
	# ------------------------------------------------------------------
	# 😮‍💨【喘息期：爆炸後原地發呆結束，恢復移動】
	# ------------------------------------------------------------------
	# 注意：當 has_exploded 被觸發時，state_timer 會被歸零。
	# 所以這裡是在計算「爆炸後發呆了多久」，時間到就切回 move 狀態追玩家！
	if has_exploded and state_timer >= post_explode_recovery:
		state_machine.change_state("move") 

# ==========================================
# 🎯 階段三：精準影格攔截器 (當播到第 17 幀時觸發)
# ==========================================
func _on_bomb_frame_changed() -> void:
	if not character.animated_sprite_2d: return
	
	# 確保我們只在播放 bomb 動畫，而且還沒炸過的情況下檢查
	if character.animated_sprite_2d.animation == "bomb" and not has_exploded:
		
		# 🌟【關鍵對位】：當動畫完美播到第 17 幀 (肉塊炸開散落的那一刻)！
		if character.animated_sprite_2d.frame == 17:
			has_exploded = true # 上鎖，確保只炸一次
			
			# 1. 停止顫抖，將精靈圖位置與比例歸位
			character.animated_sprite_2d.position = _base_sprite_pos
			character.animated_sprite_2d.scale = character.original_sprite_scale
			
			# 2. 🌟【精準吐怪】：在肉塊炸開的這一瞬間，小怪跟著噴射出去！
			_spawn_minions(minion_spawn_count)
			
			# 3. 觸發相機強烈震屏，展現大爆炸威力
			var camera = character.get_tree().get_first_node_in_group("camera")
			if camera and camera.has_method("apply_shake"):
				camera.apply_shake(screen_shake_intensity)
				
			# 4. 執行「生成殘留碎肉 + 本體碰撞箱與視覺同步縮小」
			_execute_explosion_and_shrink()
			
			# 5. 重新歸零碼錶！讓 state_physics_update 開始專心倒數發呆喘息時間
			state_timer = 0.0

# ==========================================
# 💥 視覺核心：爆炸那刻紅光綻放 ＋ 碰撞箱與視覺同步縮小
# ==========================================
func _execute_explosion_and_shrink() -> void:
	var anim = character.animated_sprite_2d 
	if not anim: return 
	
	# --- 步驟 A：【生成留在原地炸開的碎肉外殼】 ---
	var remnant = AnimatedSprite2D.new()        # 建立臨時動畫節點
	remnant.sprite_frames = anim.sprite_frames  # 共用圖庫
	remnant.animation = anim.animation          # 鎖定 bomb 動畫
	remnant.frame = anim.frame                  # 關鍵：從第 17 幀繼續播！
	remnant.speed_scale = 0.65                  # 放慢碎肉散開速度，停留久一點
	remnant.offset = anim.offset                
	remnant.centered = anim.centered            
	remnant.flip_h = anim.flip_h                
	
	# 🌟【爆炸瞬間極紅】：因為 remnant 沒掛 Shader，我們直接用 self_modulate 染成極限深紅！
	remnant.self_modulate = explode_peak_red
	
	character.get_parent().add_child(remnant)      # 將爆炸外殼掛載到世界層
	remnant.global_position = anim.global_position # 對齊世界座標
	remnant.global_scale = anim.global_scale       # 鎖定為「縮小前的巨大尺寸」留在原地
	remnant.z_index = character.z_index + 1        # 蓋在 Boss 前面
	remnant.play()                                 # 繼續把後半段散落動畫播完
	
	# 讓爆炸碎肉在地上停留後平滑淡出並銷毀
	var rem_tween = create_tween().bind_node(remnant)
	rem_tween.tween_property(remnant, "self_modulate", Color(1.2, 0.9, 0.9, 1.0), 0.45)
	rem_tween.tween_interval(0.2)
	rem_tween.tween_property(remnant, "modulate:a", 0.0, 0.35)
	rem_tween.tween_callback(remnant.queue_free)
	
	# --- 步驟 B：【本體洗回原色、縮小視覺與碰撞箱！】 ---
	anim.speed_scale = 1.0                        
	anim.scale = character.original_sprite_scale  # 鎖定原始長寬比，絕不壓扁
	
	# 1. 🌟【視覺縮水】：X 與 Y 同步乘上 0.85
	character.scale *= shrink_factor
	
	
	# 切換為 idle 待機動畫，在原地小跳步落地後安靜休息到硬直結束
	character.play_animation("idle", character.last_facing_vec)
	
	# 將本體的 Shader 紅光褪回正常的白色
	var mat = anim.material as ShaderMaterial
	if mat:
		var hop_tween = create_tween().set_parallel(true)
		hop_tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, 0.3)
	
	# 單純的 Y 軸高度往上跳出再落地，不動 scale 長寬比
	var jump_seq = create_tween()
	jump_seq.tween_property(anim, "position:y", _base_sprite_pos.y - 45.0, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump_seq.tween_property(anim, "position:y", _base_sprite_pos.y, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)



# ==========================================
# 👶 召喚物系統：保齡球小團子噴射邏輯
# ==========================================
func _spawn_minions(count: int):
	# 防呆：如果面板沒放小怪場景則返回
	if not character.minion_scene: return 
	
	for i in range(count):
		var minion = character.minion_scene.instantiate() 
		character.get_parent().add_child(minion)          
		
		# 初始位置微調到大團子的肚子中心
		minion.global_position = character.global_position + Vector2(0, -10)
		
		if character.player_node:
			var dir_to_player = character.global_position.direction_to(character.player_node.global_position)
			
			# V 字防守陣型：利用 60 度扇形張角將小怪左右分開噴射
			var angle_offset = 0.0
			if count > 1:
				var spread_arc = 60.0
				angle_offset = -(spread_arc / 2.0) + (i * (spread_arc / (count - 1)))
				
			var throw_dir = dir_to_player.rotated(deg_to_rad(angle_offset))
			
			# 噴出階段先關閉小怪的 AI 狀態機
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false)
			
			# 賦予極高的物理推力，把小怪當保齡球射出
			if "velocity" in minion:
				minion.velocity = throw_dir * minion_spit_force
				if "last_facing_vec" in minion:
					minion.last_facing_vec = throw_dir
					minion.play_animation("move", throw_dir)
			
			# 讓小團子圖片在 0.4 秒內做出立體拋物線墜地
			var sprite = minion.get_node_or_null("AnimatedSprite2D")
			if sprite:
				var flight_time = 0.4
				var tween = create_tween()
				
				# 往上拋起 (-30)
				tween.tween_property(sprite, "position:y", -30.0, flight_time / 2.0)\
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				# 砸回地板 (0)
				tween.chain().tween_property(sprite, "position:y", 0.0, flight_time / 2.0)\
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				
				# 落地瞬間踩煞車，並重新喚醒小怪 AI 開始追玩家
				tween.chain().tween_callback(func():
					if is_instance_valid(minion):
						minion.velocity = Vector2.ZERO 
						if "state_machine" in minion and minion.state_machine:
							minion.state_machine.set_physics_process(true) 
				)

# ==========================================
# 🚪 離開狀態清理 (防呆復原)
# ==========================================
func exit():
	# 1. 解除無敵保護鎖
	if "is_invincible" in character:
		character.is_invincible = false
		
	# 2. 🌟【防呆清理】：拔掉動畫影格監聽器，避免影響到其他攻擊動作！
	if character.animated_sprite_2d and character.animated_sprite_2d.frame_changed.is_connected(_on_bomb_frame_changed):
		character.animated_sprite_2d.frame_changed.disconnect(_on_bomb_frame_changed)
		
	# 3. 確保精靈圖與 Shader 參數 100% 歸位
	if character.animated_sprite_2d:
		var anim = character.animated_sprite_2d
		anim.speed_scale = 1.0
		anim.position = _base_sprite_pos
		anim.scale = character.original_sprite_scale
		anim.self_modulate = Color.WHITE
		anim.modulate = Color.WHITE
		
		var mat = anim.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("flash_modifier", 0.0)
			mat.set_shader_parameter("state_color", Color.WHITE)

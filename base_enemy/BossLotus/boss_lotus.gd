extends Node2D

# ==========================================
# 📊 1. [企劃數值面板 - Design Parameters] 
# 【正規作法 - 數據驅動設計】：將所有會影響遊戲平衡的數值暴露給編輯器 (Inspector)。
# 這樣一來，企劃人員調整難度時，絕對不會動到原始碼，徹底杜絕人為修改引發的 Bug。
# ==========================================
@export_group("Boss 核心數值")
@export var max_hp: int = 500             # Boss 最大血量上限 (生命力基底)
@export var current_hp: int = 500         # Boss 當前血量 (初始化時需與 max_hp 同步)
@export var phase_2_threshold: int = 250  # 🌟 觸發二階狂暴的絕對血量門檻 (預設 50%)

# ==========================================
# 🔒 2. [內部狀態與防呆變數 - State Machine & Locks]
# 【正規作法 - 狀態隔離】：利用布林值 (bool) 鎖定狀態，防止玩家在不該輸出的時候偷打。
# ==========================================
# 🌟 [Transform 基準點記憶]：
# 為什麼要記這個？因為受擊時我們會讓王「震動」跟「放大」。
# 如果王在震動的瞬間又被打中，新的動畫會以「歪掉的位置」為基準，導致王永久走位變形！
var original_sprite_scale: Vector2 = Vector2.ONE 
var original_sprite_pos: Vector2 = Vector2.ZERO  

# 🌟 [獨立時間軸導播 Tween]：
var _hit_tween: Tween           # 專職管理「受擊閃爍與震動」。獨立出來是為了隨時 kill() 它，防止連擊時動畫互相打架。
var _phase_timeline: Tween      # 專職管理「戰鬥流程」。取代舊版的 AnimationPlayer，因為程式控制的 Tween 更具動態彈性。

var current_phase: int = 1      # 當前階段狀態機 (1 = 正常一階, 2 = 狂暴二階)
var is_transitioning: bool = false # 轉場無敵鎖：為 true 時，免疫一切傷害與負面狀態。
var current_active_tentacles: Array = [] # 追蹤場上存活的觸手，讓王擁有統一的「強制清場」生殺大權。

# 🌟 [正規色彩學 - 拒絕 HDR 泛光污染]：
# 為什麼用 Color(1.0, 0.2, 0.2)？
# 在 2D 像素遊戲中，RGB 任何一值超過 1.0 就會觸發引擎的 Glow(泛光) 導致像素邊緣模糊發白。
# 這裡嚴格控制在 1.0 內，保證二階狂暴紅依然保持極致銳利！
var phase_2_color: Color = Color(1.0, 0.2, 0.2) 

# ==========================================
# 🔌 3. [節點綁定區 - Node References]
# ==========================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D # 王的主體 Sprite
@onready var spawners = $Spawners                         # 負責生成螺旋子彈的砲台管理器
@onready var laser_weapon = $LaserWeapon                  # 負責發射雷射的武器管理器
@onready var boss_ui = $BossUI                            # Boss 專屬血條 UI 介面

# 🌟 [場景依賴注入]：綁定四個角落的觸手藍圖 (.tscn)
@export var tentacle_left_top: PackedScene    
@export var tentacle_left_down: PackedScene   
@export var tentacle_right_top: PackedScene   
@export var tentacle_right_down: PackedScene  

# ==========================================
# 💡 4. [初始化程序 - Initialization]
# ==========================================
func _ready() -> void:
	current_hp = max_hp # 遊戲開始，血量補滿
	
	if sprite:
		sprite.play("idle") 
		# 遊戲載入的第一幀，立刻記憶王在場景上的完美座標與大小
		original_sprite_scale = sprite.scale
		original_sprite_pos = sprite.position
	
	# 初始化血條名稱與最大值
	if boss_ui: boss_ui.init_boss("淵獄蓮華", max_hp)
	
	# 暖機完畢，正式交由一階時間軸接管戰局！
	_play_phase_1_timeline()

# ==========================================
# 🎬 5. [3A 級時間軸導播室 - Timeline Controller]
# 【類似思考】：用單一主線程 (Tween) 依序安排回調 (callback) 與等待 (interval)，
# 保證戰鬥的節奏如同齒輪般完美咬合，絕對不會發生「招式重疊」的 Bug。
# ==========================================

# 🌟【第一階段時間軸 (總時長嚴格鎖定 15 秒)】
# 節奏設計：穩定，帶有長達 3 秒的絕對淨空休息期，讓玩家有時間喘息與反擊。
func _play_phase_1_timeline() -> void:
	current_phase = 1
	# 【安全機制】：每次重啟迴圈前，必定先斬斷前一次的 Tween，防止幽靈程序雙開。
	if _phase_timeline and _phase_timeline.is_running(): _phase_timeline.kill()
	_phase_timeline = create_tween()
	
	# [0.0s] 王下達命令，生成觸手。
	_phase_timeline.tween_callback(trigger_vine_obstacles)
	
	# [1.0s ~ 5.0s] 預留 1 秒讓觸手落地，接著啟動順時針彈幕，掃射 4 秒。
	_phase_timeline.tween_interval(1.0)
	_phase_timeline.tween_callback(start_spiral_bullets.bind(true)) 
	_phase_timeline.tween_interval(4.0)
	_phase_timeline.tween_callback(stop_bullets) # 下達停火指令
	
	# [7.0s ~ 11.0s] 王喘息 2 秒，接著啟動逆時針彈幕，反向掃射 4 秒。
	_phase_timeline.tween_interval(2.0)
	_phase_timeline.tween_callback(start_spiral_bullets.bind(false))
	_phase_timeline.tween_interval(4.0)
	_phase_timeline.tween_callback(stop_bullets) 
	
	# 🌟【11.0s - 絕對清場命令】
	# 剝奪觸手的自主壽命！時間一到，王強制命令場上所有觸手啟動「死亡縮回」程序。
	_phase_timeline.tween_callback(_force_retract_all_tentacles)
	
	# [11.0s ~ 12.0s] 預留 1 秒鐘，專門用來等待觸手把「縮回地下」的動畫播完。
	_phase_timeline.tween_interval(1.0)
	
	# 🌟🌟🌟【12.0s ~ 15.0s - 絕對休息期】🌟🌟🌟
	# 王完全待機 3 秒。此時場地乾淨，是設計給玩家「貼王輸出」的黃金時間。
	_phase_timeline.tween_interval(3.0)
	
	# [15.0s] 一階循環結束，首尾相連重新啟動。
	_phase_timeline.tween_callback(_play_phase_1_timeline)

# 🌟【第二階段時間軸 (總時長壓縮至 10.5 秒)】
# 節奏設計：極速、高壓，縮短玩家的反應時間，休息期減半。
func _play_phase_2_timeline() -> void:
	current_phase = 2
	if _phase_timeline and _phase_timeline.is_running(): _phase_timeline.kill()
	_phase_timeline = create_tween()
	
	# [0.0s] 呼叫狂暴觸手 (極限預警速度)
	_phase_timeline.tween_callback(trigger_vine_obstacles)
	
	# [0.5s ~ 3.0s] 前搖縮短至 0.5s，立刻射出逆時針雷射掃射 2.5 秒。
	_phase_timeline.tween_interval(0.5)
	_phase_timeline.tween_callback(start_laser_sweep.bind(false))
	_phase_timeline.tween_interval(2.5)
	_phase_timeline.tween_callback(stop_laser_sweep)
	
	# [4.5s ~ 7.0s] 中間只休息 1.5s，立刻射出順時針雷射 2.5 秒。
	_phase_timeline.tween_interval(1.5)
	_phase_timeline.tween_callback(start_laser_sweep.bind(true))
	_phase_timeline.tween_interval(2.5)
	_phase_timeline.tween_callback(stop_laser_sweep)
	
	# 🌟【8.0s - 絕對清場命令】
	_phase_timeline.tween_interval(1.0)
	_phase_timeline.tween_callback(_force_retract_all_tentacles)
	
	# [8.0s ~ 9.0s] 等待觸手縮回動畫播完。
	_phase_timeline.tween_interval(1.0)
	
	# 🌟🌟🌟【9.0s ~ 10.5s - 高壓休息期】🌟🌟🌟
	# 狂暴階段休息時間大減，僅留 1.5 秒空窗期，大幅增加走位壓力。
	_phase_timeline.tween_interval(1.5)
	
	# [10.5s] 二階循環結束，重新啟動！
	_phase_timeline.tween_callback(_play_phase_2_timeline)

# 🌟【強制清場工具 - Memory & Scene Cleanup】
# 遍歷王追蹤的觸手陣列，下令它們自我了斷，從根本上解決「觸手重疊不肯走」的 Bug。
func _force_retract_all_tentacles() -> void:
	for tentacle in current_active_tentacles:
		if is_instance_valid(tentacle) and tentacle.has_method("_die"):
			tentacle._die() 
	current_active_tentacles.clear() # 清空追蹤陣列，釋放參照

# ==========================================
# 🩸 6. [傷害計算與轉階邏輯 - Combat & Transitions]
# ==========================================
func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	# 【機制設計】：BOSS 免疫近戰判定，強迫玩家必須用子彈射擊。
	if is_melee: return 
	
	# 【無敵鎖定】：血量歸零正在播死亡動畫，或正在播「轉場變身」時，無效化一切傷害。
	if current_hp <= 0 or is_transitioning: return 
	
	current_hp -= int(amount)
	
	# 🌟【硬性血量鎖 (Hard Lock) - 守護演出完整性】：
	# 防止玩家武器傷害太高直接一擊秒殺，破壞遊戲體驗。
	# 只要是一階，且血量低於門檻，強制把血量鎖在 50%，並啟動變身！
	if current_hp <= phase_2_threshold and current_phase == 1:
		current_hp = phase_2_threshold 
		if boss_ui: boss_ui.update_health(current_hp)
		_enter_phase_2() 
		return 
		
	# 正常扣血處理，用 clampi 確保數值絕對不會低於 0，防止 UI 顯示負數血條
	current_hp = clampi(current_hp, 0, max_hp)
	if boss_ui: boss_ui.update_health(current_hp)
	
	# 呼叫視覺回饋
	if current_hp > 0: _play_hit_flash_tween()
	if current_hp <= 0: _die()

# ==========================================
# 🌟🔥 7. [3A 級二階變身演出 - Phase Transition Effects]
# 【類似思考】：《空洞騎士》王在半血時，仰天咆哮、全身顫抖並炸出衝擊波，強化「狂暴化」的儀式感。
# ==========================================
func _enter_phase_2() -> void:
	is_transitioning = true # 啟動無敵鎖
	
	# 1. 🌟【斬斷所有干擾】：
	# 殺死主時間軸(停止攻擊)，並強制殺死「受擊閃爍」，防止閃白動畫把接下來要變的「紅色」給洗掉。
	if _phase_timeline and _phase_timeline.is_running(): _phase_timeline.kill()
	if _hit_tween and _hit_tween.is_running(): _hit_tween.kill() 
	
	# 2. 🌟【淨空舞台準備表演】：
	# 停火 -> 清除所有殘留子彈 -> 強制觸手縮回，給玩家純粹的 Boss 特寫。
	stop_bullets()
	var old_bullets = get_tree().get_nodes_in_group("boss_bullets")
	for bullet in old_bullets:
		if is_instance_valid(bullet): bullet.queue_free() 
	_force_retract_all_tentacles()
	
	# 3. 切換到痛苦/蓄力動畫，並呼叫特效函式
	if sprite: 
		sprite.play("hurt") 
		_play_phase_transition_effect()
	
	# 給予整整 3 秒的表演時間，時間一到解除無敵，正式開戰。
	get_tree().create_timer(3.0).timeout.connect(finish_transition)

# 🌟【純程式碼生成的爆氣特效 (Programmatic Juice)】
func _play_phase_transition_effect() -> void:
	# 使用 parallel(true) 讓變色與震動同時發生
	var trans_tween = create_tween().set_parallel(true)
	
	# A. 【漸變上色】：利用 2.5 秒的時間，讓王緩慢且不祥地染上深血紅色。
	trans_tween.tween_property(sprite, "modulate", phase_2_color, 2.5).set_trans(Tween.TRANS_SINE)
	
	# B. 【極限顫抖】：每 0.05 秒位移一次 (偏移再拉回)，持續 2.5 秒，營造能量即將失控的視覺張力。
	var shake_tween = create_tween().set_loops(25) 
	shake_tween.tween_property(sprite, "position", original_sprite_pos + Vector2(randf_range(-10,10), randf_range(-10,10)), 0.05)
	shake_tween.tween_property(sprite, "position", original_sprite_pos, 0.05)
	
	# 等待 2.5 秒的蓄力期結束
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree(): return # 安全檢查，防止 Boss 已被刪除導致報錯
	
	# C. 【全螢幕巨震】：呼叫相機系統，給予 30 級的強力震動宣告二階來臨。
	var camera = get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"): camera.apply_shake(30.0)
	
	# D. 【爆氣衝擊波】：純靠 Line2D 與數學 (TAU圓周率) 生成 32 邊形的完美紅圈。
	var shockwave = Line2D.new()
	shockwave.width = 15.0
	shockwave.default_color = phase_2_color
	shockwave.closed = true
	var points = PackedVector2Array()
	for i in range(32):
		var angle = TAU * float(i) / 32.0
		points.append(Vector2(cos(angle)*100, sin(angle)*100))
	shockwave.points = points
	shockwave.position = original_sprite_pos
	add_child(shockwave)
	
	# E. 【衝擊波擴散動畫】：瞬間放大 10 倍 (Scale) 同時透明度歸零 (Alpha = 0)，播完自動刪除。
	var blast_tween = create_tween().set_parallel(true)
	blast_tween.tween_property(shockwave, "scale", Vector2(10.0, 10.0), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	blast_tween.tween_property(shockwave, "modulate:a", 0.0, 0.5)
	blast_tween.chain().tween_callback(shockwave.queue_free)
	
	# F. 🌟【強制底色定調】：將王永久定調為狂暴紅，並覆寫其基準放大比例 (1.1倍)，增加視覺威壓感。
	current_phase = 2 
	sprite.modulate = phase_2_color 
	original_sprite_scale = original_sprite_scale * 1.1 
	sprite.scale = original_sprite_scale

# 變身演出結束，還原待機動畫，正式進入二階。
func finish_transition() -> void:
	is_transitioning = false 
	if sprite:
		sprite.play("idle") 
		sprite.position = original_sprite_pos # 重置可能因震動而殘留偏移的位置
	_play_phase_2_timeline()

# ==========================================
# 🎯 8. [機制1 - 智能生成藤蔓路障] (絕對對角線映射)
# ==========================================
func trigger_vine_obstacles() -> void:
	# 防呆檢查：確認企劃有在 Inspector 中掛載 4 個觸手的 Scene，沒有的話印出錯誤並中斷，防止崩潰。
	if not (tentacle_left_top and tentacle_left_down and tentacle_right_top and tentacle_right_down):
		print("❌ [嚴重錯誤] 觸手場景丟失！請檢查 BossLotus 的 Inspector。")
		return

	var player = get_tree().get_first_node_in_group("Player")
	var spawn_data = [] 
	
	# 🌟【空間邏輯核心 - 動態封路演算法】：
	# 原則：觸手必須「朝向場地正中央」砸，所以生成藍圖必須是跟它所在角落「完全對角線反轉」的面向！
	# 例如：在左上角的生成點 (LeftTop)，必須塞入面向右下打 (RightDown) 的觸手場景。
	if player:
		# 計算玩家與 Boss 的相對座標距離
		var dx = player.global_position.x - self.global_position.x
		var dy = player.global_position.y - self.global_position.y
		
		# 比較 X 與 Y 的絕對值，判斷玩家傾向橫向還是縱向
		if abs(dx) > abs(dy):
			if dx < 0: 
				# 玩家在左邊 -> 封鎖左側上下牆壁
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_right_down})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_right_top})
			else:      
				# 玩家在右邊 -> 封鎖右側上下牆壁
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_left_down})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_left_top})
		else:
			if dy < 0: 
				# 玩家在上方 -> 封鎖上方左右牆壁
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_right_down})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_left_down})
			else:      
				# 玩家在下方 -> 封鎖下方左右牆壁
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_right_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_left_top})
	else:
		# 【防呆】：如果找不到玩家(可能剛好死亡)，備用邏輯為「全場 4 個角落全部封鎖」。
		spawn_data = [
			{"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_right_down},
			{"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_right_top},
			{"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_left_down},
			{"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_left_top}
		]
	
	# 實體化所有挑選出來的觸手
	for data in spawn_data:
		var new_tentacle = data["scene"].instantiate()
		new_tentacle.global_position = data["pos"]
		
		# 🌟【難度屬性動態覆寫】：依據當前是幾階，王直接把難度參數覆寫進觸手體內。
		if current_phase == 2:
			new_tentacle.max_hp = 45          # 二階血量變多
			new_tentacle.telegraph_time = 0.5 # 🌟 二階極限壓迫：紅圈預警瞬間完成 (0.5秒)
		else:
			new_tentacle.max_hp = 30
			new_tentacle.telegraph_time = 1.0 # 🌟 一階給予玩家充分反應時間 (1.0秒)
			
		get_parent().add_child(new_tentacle)
		current_active_tentacles.append(new_tentacle) # 登錄進追蹤清單，方便王強制清場
		
		# 下達攻擊指令，讓觸手開始播預警與砸下
		if new_tentacle.has_method("execute_smash"):
			new_tentacle.execute_smash()

# ==========================================
# 🎯 9. [武器控制 API - Weapon Controls]
# ==========================================
func start_spiral_bullets(is_clockwise: bool) -> void:
	if sprite: sprite.play("attack_bullet")
	if is_clockwise: spawners.start_clockwise()
	else: spawners.start_counter_clockwise()

func stop_bullets() -> void:
	spawners.stop_all()
	# 停火後，除非正在變身，否則回到喘息動畫
	if sprite and not is_transitioning: sprite.play("pant") 

func start_laser_sweep(is_clockwise: bool) -> void:
	if sprite:
		sprite.play("laser_start")
		# 透過 connect 聽取動畫結束事件，無縫接軌無限循環的 laser_loop 動畫
		sprite.animation_finished.connect(func():
			if sprite.animation == "laser_start": sprite.play("laser_loop")
		, CONNECT_ONE_SHOT) 
	if laser_weapon: laser_weapon.fire_laser(is_clockwise)

func stop_laser_sweep() -> void:
	if laser_weapon: laser_weapon.stop_laser()
	if sprite and not is_transitioning:
		sprite.play("laser_end")
		# 雷射收招結束後接回喘息動畫
		sprite.animation_finished.connect(func():
			if sprite.animation == "laser_end": sprite.play("pant")
		, CONNECT_ONE_SHOT)

# ==========================================
# ✨ 10. [視覺打磨：高對比色彩受擊閃爍 - Hit Juice]
# 【正規作法】：不使用超過 1.0 的 RGB 數值避免 HDR 模糊，純靠「反差色」建立極大對比度。
# ==========================================
func _play_hit_flash_tween() -> void:
	if not sprite: return
	
	# 【防交錯衝突】：如果還在播上一次的受傷動畫，先強制砍死並還原基準屬性。
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
		sprite.scale = original_sprite_scale
		sprite.position = original_sprite_pos
	
	# 記錄受傷前正在播的動作（例如正在噴雷射），以便受傷閃爍完能接續播放。
	var previous_anim = sprite.animation
	var previous_frame = sprite.frame
	
	sprite.play("hurt") # 切換至受傷臉
	
	_hit_tween = create_tween().set_parallel(true)
	
	# 🌟【色彩對比策略】：
	if current_phase == 1:
		# 一階 (本體白底)：被打時瞬間閃成「純紅色」，再用 0.2 秒漸變回「純白色」。
		sprite.modulate = Color(1.0, 0.0, 0.0) 
		_hit_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
	else:
		# 二階 (本體紅底)：被打時瞬間反向閃成「純白色」，再用 0.2 秒漸變回「深血紅色」。
		sprite.modulate = Color.WHITE 
		_hit_tween.tween_property(sprite, "modulate", phase_2_color, 0.2)
	
	# 【肉質打擊感】：讓王受擊瞬間膨脹 15% (配合 EXPO_OUT 曲線)，產生類似果凍被擠壓的 Q 彈感。
	sprite.scale = original_sprite_scale * 1.15
	_hit_tween.tween_property(sprite, "scale", original_sprite_scale, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# 【高頻隨機位移】：利用 5 次迴圈寫出短暫的顫抖效果。
	for i in range(5):
		var random_offset = Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
		_hit_tween.tween_property(sprite, "position", original_sprite_pos + random_offset, 0.02).set_delay(i * 0.02)
	# 最後一步：確保震完一定歸位，不走樣。
	_hit_tween.tween_property(sprite, "position", original_sprite_pos, 0.02).set_delay(0.1) 

	# 閃爍動畫全部跑完後，執行回調函式恢復之前的動作。
	_hit_tween.chain().tween_callback(func():
		if current_hp > 0 and is_instance_valid(sprite) and not is_transitioning:
			# 如果原本不是播受傷或死亡，就恢復原狀
			if previous_anim != "hurt" and previous_anim != "die":
				sprite.play(previous_anim)
				# 如果原本的動作是循環動畫(如雷射loop)，則回到上一幀繼續播，做到無縫接軌。
				if sprite.sprite_frames.get_animation_loop(previous_anim):
					sprite.set_frame_and_progress(previous_frame, 0.0)
	)

# ==========================================
# 💀 11. [死亡收尾 - Death Sequence]
# ==========================================
func _die() -> void:
	# 1. 斬斷導播時間軸、所有武器停火，防止「死後還在發射子彈」的低級 Bug。
	if _phase_timeline and _phase_timeline.is_running(): _phase_timeline.kill() 
	if spawners: spawners.stop_all()
	if laser_weapon: laser_weapon.stop_laser()

	# 2. 清除場上所有正在飛行的子彈 (垃圾回收 GC)。
	var old_bullets = get_tree().get_nodes_in_group("boss_bullets")
	for bullet in old_bullets:
		if is_instance_valid(bullet): bullet.queue_free()

	# 3. 讓所有忠心護主的觸手跟隨王一起退場 (優雅縮回)。
	_force_retract_all_tentacles()

	# 4. 關閉王的物理與受擊碰撞框，變成一具屍體，讓玩家可以直接穿梭過去。
	if has_node("CollisionShape2D"): $CollisionShape2D.set_deferred("disabled", true)
	if has_node("Hurtbox/CollisionShape2D"): $Hurtbox/CollisionShape2D.set_deferred("disabled", true)
		
	if sprite: sprite.play("die") # 播放枯萎動畫
	
	# 5. 死亡淡出消失演出：變暗黑 -> 緩慢透明化 (Alpha=0) -> 徹底 queue_free() 刪除節點釋放效能。
	var tween = create_tween().set_parallel(false) 
	tween.tween_property(sprite, "modulate", Color(0.2, 0.2, 0.2, 1.0), 1.0) 
	tween.tween_property(sprite, "modulate:a", 0.0, 1.5) 
	tween.finished.connect(func(): queue_free())

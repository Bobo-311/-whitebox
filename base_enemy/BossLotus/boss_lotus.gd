extends Node2D

# ==========================================
# 📊 [數值面板] - 可以在 Godot 右側 Inspector 直接調整
# ==========================================
@export_group("Boss 核心數值")
@export var max_hp: int = 500
@export var current_hp: int = 500

# 設定低於多少血量時進入第二階段 (預設 50%，也就是 250)
@export var phase_2_threshold: int = 250 

# 目前的階段狀態
var current_phase: int = 1
var is_transitioning: bool = false # 狀態鎖：是否正在播放轉場動畫？(此期間無敵)
# 用來暫存當下「正在預警中」的觸手實體
var current_active_tentacles: Array = []

# ==========================================
# 節點抓取區
# ==========================================
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar = $HealthBar 
@onready var spawners = $Spawners # 綁定發射器模組
@onready var laser_weapon = $LaserWeapon # 抓取剛做好的雷射部門

# (之後實作發射器時會用到，先寫好放著)
@onready var pivot_clockwise = $Spawners/Pivot_Clockwise
@onready var pivot_counter = $Spawners/Pivot_Counter

# ==========================================
# 📦 [備註] 觸手彈藥庫 (在 Inspector 中填入對應的場景)
# ==========================================
@export var tentacle_left_top: PackedScene    # 放入 觸手_左上.tscn
@export var tentacle_left_down: PackedScene   # 放入 觸手_左下.tscn
@export var tentacle_right_top: PackedScene   # 放入 觸手_右上.tscn
@export var tentacle_right_down: PackedScene  # 放入 觸手_右下.tscn



# ==========================================
# 💡 啟動函數
# ==========================================
func _ready() -> void:
	current_hp = max_hp
	
	# 確保開局播放正確的待機圖片
	if sprite:
		sprite.play("idle_down")
	
	# 初始化血條
	if health_bar and health_bar.has_method("init_health"):
		health_bar.init_health(max_hp)
		
	print("🌺 淵獄蓮華正式降臨！進入第一階段。")
	_play_phase_1_timeline()

# ==========================================
# 🎬 時間軸導播室 (核心)
# ==========================================
func _play_phase_1_timeline() -> void:
	current_phase = 1
	if anim_player.has_animation("Phase1_Loop"):
		anim_player.play("Phase1_Loop")
	print("▶️ 啟動 第一階段 時間軸 (15秒循環)")

func _play_phase_2_timeline() -> void:
	current_phase = 2
	print("🚨 進入狂暴第二階段！")
	
	# 強制停止一階的時間軸，避免兩邊的指令打架
	anim_player.stop()
	
	# 視覺表現：讓蓮華花瓣泛紅 (用 Tween 讓顏色平滑漸變 0.5 秒)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), 0.5)
	
	if anim_player.has_animation("Phase2_Loop"):
		anim_player.play("Phase2_Loop")
	print("▶️ 啟動 第二階段 時間軸 (12秒循環)")

# ==========================================
# 🩸 受擊與階段切換 (由 Hurtbox 觸發)
# ==========================================
func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	
	# 💡【無敵判定】如果已經死了，或是「正在轉場中 (播放變色動畫)」，免疫一切傷害！
	if current_hp <= 0 or is_transitioning: 
		return 

	# 扣除血量
	current_hp -= int(amount)
	
	# 🌟【一階轉二階：硬性血量鎖與斷招】
	if current_hp <= phase_2_threshold and current_phase == 1:
		# 1. 強制把血量鎖在 50% (例如 250)，確保玩家的大招不會把二階的血也扣掉
		current_hp = phase_2_threshold 
		
		# 2. 更新 UI 血條 (確保血條停在剛好一半)
		if health_bar and health_bar.has_method("update_health"):
			health_bar.update_health(current_hp)
			
		print("🛡️ 觸發硬性血量鎖！目前血量鎖定在：", current_hp)
		
		# 3. 呼叫轉場演出 (裡面會自動執行武器停火與清空場上彈幕)
		_enter_phase_2() 
		return # 攔截掉後續的一般受擊邏輯，直接退出！
		
	# 確保血量不低於 0
	current_hp = clampi(current_hp, 0, max_hp)
	print("💥 淵獄蓮華受傷！剩餘血量：", current_hp)
	
	# 一般更新 UI 血條
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_hp)
	
	# 一階與二階的日常受擊視覺反饋 (血量還沒歸零時)
	if current_hp > 0:
		_play_hit_flash_tween()
		
	# 🌟【終極死亡判定】
	if current_hp <= 0:
		_die()
# ==========================================
# 🎬 [演出邏輯] 進入第二階段 (狂暴化轉場)
# ==========================================
func _enter_phase_2() -> void:
	print("🔥 血量低於 50%，啟動二階狂暴轉場！")
	
	is_transitioning = true # 上鎖，進入無敵狀態
	current_phase = 2       # 紀錄已進入二階
	
	# 1. 【武器停火】關閉一階的雙螺旋發射器
	spawners.stop_all()
	
	# 2. 【全場清盤 (Board Wipe)】銷毀場上所有殘存的火球
	var old_bullets = get_tree().get_nodes_in_group("boss_bullets")
	for bullet in old_bullets:
		if is_instance_valid(bullet):
			bullet.queue_free() # 瞬間引爆
	print("🧹 一階彈幕清空完畢！")
	
	# 3. 【強制中斷】停止目前正在跑的 Phase1_Loop
	anim_player.stop()
	
	# 4. 【啟動轉場動畫】呼叫我們在 AnimationPlayer 裡做好的 Phase_Transition
	if anim_player.has_animation("Phase_Transition"):
		anim_player.play("Phase_Transition")
	else:
		# 防呆：如果你還沒做好轉場動畫，就直接硬切過去
		print("⚠️ 找不到轉場動畫，強制進入二階！")
		finish_transition()

# ==========================================
# 📡 [公開 API] 供 Phase_Transition 動畫在結尾 (第3.0秒) 呼叫
# ==========================================
func finish_transition() -> void:
	print("⚠️ 轉場結束，二階正式開始！解除無敵！")
	is_transitioning = false # 解開無敵鎖
	
	# 這才是真正啟動二階循環的地方
	if anim_player.has_animation("Phase2_Loop"):
		anim_player.play("Phase2_Loop")
	print("▶️ 啟動 第二階段 時間軸 (雷射狂暴化)")
# ==========================================
# ✨ 受傷視覺反饋 (切換圖片 + 閃光，不干擾主時間軸)
# ==========================================
func _play_hit_flash_tween() -> void:
	if sprite:
		# 1. 播放真實的受傷圖片
		sprite.play("hurt_down")
		
		# 2. 依然保留紅光 Tween 增加打擊感 (兩者疊加效果最好！)
		var tween = create_tween()
		sprite.modulate = Color(3.0, 0.2, 0.2)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
		
		# 3. 啟動一個超短計時器，受傷圖播完後，切回原本的待機圖 (約 0.3 秒)
		get_tree().create_timer(0.3).timeout.connect(func():
			# 安全檢查：確保 Boss 還活著才切回 idle
			if current_hp > 0 and is_instance_valid(sprite):
				sprite.play("idle_down")
		)

# ==========================================
# 💀 正式死亡流程 (斷招、清盤與動畫)
# ==========================================
func _die() -> void:
	print("💀 淵獄蓮華 死亡崩潰中... 啟動全場清盤邏輯！")
	
	# ==================================
	# 🧹 1. 武器拔插頭 (Power Off)
	# ==================================
	# 停止大腦排程 (不再呼叫任何新指令)
	anim_player.stop()
	
	# 強制關閉螺旋發射器
	if spawners and spawners.has_method("stop_all"):
		spawners.stop_all()
		
	# 強制關閉二階雷射死光 (避免雷射掃到一半王死了還在掃)
	if laser_weapon and laser_weapon.has_method("stop_laser"):
		laser_weapon.stop_laser()

	# ==================================
	# 🧹 2. 場地大清盤 (Board Wipe)
	# ==================================
	# 瞬間銷毀場上所有殘存的螺旋子彈
	var old_bullets = get_tree().get_nodes_in_group("boss_bullets")
	for bullet in old_bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()
	print("✨ 殘留彈幕與雷射已強制清除！")

	# ==================================
	# 🛡️ 3. 物理判定關閉 (變成布景)
	# ==================================
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if has_node("Hurtbox/CollisionShape2D"):
		$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
		
	# ==================================
	# 🎬 4. 死亡視覺演出
	# ==================================
	# 播放真實的死亡圖片
	if sprite:
		sprite.play("die_down")
	
	# 製造死亡崩壞特效 (利用 Tween 漸黑與淡出)
	var tween = create_tween().set_parallel(false) # 序列執行
	tween.tween_property(sprite, "modulate", Color(0.2, 0.2, 0.2, 1.0), 1.0) # 1秒內變黑炭
	tween.tween_property(sprite, "modulate:a", 0.0, 1.5) # 再花 1.5 秒慢慢化成灰燼
	
	# 特效播完後，呼叫結算函數
	tween.finished.connect(_on_death_animation_finished)

# ==========================================
# 🎉 死亡動畫播完後的處理 (通關結算)
# ==========================================
func _on_death_animation_finished() -> void:
	print("🎉 淵獄蓮華 已徹底消滅！")
	# TODO: 發送勝利信號、掉落物品等
	queue_free()

# ==========================================
# 🎯 招式 API 接口 (供 AnimationPlayer 呼叫)
# ==========================================

# ==========================================
# 🎯 [機制1] 生成藤蔓路障 (十字象限完美包圍版)
# ==========================================
func trigger_vine_obstacles() -> void:
	# [防呆檢查] 確保 4 個觸手的場景檔案 (PackedScene) 都有在右側 Inspector 填好
	if not (tentacle_left_top and tentacle_left_down and tentacle_right_top and tentacle_right_down):
		print("❌ 錯誤：四個角落的觸手場景未填滿！")
		return

	# [索敵] 利用 Group (群組) 在整個遊戲場景中尋找名為 "Player" 的節點
	var player = get_tree().get_first_node_in_group("Player")
	
	# [裝備籃] 用來暫存「這次判定後，到底要生成哪幾根觸手」的清單
	var spawn_data = [] 
	
	if player:
		# [計算距離] 算出玩家與 Boss 之間 X 軸與 Y 軸的距離差
		# 舉例：dx 為負代表玩家在 Boss 左邊，dy 為正代表玩家在 Boss 下方
		var dx = player.global_position.x - self.global_position.x
		var dy = player.global_position.y - self.global_position.y
		
		# [象限判定核心] 比較 X 距離與 Y 距離的「絕對值 (abs)」
		# 如果 X 的差距 > Y 的差距，代表玩家明顯偏向「左」或「右」
		if abs(dx) > abs(dy):
			if dx < 0: # 玩家在【左】-> 砸下左上、左下，包夾左側
				print("🎯 玩家在【左】，砸下左上、左下！")
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_left_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_left_down})
			else:      # 玩家在【右】-> 砸下右上、右下，包夾右側
				print("🎯 玩家在【右】，砸下右上、右下！")
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_right_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_right_down})
		# 如果 Y 的差距 > X 的差距，代表玩家明顯偏向「上」或「下」
		else:
			if dy < 0: # 玩家在【上】-> 砸下左上、右上，包夾上方
				print("🎯 玩家在【上】，砸下左上、右上！")
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_left_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_right_top})
			else:      # 玩家在【下】-> 砸下左下、右下，包夾下方
				print("🎯 玩家在【下】，砸下左下、右下！")
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_left_down})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_right_down})
	else:
		# [備案] 如果玩家死掉或沒掛 Player 群組，就 4 根全砸
		print("⚠️ 找不到玩家，執行四方全域封鎖！")
		spawn_data = [
			{"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_left_top},
			{"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_left_down},
			{"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_right_top},
			{"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_right_down}
		]

	# [執行生成] 迴圈讀取 spawn_data
	for data in spawn_data:
		var new_tentacle = data["scene"].instantiate()
		new_tentacle.global_position = data["pos"]
		
		# 🌟【正規作法：動態難度注入 (Dynamic Scaling)】
		# 如果目前是第二階段，我們在大腦這裡，直接篡改觸手的數值！
		# 這樣就不用麻煩地去建一個全新的二階觸手場景檔了。
		if current_phase == 2:
			new_tentacle.max_hp = 45        # 血量變厚 (原本 30)
			new_tentacle.current_hp = 45    # 當前血量也要跟著變
			new_tentacle.lifespan = 11.5    # 在場上活久一點 (原本 11.0)
		else:
			# 如果是一階，就給它預設值 (確保程式不出錯)
			new_tentacle.max_hp = 30
			new_tentacle.current_hp = 30
			new_tentacle.lifespan = 11.0
			
		# 加到場景上，並把它存進大腦的記憶清單，等一下好使喚它砸下
		get_parent().add_child(new_tentacle)
		current_active_tentacles.append(new_tentacle)

# ==========================================
# 🎯 [機制1-補充] 命令預警觸手正式砸下
# ==========================================
func smash_vine_obstacles() -> void:
	print("💥 導演指令：全體觸手立刻砸擊！")
	
	# 點名所有在名單上的觸手
	for tentacle in current_active_tentacles:
		# 確保觸手還存在 (沒被提早刪除) 且有砸下功能
		if is_instance_valid(tentacle) and tentacle.has_method("execute_smash"):
			tentacle.execute_smash()
	
	# 砸完後清空名單，準備下一輪
	current_active_tentacles.clear()

# ==========================================
# 🎯 [戰鬥機制 2] 螺旋彈幕控制 API
# ==========================================
func start_spiral_bullets(is_clockwise: bool) -> void:
	if is_clockwise:
		spawners.start_clockwise()
	else:
		spawners.start_counter_clockwise()

# [共用] 停止彈幕/進入休息
func stop_bullets() -> void:
	print("🛑 [導演指令] 彈幕停止，進入喘息/休息期。")
	spawners.stop_all()

# ==========================================
# [機制3] 高壓雷射死光 (二階專屬)
# ==========================================
func start_laser_sweep(is_clockwise: bool) -> void:
	var dir = "順時針" if is_clockwise else "逆時針"
	print("⚡ [導演指令] 執行【", dir, "】高壓雷射死光！")
	
	# 呼叫雷射武器節點自己寫好的發射功能
	if laser_weapon:
		laser_weapon.fire_laser(is_clockwise)

func stop_laser_sweep() -> void:
	print("🛑 [導演指令] 關閉雷射死光。")
	if laser_weapon:
		laser_weapon.stop_laser()

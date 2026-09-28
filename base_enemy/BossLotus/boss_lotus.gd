extends Node2D

# ==========================================
# 📊 [數值面板] - 可以在 Godot 右側 Inspector 直接調整
# ==========================================
@export_group("Boss 核心數值")
@export var max_hp: int = 500
@export var current_hp: int = 500

# 設定低於多少血量時進入第二階段 (預設 50%，也就是 250)
@export var phase_2_threshold: int = 250 

# 🌟【新增：防抽搐與變形機制】記憶精靈圖最原始的大小與位置，確保動畫能完美彈回原狀
var original_sprite_scale: Vector2 = Vector2.ONE
var original_sprite_pos: Vector2 = Vector2.ZERO
var _hit_tween: Tween # 🌟 專門用來管理受傷動畫，防止連擊時動畫疊加卡死

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
@onready var spawners = $Spawners # 綁定發射器模組
@onready var laser_weapon = $LaserWeapon # 抓取剛做好的雷射部門

# 直接抓取底下的 BossUI 子節點
@onready var boss_ui = $BossUI

@onready var pivot_clockwise = $Spawners/Pivot_Clockwise
@onready var pivot_counter = $Spawners/Pivot_Counter

# ==========================================
# 📦 [備註] 觸手彈藥庫 (在 Inspector 中填入對應的場景)
# ==========================================
@export var tentacle_left_top: PackedScene    
@export var tentacle_left_down: PackedScene   
@export var tentacle_right_top: PackedScene   
@export var tentacle_right_down: PackedScene  

# ==========================================
# 💡 啟動函數
# ==========================================
func _ready() -> void:
	current_hp = max_hp
	
	if sprite:
		sprite.play("idle_down")
		# 🌟【修改】把精靈圖剛載入時的縮放比例與位置存起來
		original_sprite_scale = sprite.scale
		original_sprite_pos = sprite.position
		
	print("🌺 淵獄蓮華正式降臨！進入第一階段。")
	_play_phase_1_timeline()
	
	if boss_ui:
		boss_ui.init_boss("淵獄蓮華", max_hp)
		print("✅ Boss UI 連線成功！上限：", max_hp)

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
		current_hp = phase_2_threshold 
		
		# 直接更新子節點的 UI，確保血條卡在 50%
		if boss_ui:
			boss_ui.update_health(current_hp)
			
		print("🛡️ 觸發硬性血量鎖！目前血量鎖定在：", current_hp)
		
		# 呼叫轉場演出
		_enter_phase_2() 
		return # 攔截掉後續的一般受擊邏輯，直接退出！
		
	# 確保血量不低於 0
	current_hp = clampi(current_hp, 0, max_hp)
	print("💥 淵獄蓮華受傷！剩餘血量：", current_hp)
	
	# 日常受擊：通知專屬 UI 更新
	if boss_ui:
		boss_ui.update_health(current_hp)
	
	# 日常受擊：播放極致打擊感動畫
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
	
	# 補回轉場的那一下重擊感，結束後「自動定格成狂暴的紅色」
	_play_hit_flash_tween()
	
	# 1. 【武器停火】關閉一階的雙螺旋發射器
	spawners.stop_all()
	
	# 2. 【全場清盤 (Board Wipe)】銷毀場上所有殘存的火球
	var old_bullets = get_tree().get_nodes_in_group("boss_bullets")
	for bullet in old_bullets:
		if is_instance_valid(bullet):
			bullet.queue_free() # 瞬間引爆
			
	# 連一階殘留的觸手也全部瞬間銷毀
	for tentacle in current_active_tentacles:
		if is_instance_valid(tentacle):
			tentacle.queue_free()
	current_active_tentacles.clear()
	print("🧹 一階彈幕與觸手清空完畢！")
	
	# 3. 【強制中斷】停止目前正在跑的 Phase1_Loop
	anim_player.stop()
	
	# 4. 【啟動轉場動畫】
	if anim_player.has_animation("Phase_Transition"):
		anim_player.play("Phase_Transition")
	else:
		print("⚠️ 找不到轉場動畫，強制進入二階！")
		finish_transition()

# ==========================================
# 📡 [公開 API] 供 Phase_Transition 動畫在結尾 (第3.0秒) 呼叫
# ==========================================
func finish_transition() -> void:
	print("⚠️ 轉場結束，二階正式開始！解除無敵！")
	is_transitioning = false # 解開無敵鎖
	
	# 🌟【新增：最後一道防線】確保轉場完畢後，一切變形都強制歸位，防禦任何卡圖 Bug
	if sprite:
		sprite.play("idle_down")
		sprite.scale = original_sprite_scale
		sprite.position = original_sprite_pos
	
	if anim_player.has_animation("Phase2_Loop"):
		anim_player.play("Phase2_Loop")
	print("▶️ 啟動 第二階段 時間軸 (雷射狂暴化)")

# ==========================================
# ✨ 3A級受傷視覺反饋 (爆氣放大 + 劇烈震動 + 閃白 + 動態底色)
# ==========================================
func _play_hit_flash_tween() -> void:
	if not sprite: return
	
	# 🌟【新增：防重疊機制】如果上一個動畫還沒播完又被砍，強制斬斷舊動畫，直接重新開始！
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
		# 復原變形與偏移，避免新動畫把錯誤的狀態當成起點
		sprite.scale = original_sprite_scale
		sprite.position = original_sprite_pos
	
	# 1. 播放真實的受傷圖片
	sprite.play("hurt_down")
	
	# 動態底色判定：決定動畫結束後要退回什麼底色
	var target_base_color = Color.WHITE
	if current_phase == 2:
		target_base_color = Color(1.0, 0.3, 0.3) # 二階退回狂暴紅
		
	# 🌟【修改】統一用一條 _hit_tween 來綁定所有的動畫
	_hit_tween = create_tween().set_parallel(true)
	
	# 🎬 A. 【極度閃白】
	sprite.modulate = Color(4.0, 4.0, 4.0, 1.0) 
	_hit_tween.tween_property(sprite, "modulate", target_base_color, 0.2)
	
	# 🎬 B. 【爆氣放大】
	sprite.scale = original_sprite_scale * 1.15
	_hit_tween.tween_property(sprite, "scale", original_sprite_scale, 0.25)\
		 .set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		
	# 🎬 C. 【劇烈無定向震動】(透過 set_delay 塞進平行的 tween 中)
	for i in range(5):
		var random_offset = Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
		_hit_tween.tween_property(sprite, "position", original_sprite_pos + random_offset, 0.02).set_delay(i * 0.02)
	_hit_tween.tween_property(sprite, "position", original_sprite_pos, 0.02).set_delay(0.1) # 抖完歸位

	# 🌟 🎬 D. 【善後切回待機】
	# chain() 會等待前面所有平行動畫播完，再執行這個 callback
	# 移除了「not is_transitioning」這個毒瘤，保證絕對切回待機圖！
	_hit_tween.chain().tween_callback(func():
		if current_hp > 0 and is_instance_valid(sprite):
			sprite.play("idle_down")
	)

# ==========================================
# 💀 正式死亡流程 (斷招、清盤與動畫)
# ==========================================
func _die() -> void:
	print("💀 淵獄蓮華 死亡崩潰中... 啟動全場清盤邏輯！")
	
	anim_player.stop()
	
	if spawners and spawners.has_method("stop_all"):
		spawners.stop_all()
		
	if laser_weapon and laser_weapon.has_method("stop_laser"):
		laser_weapon.stop_laser()

	var old_bullets = get_tree().get_nodes_in_group("boss_bullets")
	for bullet in old_bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()
	print("✨ 殘留彈幕與雷射已強制清除！")

	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if has_node("Hurtbox/CollisionShape2D"):
		$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
		
	if sprite:
		sprite.play("die_down")
	
	var tween = create_tween().set_parallel(false) # 序列執行
	tween.tween_property(sprite, "modulate", Color(0.2, 0.2, 0.2, 1.0), 1.0) 
	tween.tween_property(sprite, "modulate:a", 0.0, 1.5) 
	
	tween.finished.connect(_on_death_animation_finished)

# ==========================================
# 🎉 死亡動畫播完後的處理 (通關結算)
# ==========================================
func _on_death_animation_finished() -> void:
	print("🎉 淵獄蓮華 已徹底消滅！")
	queue_free()

# ==========================================
# 🎯 [機制1] 生成藤蔓路障 (十字象限完美包圍版)
# ==========================================
func trigger_vine_obstacles() -> void:
	if current_phase == 2:
		return 

	if not (tentacle_left_top and tentacle_left_down and tentacle_right_top and tentacle_right_down):
		print("❌ 錯誤：四個角落的觸手場景未填滿！")
		return

	var player = get_tree().get_first_node_in_group("Player")
	var spawn_data = [] 
	
	if player:
		var dx = player.global_position.x - self.global_position.x
		var dy = player.global_position.y - self.global_position.y
		
		if abs(dx) > abs(dy):
			if dx < 0: 
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_left_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_left_down})
			else:      
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_right_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_right_down})
		else:
			if dy < 0: 
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_left_top})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_right_top})
			else:      
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_left_down})
				spawn_data.append({"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_right_down})
	else:
		print("⚠️ 找不到玩家，執行四方全域封鎖！")
		spawn_data = [
			{"pos": $TentacleAnchors/SpawnPoint_LeftTop.global_position, "scene": tentacle_left_top},
			{"pos": $TentacleAnchors/SpawnPoint_LeftDown.global_position, "scene": tentacle_left_down},
			{"pos": $TentacleAnchors/SpawnPoint_RightTop.global_position, "scene": tentacle_right_top},
			{"pos": $TentacleAnchors/SpawnPoint_RightDown.global_position, "scene": tentacle_right_down}
		]

	for data in spawn_data:
		var new_tentacle = data["scene"].instantiate()
		new_tentacle.global_position = data["pos"]
		
		if current_phase == 2:
			new_tentacle.max_hp = 45        
			new_tentacle.current_hp = 45    
			new_tentacle.lifespan = 11.5    
		else:
			new_tentacle.max_hp = 30
			new_tentacle.current_hp = 30
			new_tentacle.lifespan = 11.0
			
		get_parent().add_child(new_tentacle)
		current_active_tentacles.append(new_tentacle)

# ==========================================
# 🎯 [機制1-補充] 命令預警觸手正式砸下
# ==========================================
func smash_vine_obstacles() -> void:
	print("💥 導演指令：全體觸手立刻砸擊！")
	for tentacle in current_active_tentacles:
		if is_instance_valid(tentacle) and tentacle.has_method("execute_smash"):
			tentacle.execute_smash()
	current_active_tentacles.clear()

# ==========================================
# 🎯 [戰鬥機制 2] 螺旋彈幕控制 API
# ==========================================
func start_spiral_bullets(is_clockwise: bool) -> void:
	if current_phase == 2: 
		return 
		
	if is_clockwise:
		spawners.start_clockwise()
	else:
		spawners.start_counter_clockwise()

func stop_bullets() -> void:
	print("🛑 [導演指令] 彈幕停止，進入喘息/休息期。")
	spawners.stop_all()

# ==========================================
# [機制3] 高壓雷射死光 (二階專屬)
# ==========================================
func start_laser_sweep(is_clockwise: bool) -> void:
	var dir = "順時針" if is_clockwise else "逆時針"
	print("⚡ [導演指令] 執行【", dir, "】高壓雷射死光！")
	if laser_weapon:
		laser_weapon.fire_laser(is_clockwise)

func stop_laser_sweep() -> void:
	print("🛑 [導演指令] 關閉雷射死光。")
	if laser_weapon:
		laser_weapon.stop_laser()

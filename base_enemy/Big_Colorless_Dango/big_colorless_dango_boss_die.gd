extends State

# ==========================================
# 💀 Boss 狀態：死亡初見殺 (自爆分裂 / 集束炸彈) - 終極註解版
# ==========================================
# 【類似遊戲思考】：參照手繪圖的「中心引爆，5條拋物線向外炸開」。
# Boss 死亡不該只是消失，而是將體內剩餘的能量，
# 以「高壓拋物線」的方式向外噴射，變成 5 個獨立的威脅，延續戰鬥張力。

@export_category("💀 死亡煙火秀：場景裝填")
@export var explosion_scene: PackedScene     # 裝填：橘紅色死亡核爆 (負責瞬間高傷與清場)
@export var poison_puddle_scene: PackedScene # 裝填：毒沼 (負責死後的永久地形阻礙)
@export var minion_scene: PackedScene        # 裝填：小團子 (負責死後的持續追擊)

@export_category("💀 死亡煙火秀：數值設定")
@export var minion_count: int = 5            # [企劃設定]：炸出 5 隻，完美形成 72 度無死角包圍網
@export var swell_time: float = 1.2          # [遊戲體驗]：死前閃紅光膨脹的恐慌時間，給玩家反應與翻滾的空檔

@export_group("🏀 小怪炸裂：拋物線物理設定")
@export var minion_scatter_radius: float = 250.0  # [空間控制]：拋物線最終落點距離 (飛多遠)
@export var minion_arc_height: float = 200.0      # [視覺控制]：拋物線最高點 (數字越大飛越高)
@export var minion_flight_time: float = 0.8       # [時間控制]：滯空飛行時間

# ==========================================
# 🛑 階段一：死亡劫持 (Death Hijacking)
# ==========================================
func enter():
	# [防呆機制]：煞車歸零。避免 Boss 死掉的瞬間還帶著慣性在地板上滑行。
	character.velocity = Vector2.ZERO
	
	# [系統原理]：開啟無敵保護。避免玩家鞭屍引發重複扣血特效，甚至造成負血量 Bug。
	if "is_invincible" in character:
		character.is_invincible = true
		
	# 【正規作法】：關閉 Boss 肉體碰撞
	# 等一下圖片會膨脹 1.5 倍，如果不關閉實體碰撞箱，巨大的肥肉會把貼臉的玩家直接擠出地圖邊界 (OOB Bug)。
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", true)

	_play_death_telegraph()

# ==========================================
# 🎈 階段二：膨脹與震屏 (Telegraphing)
# ==========================================
func _play_death_telegraph():
	var sprite = character.animated_sprite_2d
	if not sprite: return
	
	# 🎥 [遊戲體驗/Juice]：輕微震屏。這不是爆炸的震動，而是模擬體內能量壓抑不住的臨場感。
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(15.0)
		
	var tween = create_tween()
	
	# [假 3D 物理變形]：身體膨脹 1.5 倍。使用 EXPO (指數型) + EASE_IN (漸入加速) 模擬氣球快撐爆的物理感。
	tween.tween_property(sprite, "scale", Vector2(1.5, 1.5), swell_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# [材質視覺變色]：使用 parallel() 讓變色跟膨脹同時發生，染上危險的深紅色。
	var mat = sprite.material as ShaderMaterial
	if mat:
		tween.parallel().tween_property(mat, "shader_parameter/state_color", Color(1.0, 0.1, 0.1, 1.0), swell_time)
		
	# 1.2 秒膨脹結束後，強制引爆！
	tween.finished.connect(_detonate)

# ==========================================
# 💥 階段三：核爆與拋物線分裂 (The Payload)
# ==========================================
func _detonate():
	# [系統原理]：解耦 (Decoupling)。大胖呆馬上就要被刪除了，
	# 必須把所有生成的武器跟小怪，交給上一層的地圖 (parent) 去當小孩，才不會跟著 Boss 一起陪葬。
	var parent = character.get_parent()
	var spawn_pos = character.global_position
	
	# 1. 生成核爆
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		parent.add_child(explosion)
		explosion.global_position = spawn_pos
		
	# 2. 生成毒沼
	if poison_puddle_scene:
		var puddle = poison_puddle_scene.instantiate()
		parent.add_child(puddle)
		puddle.global_position = spawn_pos
		
	# 3. 🏀 完美拋物線分裂小怪
	if minion_scene:
		for i in range(minion_count):
			var minion = minion_scene.instantiate()
			
			# 【正規作法】：直接 add_child，讓小怪立刻觸發 _ready()，確保後續呼叫動畫不會報錯 (Nil Error)。
			parent.add_child(minion)
			
			# 🌟【防呆機制 1：強制解除隱形】
			# 因為小怪飛行時會拔掉碰撞箱，導致白貓燈光(Area2D)照不到牠。
			# 為了避免牠們變成「空中幽靈」，一出生就強制洗白現形！
			minion.visible = true
			minion.modulate = Color.WHITE
			if "is_illuminated_by_cat" in minion:
				minion.is_illuminated_by_cat = true
			
			minion.global_position = spawn_pos 
			
			# 📐 【數學邏輯：360度均分發射】
			var angle = deg_to_rad(i * (360.0 / minion_count))
			var throw_dir = Vector2.RIGHT.rotated(angle) 
			var target_pos = spawn_pos + (throw_dir * minion_scatter_radius) # 計算最終落點
			
			# 🌟【防呆機制 2：徹底剝奪物理權限 (解決原地跑步 Bug)】
			# 因為小怪的 BaseEnemy 有 _physics_process 在執行 move_and_slide()。
			# 如果不關掉，物理引擎會像「手煞車」一樣死死卡住，導致 Tween 拖不動小怪。
			minion.set_physics_process(false) # 關閉肉體物理引擎
			
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false) # 關閉 AI 大腦，避免半空亂跑
			var m_col = minion.get_node_or_null("CollisionShape2D")
			if m_col: m_col.set_deferred("disabled", true)      # 關閉實體碰撞，避免半空卡牆
			
			# 讓小怪眼睛看著自己飛出去的方向
			if "last_facing_vec" in minion:
				minion.last_facing_vec = throw_dir
				minion.play_animation("move", throw_dir)
			
			# 🎬 【雙軌 Tween 核心：重現完美弧線】
			# 🌟【最關鍵修正：過繼 Tween 撫養權 (解決卡在原地 Bug)】
			# 在 Godot 中，如果你只寫 create_tween()，這個 Tween 會綁定在「呼叫者」(即將死亡的 Boss) 身上。
			# Boss 一死，Tween 就會跟著陪葬被強制中止。
			# 必須寫成 `minion.create_tween()`，將 Tween 的生命週期綁定在小怪身上！
			
			# 軌道 A：底盤影子 (線性滑向落點)
			var move_tween = minion.create_tween()
			move_tween.tween_property(minion, "global_position", target_pos, minion_flight_time).set_trans(Tween.TRANS_LINEAR)
			
			# 軌道 B：肉體圖片 (Y軸上下起伏，畫出假 3D 拋物線)
			var m_sprite = minion.get_node_or_null("AnimatedSprite2D")
			if m_sprite:
				var arc_tween = m_sprite.create_tween() # 同理，綁定在精靈圖身上
				# 上半段 (飛向最高點，Ease Out 阻力減速)
				arc_tween.tween_property(m_sprite, "position:y", -minion_arc_height, minion_flight_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				# 下半段 (重力墜落砸地，Ease In 重力加速)
				arc_tween.tween_property(m_sprite, "position:y", 0.0, minion_flight_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				
			# ⚡ 【落地甦醒 (On Landing)】
			# 當平面滑行 (move_tween) 結束，代表精準降落。
			move_tween.finished.connect(func():
				if is_instance_valid(minion): 
					if m_col: m_col.set_deferred("disabled", false) # 1. 恢復實體碰撞箱
					
					# 🌟 2. 歸還物理權限！重新發動引擎，小怪又能 move_and_slide 了。
					minion.set_physics_process(true)
					
					if "state_machine" in minion and minion.state_machine:
						minion.state_machine.set_physics_process(true) # 3. 插回 AI 大腦，開始追殺！
			)
	
	# ==========================================
	# 👻 階段四：垃圾回收 (Garbage Collection)
	# ==========================================
	# 所有的死亡機關都已經順利交付給地圖。
	# 因為上方的 Tween 已經成功過繼給小怪了，大胖呆本體現在可以安心地從記憶體中抹除。
	character.queue_free()

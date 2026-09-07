extends State

# ==========================================
# 💀 Boss 狀態：死亡初見殺 (自爆賴皮豬) - 完美拋物線與極致註解版
# ==========================================
# 【類似遊戲思考】：死亡是 Boss 戰的最後高潮。
# 我們要利用玩家「打贏瞬間會鬆懈」的心理，用膨脹預警製造恐慌，
# 再用核爆、毒沼、滿天飛的小怪，進行最後的無差別攻擊。

@export_category("💀 死亡煙火秀：場景裝填")
@export var explosion_scene: PackedScene     # 裝填：橘紅色死亡核爆 (負責瞬間毀滅性範圍傷害)
@export var poison_puddle_scene: PackedScene # 裝填：毒沼 (負責死後的永久地形壓制)
@export var minion_scene: PackedScene        # 裝填：小團子 (負責死後的持續追擊)

@export_category("💀 死亡煙火秀：數值設定")
@export var minion_count: int = 5            # [企劃調整]：炸出幾隻小怪？(5隻能形成 72 度無死角包圍網)
@export var swell_time: float = 1.2          # [遊戲體驗]：膨脹發呆時間。1.2秒是給玩家意識到「不對勁」並翻滾的最佳反應期。

@export_group("🏀 小怪炸裂：拋物線物理設定")
@export var minion_scatter_radius: float = 250.0  # [空間控制]：小怪最終的落地點距離中心有多遠。
@export var minion_arc_height: float = 200.0      # [視覺控制]：拋物線最高點 (數字越大，飛得越高)。
@export var minion_flight_time: float = 0.8       # [時間控制]：滯空時間。配合高度，決定這場「天女散花」的節奏。

# ==========================================
# 🛑 階段一：死亡劫持 (Death Hijacking)
# ==========================================
func enter():
	print("💀 大胖呆進入死亡劫持狀態！開始膨脹...")
	
	# [防呆機制]：Boss 死亡瞬間可能正在滑行，必須歸零，否則牠會一邊膨脹一邊在地板上滑，非常出戲。
	character.velocity = Vector2.ZERO
	
	# [系統原理]：如果不開啟無敵，玩家繼續砍正在膨脹的 Boss，可能會重複觸發扣血特效，甚至導致負血量 Bug。
	if "is_invincible" in character:
		character.is_invincible = true
		
	# 關閉物理碰撞 (極度關鍵！)
	# [防呆機制]：等一下圖片會膨脹 1.5 倍。如果不關閉實體碰撞箱 (CollisionShape2D)，
	# Boss 膨脹的肥肉會把站在旁邊的玩家強行推開，甚至把玩家擠出地圖邊界 (OOB 穿牆 Bug)。
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", true)

	# 準備完畢，進入預警演出
	_play_death_telegraph()

# ==========================================
# 🎈 階段二：膨脹與震屏警告 (Telegraphing)
# ==========================================
func _play_death_telegraph():
	var sprite = character.animated_sprite_2d
	if not sprite: return
	
	# 🎥 [遊戲體驗/Juice]：輕微震屏。這不是爆炸的震動，而是模擬體內能量快要壓抑不住的臨場感。
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(15.0)
		
	var tween = create_tween()
	
	# 🎈 [假 3D 物理變形]：身體逐漸膨脹到 1.5 倍。
	# TRANS_EXPO (指數型) + EASE_IN (漸入加速)：這會讓動畫「一開始慢慢膨脹，最後一瞬間突然撐爆」，最符合氣球爆炸的物理法則。
	tween.tween_property(sprite, "scale", Vector2(1.5, 1.5), swell_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# 🩸 [材質視覺變色]：使用 parallel() 讓這個變色動畫跟上面的膨脹「同時進行」。
	# 將 Shader 顏色逐漸染成深紅色，給玩家強烈的危險信號。
	var mat = sprite.material as ShaderMaterial
	if mat:
		tween.parallel().tween_property(mat, "shader_parameter/state_color", Color(1.0, 0.1, 0.1, 1.0), swell_time)
		
	# ⏳ [信號串接]：Tween 動畫跑完的那一瞬間 (1.2秒後)，觸發真實的爆炸！
	tween.finished.connect(_detonate)

# ==========================================
# 💥 階段三：機制大禮包與完美拋物線小怪
# ==========================================
func _detonate():
	print("💥 膨脹完畢，引發死亡核爆！")
	
	# [系統原理]：解耦 (Decoupling)。大胖呆等一下就要自我刪除了。
	# 如果生成的爆炸和小怪掛在大胖呆底下，會跟著大胖呆一起被系統抹除。
	# 所以我們必須把這些生成的物件，丟給上一層的「地圖 (parent)」去當小孩。
	var parent = character.get_parent()
	var spawn_pos = character.global_position
	
	# 1. 💣 生成核爆武器 (負責高傷與清場)
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		parent.add_child(explosion)
		explosion.global_position = spawn_pos
		
	# 2. 🤢 生成永久毒沼 (負責阻礙地形)
	if poison_puddle_scene:
		var puddle = poison_puddle_scene.instantiate()
		parent.add_child(puddle)
		puddle.global_position = spawn_pos
		
	# 3. 🏀 完美拋物線生成滿天星小怪 (負責死後追擊)
	if minion_scene:
		for i in range(minion_count):
			var minion = minion_scene.instantiate()
			parent.add_child(minion)
			minion.global_position = spawn_pos 
			
			# 📐 [數學邏輯：完美圓形分佈]
			# i * (360 / 5) = 分別算出 0度, 72度, 144度, 216度, 288度
			var angle = deg_to_rad(i * (360.0 / minion_count))
			var throw_dir = Vector2.RIGHT.rotated(angle) # 將角度轉為 XY 向量
			
			# 最終落地點 = 爆炸中心點 + (方向向量 * 企劃設定的射程)
			var target_pos = spawn_pos + (throw_dir * minion_scatter_radius) 
			
			# 🧠 [防呆機制：剝奪行動與物理能力]
			# 小怪在天上飛的時候，絕對不能自己亂走路，也不能撞到地圖的牆壁！
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false) # 關閉大腦 (AI)
			var m_col = minion.get_node_or_null("CollisionShape2D")
			if m_col: m_col.set_deferred("disabled", true)      # 關閉肉體碰撞箱
			
			# 改變小怪的面向，讓牠看著自己飛出去的方向
			if "last_facing_vec" in minion:
				minion.last_facing_vec = throw_dir
				minion.play_animation("move", throw_dir)
			
			# 🎬 [視覺核心：雙軌 Tween 拋物線 (Dual-Track Tween)]
			# 為什麼不用 velocity？因為 velocity 只能在平地滑。我們要創造「飛躍空中」的錯覺。
			
			# 【軌道 A：平面滑行】讓小怪的根節點，筆直地滑向落地點。TRANS_LINEAR 代表等速前進。
			var move_tween = create_tween()
			move_tween.tween_property(minion, "global_position", target_pos, minion_flight_time).set_trans(Tween.TRANS_LINEAR)
			
			# 【軌道 B：垂直起伏】只針對圖片 (Sprite) 做 Y 軸的位移，這就是俯視角假 3D 的精髓！
			var m_sprite = minion.get_node_or_null("AnimatedSprite2D")
			if m_sprite:
				var arc_tween = create_tween()
				# 上半段 (起飛)：從地板往上飛到負數高度。用 EASE_OUT (阻力減速) 模擬重力把你拉住。
				arc_tween.tween_property(m_sprite, "position:y", -minion_arc_height, minion_flight_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				# 下半段 (墜落)：從空中砸回地板 (0.0)。用 EASE_IN (重力加速) 模擬越掉越快。
				arc_tween.tween_property(m_sprite, "position:y", 0.0, minion_flight_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				
			# ⚡ [信號串接：落地瞬間甦醒]
			# 當【軌道 A】跑完，代表小怪精準降落在目標點了。此時解除所有封印！
			move_tween.finished.connect(func():
				if is_instance_valid(minion): # 確保小怪在飛行途中沒有因為意外被刪除
					if m_col: m_col.set_deferred("disabled", false)     # 1. 恢復物理碰撞
					if "state_machine" in minion and minion.state_machine:
						minion.state_machine.set_physics_process(true)  # 2. 插回大腦，5 隻小怪同時開始追殺玩家！
			)
	
	# ==========================================
	# 👻 階段四：垃圾回收 (Garbage Collection)
	# ==========================================
	# 所有的惡意大禮包都已經安全地交給地圖 (parent) 去生成並管理了。
	# 大胖呆的任務徹底結束，此時才呼叫 queue_free() 讓自己從世界上抹除，釋放記憶體。
	character.queue_free()

extends State

# ==========================================
# 💀 Boss 狀態：死亡初見殺 (自爆分裂 / 集束炸彈) - 終極註解版
# ==========================================

@export_category("💀 死亡煙火秀：場景裝填")
@export var explosion_scene: PackedScene     # 裝填：橘紅色死亡核爆 (負責瞬間高傷與清場)
@export var poison_puddle_scene: PackedScene # 裝填：毒沼 (負責死後的永久地形阻礙)
@export var minion_scene: PackedScene        # 裝填：小團子 (負責死後的持續追擊)
@export var drop_box_scene: PackedScene      # 🌟 新增裝填：死亡爆出的任務貨物箱 (拖入 medium_box.tscn)

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
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", true)

	_play_death_telegraph()

# ==========================================
# 🎈 階段二：膨脹與震屏 (Telegraphing)
# ==========================================
func _play_death_telegraph():
	var sprite = character.animated_sprite_2d
	if not sprite: return
	
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(15.0)
	
	character.play_animation("bomb")
	
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.5, 1.5), swell_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	var mat = sprite.material as ShaderMaterial
	if mat:
		tween.parallel().tween_property(mat, "shader_parameter/state_color", Color(1.0, 0.1, 0.1, 1.0), swell_time)
		
	# 1.2 秒膨脹結束後，強制引爆！
	tween.finished.connect(_detonate)

# ==========================================
# 💥 階段三：核爆與拋物線分裂 (The Payload)
# ==========================================
func _detonate():
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
		
	# 🌟 2.5 生成任務貨物箱 (medium_box) 並演出「炸飛高空彈跳落地」！
	if drop_box_scene:
		var already_picked = DataManager.has_method("is_cutscene_completed") and DataManager.is_cutscene_completed("A014D")
		if not already_picked:
			var box = drop_box_scene.instantiate() as Node2D
			parent.add_child(box)
			box.global_position = spawn_pos
			
			# 飛行期間暫時關閉互動感應，落地停穩後才開放按 E
			if box is Area2D:
				box.monitoring = false
				
			box.scale = Vector2(0.3, 0.3)
			var box_tween = box.create_tween()
			# 先放大回正常尺寸，同時往高處拋起 90 像素，再以 BOUNCE 曲線彈跳落地！
			box_tween.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			box_tween.parallel().tween_property(box, "global_position:y", spawn_pos.y - 90.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			box_tween.tween_property(box, "global_position:y", spawn_pos.y, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			box_tween.tween_callback(func():
				if is_instance_valid(box) and box is Area2D:
					box.monitoring = true
			)
		
	# 3. 🏀 完美拋物線分裂小怪
	if minion_scene:
		for i in range(minion_count):
			var minion = minion_scene.instantiate()
			parent.add_child(minion)
			
			minion.visible = true
			minion.modulate = Color.WHITE
			if "is_illuminated_by_cat" in minion:
				minion.is_illuminated_by_cat = true
			
			minion.global_position = spawn_pos 
			
			var angle = deg_to_rad(i * (360.0 / minion_count))
			var throw_dir = Vector2.RIGHT.rotated(angle) 
			var target_pos = spawn_pos + (throw_dir * minion_scatter_radius)
			
			minion.set_physics_process(false)
			
			if "state_machine" in minion and minion.state_machine:
				minion.state_machine.set_physics_process(false)
			var m_col = minion.get_node_or_null("CollisionShape2D")
			if m_col: m_col.set_deferred("disabled", true)
			
			if "last_facing_vec" in minion:
				minion.last_facing_vec = throw_dir
				minion.play_animation("move", throw_dir)
			
			var move_tween = minion.create_tween()
			move_tween.tween_property(minion, "global_position", target_pos, minion_flight_time).set_trans(Tween.TRANS_LINEAR)
			
			var m_sprite = minion.get_node_or_null("AnimatedSprite2D")
			if m_sprite:
				var arc_tween = m_sprite.create_tween()
				arc_tween.tween_property(m_sprite, "position:y", -minion_arc_height, minion_flight_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				arc_tween.tween_property(m_sprite, "position:y", 0.0, minion_flight_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				
			move_tween.finished.connect(func():
				if is_instance_valid(minion): 
					if m_col: m_col.set_deferred("disabled", false)
					minion.set_physics_process(true)
					if "state_machine" in minion and minion.state_machine:
						minion.state_machine.set_physics_process(true)
			)
	
	# ==========================================
	# 👻 階段四：等待碎裂尾幀與垃圾回收 (Garbage Collection)
	# ==========================================
	var sprite = character.animated_sprite_2d
	if sprite and sprite.is_playing():
		var mat = sprite.material as ShaderMaterial
		if mat: mat.set_shader_parameter("state_color", Color.WHITE)
		await sprite.animation_finished
		
	character.queue_free()

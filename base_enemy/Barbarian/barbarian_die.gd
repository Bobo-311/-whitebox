
extends State

# =====================================================
# 野蠻人專屬死亡狀態
# 保留原本死亡擊退、灰階屍體、溶解與淡出
# =====================================================

@export_group("倒地演出")
@export var corpse_start_frame: int = 3     # 倒地後開始變灰的影格索引
@export var death_push_distance: float = 60.0 # 死亡時向後推移的距離
@export var death_camera_shake: float = 100.0 # 死亡鏡頭震動

@export_group("屍體效果")
@export var corpse_tint_time: float = 0.18  # 屍體灰階轉換時間
@export var corpse_hold_time: float = 5.0   # 屍體停留時間
@export var corpse_fade_time: float = 1.5   # 屍體溶解與淡出時間

@export_range(0.0, 1.0, 0.05)
var corpse_alpha: float = 0.55              # 屍體變灰後的透明度

var enemy: Barbarian
var sprite: AnimatedSprite2D

var _death_animation: StringName
var _landing_frame: int = 0
var _death_animation_valid: bool = false
var _corpse_effect_started: bool = false

# =====================================================
# 進入死亡狀態
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	if not enemy:
		return

	sprite = enemy.animated_sprite_2d
	enemy.velocity = Vector2.ZERO
	enemy.can_attack = false
	enemy.end_sword_attack()
	enemy.set_contact_enabled(false)

	_corpse_effect_started = false
	_death_animation_valid = false

	# 取得最後面向，用於播放正確方向的死亡動畫
	var anim_dir: Vector2 = enemy.last_facing_vec
	var push_dir: Vector2 = -anim_dir.normalized()

	# 優先往遠離玩家的方向擊退
	if DataManager and is_instance_valid(DataManager.player_node):
		push_dir = (
			enemy.global_position - DataManager.player_node.global_position
		).normalized()

	if push_dir == Vector2.ZERO:
		push_dir = Vector2.LEFT

	# 延後執行物理位移，避免在碰撞訊號處理期間直接修改物理狀態
	enemy.call_deferred("move_and_collide", push_dir * death_push_distance)

	# 播放對應方向的二階死亡動畫
	_death_animation = enemy.get_action_animation("die", anim_dir)
	_death_animation_valid = enemy.play_action("die", anim_dir, true)

	if _death_animation_valid:
		var frame_count: int = sprite.sprite_frames.get_frame_count(_death_animation)
		if frame_count > 0:
			_landing_frame = clampi(corpse_start_frame, 0, frame_count - 1)
		else:
			_death_animation_valid = false

	# 死亡後統一關閉全部實體與傷害碰撞
	_disable_all_collisions()

	# 保留玩家護符的擊殺回血等效果
	if DataManager and is_instance_valid(DataManager.player_node):
		if DataManager.player_node.has_method("on_enemy_killed"):
			DataManager.player_node.on_enemy_killed()

	var camera = enemy.get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(death_camera_shake)

	# 如果死亡素材尚未匯入，不等待不存在的動畫
	if not _death_animation_valid:
		sprite.pause()
		_start_corpse_effect()

# =====================================================
# 關閉全部碰撞
# 避免死亡後的屍體阻擋玩家或繼續造成傷害
# =====================================================
func _disable_all_collisions() -> void:
	var root_shape = enemy.get_node_or_null("CollisionShape2D")
	if root_shape:
		root_shape.set_deferred("disabled", true)

	var area_paths: Array[String] = [
		"Hitbox",
		"BodyHitbox",
		"Hurtbox",
		"DetectPlayer"
	]

	for path in area_paths:
		var area = enemy.get_node_or_null(path)
		if area is Area2D:
			area.set_deferred("monitoring", false)
			area.set_deferred("monitorable", false)

			for child in area.get_children():
				if child is CollisionShape2D or child is CollisionPolygon2D:
					child.set_deferred("disabled", true)

# =====================================================
# 等待死亡動畫到達真正倒地的影格
# =====================================================
func state_physics_update(_delta: float) -> void:
	if _corpse_effect_started or not is_instance_valid(sprite):
		return

	# 如動畫意外中斷，也不讓屍體流程永久卡住
	if sprite.animation != _death_animation:
		_start_corpse_effect()
		return

	if sprite.frame >= _landing_frame or not sprite.is_playing():
		# 若不小心將死亡動畫設定成 Loop，直接停在倒地畫面
		if sprite.sprite_frames.get_animation_loop(_death_animation):
			sprite.pause()
		_start_corpse_effect()

# =====================================================
# 屍體變灰、停留、溶解
# 使用單一 Tween 統整死亡演出
# =====================================================
func _start_corpse_effect() -> void:
	if _corpse_effect_started:
		return

	_corpse_effect_started = true

	if not is_instance_valid(sprite):
		enemy.queue_free()
		return

	var corpse_material: ShaderMaterial = null

	# 複製 ShaderMaterial，不影響其他敵人個體
	if sprite.material is ShaderMaterial:
		corpse_material = sprite.material.duplicate() as ShaderMaterial
		sprite.material = corpse_material
		corpse_material.set_shader_parameter("grayscale_modifier", 0.0)
		corpse_material.set_shader_parameter("dissolve_progress", 0.0)
		corpse_material.set_shader_parameter("flash_modifier", 0.0)

	var tween: Tween = enemy.create_tween()

	# 第一段：屍體逐漸變灰
	if corpse_material:
		tween.tween_property(
			corpse_material,
			"shader_parameter/grayscale_modifier",
			1.0,
			corpse_tint_time
		)
		tween.parallel().tween_property(sprite, "modulate:a", corpse_alpha, corpse_tint_time)
	else:
		# 未使用屍體 Shader 時，使用普通暗灰色淡出作為備用效果
		tween.tween_property(
			sprite,
			"modulate",
			Color(0.6, 0.6, 0.6, corpse_alpha),
			corpse_tint_time
		)

	# 第二段：屍體停留
	tween.tween_interval(maxf(corpse_hold_time, 0.0))

	# 第三段：淡出並溶解
	tween.tween_property(
		sprite,
		"modulate:a",
		0.0,
		corpse_fade_time
	).set_trans(Tween.TRANS_SINE)

	if corpse_material:
		tween.parallel().tween_property(
			corpse_material,
			"shader_parameter/dissolve_progress",
			1.0,
			corpse_fade_time
		)

	# 死亡演出完整結束後才釋放角色
	tween.tween_callback(enemy.queue_free)

extends State

# ============================================================
# 【死亡擊退設定】
# ============================================================

@export_group("死亡擊退設定")

# 最長死亡擊退距離。
# 遇到牆壁時會由物理碰撞自動縮短。
@export var death_push_distance: float = 60.0

@export var death_camera_shake: float = 100.0


# ============================================================
# 【屍體演出設定】
# ============================================================

@export_group("屍體演出設定")

# 從第 0 格開始計算，3 代表第四張圖片。
@export var corpse_start_frame: int = 3

# 屍體轉灰所需時間。
@export var corpse_tint_time: float = 0.18

# 屍體保留時間。
@export var corpse_hold_time: float = 5.0

# 淡出與溶解時間。
@export var corpse_fade_time: float = 1.5

# 屍體最終透明度。
@export_range(0.0, 1.0, 0.01)
var corpse_alpha: float = 0.55


# ============================================================
# 【進入死亡狀態】
# ============================================================

func enter() -> void:

	# --------------------------------------------------------
	# 1. 清除敵人所有殘留移動力量
	# --------------------------------------------------------

	character.velocity = Vector2.ZERO

	var knockback = character.get_node_or_null(
		"KnockbackComponent"
	) as KnockbackComponent

	if knockback:
		knockback.lock_knockback()

	# --------------------------------------------------------
	# 2. 記錄敵人最後的面向
	# --------------------------------------------------------

	var anim_dir: Vector2 = character.last_facing_vec

	# --------------------------------------------------------
	# 3. 執行安全死亡擊退
	# 此時本體碰撞仍然維持啟用。
	# --------------------------------------------------------

	_apply_safe_death_push(anim_dir)

	# --------------------------------------------------------
	# 4. 播放死亡動畫
	# --------------------------------------------------------

	character.play_animation("die", anim_dir)

	# --------------------------------------------------------
	# 5. 位移完成後才關閉碰撞
	# --------------------------------------------------------

	_disable_death_collisions()

	# --------------------------------------------------------
	# 6. 通知玩家擊殺事件
	# --------------------------------------------------------

	if is_instance_valid(DataManager.player_node):

		if DataManager.player_node.has_method(
			"on_enemy_killed"
		):
			DataManager.player_node.on_enemy_killed()

	# --------------------------------------------------------
	# 7. 播放死亡鏡頭震動
	# --------------------------------------------------------

	var camera = character.get_tree().get_first_node_in_group(
		"camera"
	)

	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(death_camera_shake)

	# --------------------------------------------------------
	# 8. 執行屍體演出及清理
	# --------------------------------------------------------

	await _start_despawn()


# ============================================================
# 【安全死亡擊退】
# ============================================================

func _apply_safe_death_push(anim_dir: Vector2) -> void:

	if death_push_distance <= 0.0:
		return

	# 取得本體碰撞箱。
	var body_collision = character.get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D

	# 防呆：
	# 如果本體碰撞已被提前關閉，就不再執行死亡位移。
	if body_collision == null:
		return

	if body_collision.disabled or body_collision.shape == null:
		return

	if character.collision_mask == 0:
		return

	# 計算遠離玩家的死亡擊退方向。
	var push_dir: Vector2 = Vector2.ZERO

	if is_instance_valid(DataManager.player_node):

		push_dir = (
			character.global_position
			- DataManager.player_node.global_position
		).normalized()

	# 玩家不存在時，使用最後面向的反方向。
	if push_dir == Vector2.ZERO:
		push_dir = -anim_dir.normalized()

	if push_dir == Vector2.ZERO:
		push_dir = Vector2.LEFT

	# 使用物理位移，而不是直接修改 global_position。
	# 撞到牆壁會自動停止，不強迫完成整段距離。
	character.move_and_collide(
		push_dir * death_push_distance
	)

	# 位移完成後再次清空速度。
	character.velocity = Vector2.ZERO


# ============================================================
# 【關閉死亡碰撞】
# ============================================================

func _disable_death_collisions() -> void:

	# 本體碰撞。
	var body_collision = character.get_node_or_null(
		"CollisionShape2D"
	)

	if body_collision:
		body_collision.set_deferred("disabled", true)

	# 攻擊區域。
	_disable_area("Hitbox")

	# 受傷區域。
	_disable_area("Hurtbox")

	# 停止所有實體碰撞通道。
	character.set_deferred("collision_layer", 0)
	character.set_deferred("collision_mask", 0)

	character.velocity = Vector2.ZERO


# ============================================================
# 【關閉指定 Area2D】
# ============================================================

func _disable_area(node_path: String) -> void:

	var area = character.get_node_or_null(
		node_path
	) as Area2D

	if area == null:
		return

	area.set_deferred("monitoring", false)
	area.set_deferred("monitorable", false)

	area.set_deferred("collision_layer", 0)
	area.set_deferred("collision_mask", 0)

	var collision = area.get_node_or_null(
		"CollisionShape2D"
	)

	if collision:
		collision.set_deferred("disabled", true)


# ============================================================
# 【等待死亡動畫倒地影格】
# ============================================================

func _wait_for_landing_frame() -> void:

	var sprite = character.get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if sprite == null or sprite.sprite_frames == null:
		return

	# ★ 支援所有方向的死亡動畫。
	# die、die_left、die_right_up 等名稱皆可使用。
	var death_animation: StringName = sprite.animation

	if not String(death_animation).begins_with("die"):
		return

	var frame_count: int = sprite.sprite_frames.get_frame_count(
		death_animation
	)

	if frame_count <= 0:
		return

	var landing_frame: int = clampi(
		corpse_start_frame,
		0,
		frame_count - 1
	)

	# 等待指定倒地影格。
	while is_instance_valid(sprite):

		if sprite.animation != death_animation:
			break

		if sprite.frame >= landing_frame:
			break

		if not sprite.is_playing():
			break

		# 使用 process_frame 避免動畫停止後，
		# 永遠卡在等待 frame_changed 的狀態。
		await get_tree().process_frame


# ============================================================
# 【屍體消失流程】
# ============================================================

func _start_despawn() -> void:

	# 1. 等待死亡動畫倒地。
	await _wait_for_landing_frame()

	if not is_instance_valid(character):
		return

	# 2. 播放灰階轉換。
	var corpse_material: ShaderMaterial = \
		await _apply_corpse_appearance()

	if not is_instance_valid(character):
		return

	# 3. 保留屍體。
	await character.get_tree().create_timer(
		corpse_hold_time
	).timeout

	if not is_instance_valid(character):
		return

	var sprite = character.get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if sprite == null:
		character.queue_free()
		return

	# 4. 建立淡出 Tween。
	var fade_tween = character.create_tween()

	fade_tween.set_trans(Tween.TRANS_SINE)
	fade_tween.set_ease(Tween.EASE_IN_OUT)

	# 5. 屍體逐漸透明。
	fade_tween.tween_property(
		sprite,
		"modulate:a",
		0.0,
		corpse_fade_time
	)

	# 6. 同時執行 Shader 溶解。
	if is_instance_valid(corpse_material):

		fade_tween.parallel().tween_property(
			corpse_material,
			"shader_parameter/dissolve_progress",
			1.0,
			corpse_fade_time
		).set_trans(Tween.TRANS_LINEAR)

	await fade_tween.finished

	# 7. 清除敵人節點。
	if is_instance_valid(character):
		character.queue_free()


# ============================================================
# 【屍體灰階效果】
# ============================================================

func _apply_corpse_appearance() -> ShaderMaterial:

	var sprite = character.get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if sprite == null:
		return null

	var original_material = sprite.material as ShaderMaterial

	if original_material == null:
		return null

	# 複製材質，避免影響其他尚未死亡的敵人。
	var corpse_material = original_material.duplicate() \
		as ShaderMaterial

	sprite.material = corpse_material

	# 初始化 Shader。
	corpse_material.set_shader_parameter(
		"grayscale_modifier",
		0.0
	)

	corpse_material.set_shader_parameter(
		"dissolve_progress",
		0.0
	)

	corpse_material.set_shader_parameter(
		"flash_modifier",
		0.0
	)

	# 建立灰階過渡。
	var tint_tween = character.create_tween()

	tint_tween.set_trans(Tween.TRANS_SINE)
	tint_tween.set_ease(Tween.EASE_OUT)

	tint_tween.tween_property(
		corpse_material,
		"shader_parameter/grayscale_modifier",
		1.0,
		corpse_tint_time
	)

	tint_tween.parallel().tween_property(
		sprite,
		"modulate:a",
		corpse_alpha,
		corpse_tint_time
	)

	await tint_tween.finished

	return corpse_material

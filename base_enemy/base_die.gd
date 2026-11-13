extends State
# ============================================================
# 【死亡效果設定】
# 可以依照遊戲實際視覺效果調整這些數值
# ============================================================
const CORPSE_START_FRAME: int = 3
# 屍體開始變灰的影格。
# 注意：這裡使用從 0 開始的索引。
# 例如 0、1、2、3，代表第四張圖片開始變灰。
# 請依照你的 die 動畫，調整成真正碰到地面的那一格。
const CORPSE_TINT_TIME: float = 0.18
# 屍體從正常顏色轉變成灰色所需時間。
# 數值越小，變灰速度越快。
const CORPSE_HOLD_TIME: float = 5.0
# 灰色屍體在場上保留的時間。
const CORPSE_FADE_TIME: float = 1.5
# 屍體最後淡出與溶解所需時間。
const CORPSE_ALPHA: float = 0.55
# 屍體變灰後的透明度。
# 1.0 = 完全不透明
# 0.55 = 半透明
# 0.0 = 完全透明
const DEATH_PUSH_DISTANCE: float = 60.0
# 敵人死亡時往後退的距離。
const DEATH_CAMERA_SHAKE: float = 100.0
# 敵人死亡時的鏡頭震動強度。

# ============================================================
# 【進入死亡狀態】
# 敵人死亡時由 StateMachine 呼叫
# ============================================================
func enter() -> void:
	# --------------------------------------------------------
	# 1. 停止敵人目前的移動
	# --------------------------------------------------------
	character.velocity = Vector2.ZERO
	# --------------------------------------------------------
	# 2. 取得敵人最後面向的方向
	# 用來決定死亡動畫的方向
	# --------------------------------------------------------
	var anim_dir: Vector2 = character.last_facing_vec
	# --------------------------------------------------------
	# 3. 計算敵人死亡時的擊退方向
	# 讓敵人朝遠離玩家的方向退開
	# --------------------------------------------------------
	var push_dir: Vector2 = Vector2.ZERO
	if is_instance_valid(DataManager.player_node):
		push_dir = (
			character.global_position
			- DataManager.player_node.global_position
		).normalized()
	# 如果無法取得玩家位置，就使用敵人最後面向的反方向
	if push_dir == Vector2.ZERO:
		push_dir = -anim_dir.normalized()
	# 如果方向仍然無效，使用預設方向
	if push_dir == Vector2.ZERO:
		push_dir = Vector2.LEFT
	# --------------------------------------------------------
	# 4. 執行死亡擊退
	# --------------------------------------------------------

	character.move_and_collide(
		push_dir * DEATH_PUSH_DISTANCE
	)

	# --------------------------------------------------------
	# 5. 播放死亡動畫
	# --------------------------------------------------------

	character.play_animation("die", anim_dir)
	# --------------------------------------------------------
	# 6. 關閉敵人的主要碰撞
	# 避免死亡後仍然阻擋玩家移動
	# --------------------------------------------------------
	var body_collision = character.get_node_or_null(
        "CollisionShape2D"
	)
	if body_collision:
		body_collision.set_deferred("disabled", true)
	# --------------------------------------------------------
	# 7. 關閉敵人的攻擊碰撞
	# 避免死亡後還能繼續攻擊玩家
	# --------------------------------------------------------
	var hitbox_collision = character.get_node_or_null(
        "Hitbox/CollisionShape2D"
	)
	if hitbox_collision:
		hitbox_collision.set_deferred("disabled", true)
	# --------------------------------------------------------
	# 8. 關閉敵人的受傷碰撞
	# 避免死亡後仍然接收玩家攻擊
	# --------------------------------------------------------
	var hurtbox_collision = character.get_node_or_null(
        "Hurtbox/CollisionShape2D"
	)
	if hurtbox_collision:
		hurtbox_collision.set_deferred("disabled", true)

	# --------------------------------------------------------
	# 9. 呼叫玩家的擊殺事件
	# 如果 DataManager.player_node 有 on_enemy_killed()
	# 就通知玩家敵人已經死亡
	# --------------------------------------------------------

	if is_instance_valid(DataManager.player_node):
		if DataManager.player_node.has_method("on_enemy_killed"):
			DataManager.player_node.on_enemy_killed()
	# --------------------------------------------------------
	# 10. 取得鏡頭並播放震動
	# --------------------------------------------------------
	var camera = character.get_tree().get_first_node_in_group(
        "camera"
	)
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(DEATH_CAMERA_SHAKE)
	# --------------------------------------------------------
	# 11. 開始屍體處理流程
	# 使用 await 讓死亡流程依照順序執行
	# --------------------------------------------------------
	await _start_despawn()


# ============================================================
# 【屍體消失流程】
# 負責等待倒地影格、變灰、停留、淡出及溶解
# ============================================================

func _start_despawn() -> void:
	# --------------------------------------------------------
	# 1. 取得敵人的 AnimatedSprite2D
	# --------------------------------------------------------
	var sprite = character.get_node_or_null(
        "AnimatedSprite2D"
	) as AnimatedSprite2D
	# --------------------------------------------------------
	# 2. 等待死亡動畫到達指定倒地影格
	#
	# 不使用 animation_finished：
	# 因為 animation_finished 代表整個動畫結束，
	# 不代表敵人剛好倒在地上的時間點。
	# --------------------------------------------------------
	if sprite and sprite.sprite_frames:
		# 確認目前播放的是死亡動畫
		if sprite.animation == "die":
			# 取得死亡動畫總影格數
			var frame_count: int = sprite.sprite_frames.get_frame_count(
                "die"
			)
			# 確認死亡動畫至少有一張圖片
			if frame_count > 0:
				# 防止設定的影格超出動畫範圍
				var landing_frame: int = clampi(
					CORPSE_START_FRAME,
					0,
					frame_count - 1
				)
				# ------------------------------------------------
				# 持續等待，直到動畫到達倒地影格
				# ------------------------------------------------
				while is_instance_valid(sprite):
					# 如果動畫被切換，就停止等待
					if sprite.animation != "die":
						break
					# 到達倒地影格後，立即開始屍體變色
					if sprite.frame >= landing_frame:
						break
					# 等待下一次影格改變
					await sprite.frame_changed
	# --------------------------------------------------------
	# 3. 確認敵人節點還存在
	# --------------------------------------------------------
	if not is_instance_valid(character):
		return
	# --------------------------------------------------------
	# 4. 開始屍體變灰效果
	# 等待變色 Tween 完成後才繼續
	# --------------------------------------------------------
	var corpse_material: ShaderMaterial = await _apply_corpse_appearance()
	# --------------------------------------------------------
	# 5. 等待屍體保留時間
	# --------------------------------------------------------
	await character.get_tree().create_timer(
		CORPSE_HOLD_TIME
	).timeout
	# 再次確認敵人是否仍然存在
	if not is_instance_valid(character):
		return
	# --------------------------------------------------------
	# 6. 重新取得 Sprite
	# --------------------------------------------------------
	sprite = character.get_node_or_null(
        "AnimatedSprite2D"
	) as AnimatedSprite2D
	# 如果 Sprite 已經不存在，直接釋放敵人
	if sprite == null:
		character.queue_free()
		return
	# --------------------------------------------------------
	# 7. 建立最後的淡出 Tween
	# --------------------------------------------------------
	var fade_tween = character.create_tween()
	# 使用平滑的淡出曲線
	fade_tween.set_trans(Tween.TRANS_SINE)
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	# --------------------------------------------------------
	# 8. 讓屍體逐漸透明
	# --------------------------------------------------------
	fade_tween.tween_property(
		sprite,
		"modulate:a",
		0.0,
		CORPSE_FADE_TIME
	)
	# --------------------------------------------------------
	# 9. 同時執行 Shader 溶解效果
	# 讓屍體不是單純透明消失
	# --------------------------------------------------------
	if corpse_material and is_instance_valid(corpse_material):
		fade_tween.parallel().tween_property(
			corpse_material,
			"shader_parameter/dissolve_progress",
			1.0,
			CORPSE_FADE_TIME
		).set_trans(Tween.TRANS_LINEAR)
	# --------------------------------------------------------
	# 10. 等待淡出及溶解效果結束
	# --------------------------------------------------------
	await fade_tween.finished
	# --------------------------------------------------------
	# 11. 完全消失後，釋放敵人節點
	# --------------------------------------------------------
	if is_instance_valid(character):
		character.queue_free()


# ============================================================
# 【屍體變灰效果】
# 將敵人原本的材質複製一份，避免影響其他敵人
# ============================================================
func _apply_corpse_appearance() -> ShaderMaterial:
	# --------------------------------------------------------
	# 1. 取得敵人的 AnimatedSprite2D
	# --------------------------------------------------------
	var sprite = character.get_node_or_null(
        "AnimatedSprite2D"
	) as AnimatedSprite2D
	# 如果找不到 Sprite，就無法執行變灰效果
	if sprite == null:
		return null
	# --------------------------------------------------------
	# 2. 取得原本的 ShaderMaterial
	# --------------------------------------------------------
	var original_material = sprite.material as ShaderMaterial
	# 如果原本沒有 ShaderMaterial，就不執行 Shader 變色
	if original_material == null:
		return null
	# --------------------------------------------------------
	# 3. 複製材質
	#
	# 非常重要：
	# 不直接修改共用材質，避免同一種敵人的其他個體
	# 也一起變成灰色。
	# --------------------------------------------------------
	var corpse_material = original_material.duplicate() as ShaderMaterial
	# 將複製的材質指定給目前死亡的敵人
	sprite.material = corpse_material
	# --------------------------------------------------------
	# 4. 設定屍體 Shader 初始參數
	# --------------------------------------------------------
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
	# --------------------------------------------------------
	# 5. 建立變灰 Tween
	# --------------------------------------------------------
	var tint_tween = character.create_tween()
	# 使用平滑過渡
	tint_tween.set_trans(Tween.TRANS_SINE)
	tint_tween.set_ease(Tween.EASE_OUT)
	# --------------------------------------------------------
	# 6. 讓敵人逐漸轉換成灰階
	# --------------------------------------------------------
	tint_tween.tween_property(
		corpse_material,
		"shader_parameter/grayscale_modifier",
		1.0,
		CORPSE_TINT_TIME
	)
	# --------------------------------------------------------
	# 7. 同時降低屍體透明度
	# --------------------------------------------------------
	tint_tween.parallel().tween_property(
		sprite,
		"modulate:a",
		CORPSE_ALPHA,
		CORPSE_TINT_TIME
	)

	# --------------------------------------------------------
	# 8. 等待變灰效果完成
	# --------------------------------------------------------
	await tint_tween.finished
	# --------------------------------------------------------
	# 9. 回傳目前敵人的專屬材質
	# 後續淡出流程會使用這個材質控制溶解
	# --------------------------------------------------------
	return corpse_material

extends State

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerDie V2｜正式玩家死亡狀態
#
# Godot 4.5.1
#
# STEP 10.6.7-B
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 播放玩家死亡動畫
# 2. 停止玩家移動
# 3. 關閉肉體碰撞
# 4. 執行死亡金幣懲罰
# 5. 記錄死亡靈魂資料
# 6. 等待死亡演出完成
# 7. 向 RespawnManager 提出重生要求
#
# ============================================================
# 系統分工
# ============================================================
#
# PlayerDie：
# 管理玩家死亡演出及死亡懲罰。
#
# RespawnManager：
# 管理正式檢查點及死亡重生。
#
# SceneTransition：
# 管理場景切換及黑幕動畫。
#
# Player：
# 管理新玩家初始化與靈魂生成。
#
# 本腳本不直接讀寫 JSON。
# 不直接執行正式遊戲場景切換。
# ============================================================


# ============================================================
# 1. Inspector 設定
# ============================================================

@export_group("死亡演出設定")

## 原本使用的死亡動畫名稱
@export var death_animation: StringName = &"dead_down"

## 死亡動畫播放完畢後的停留時間
@export var death_hold_time: float = 2.0

## 死亡動畫最長等待時間，避免動畫異常造成卡死
@export var animation_timeout: float = 10.0


@export_group("除錯設定")

@export var debug_log: bool = true


# ============================================================
# 2. 死亡狀態鎖
# ============================================================

var _death_started: bool = false

var _penalty_applied: bool = false


# ============================================================
# 3. 進入死亡狀態
# ============================================================

func enter():

	# 防止同一個死亡狀態重複執行。
	if _death_started:

		return

	_death_started = true

	if not is_instance_valid(character):

		return

	_log("玩家進入死亡狀態")

	# --------------------------------------------------------
	# A. 停止玩家移動
	# --------------------------------------------------------

	character.velocity = Vector2.ZERO

	character.input_direction = Vector2.ZERO

	character.is_casting = false

	# --------------------------------------------------------
	# B. 關閉肉體碰撞
	#
	# 使用 set_deferred()，
	# 避免物理查詢期間直接修改碰撞。
	# --------------------------------------------------------

	var collision = character.get_node_or_null(
		"CollisionShape2D"
	)

	if collision:

		collision.set_deferred("disabled", true)

	# --------------------------------------------------------
	# C. 播放死亡動畫
	# --------------------------------------------------------

	await _play_death_animation()

	if not is_instance_valid(character):

		return

	# --------------------------------------------------------
	# D. 執行死亡懲罰
	# --------------------------------------------------------

	_handle_death_penalty()

	# --------------------------------------------------------
	# E. 執行正式死亡重生流程
	# --------------------------------------------------------

	await _restart_game()


# ============================================================
# 4. 死亡物理更新
#
# 死亡後不接受移動輸入。
# 實際 move_and_slide() 仍由 Player 處理，
# 避免同一物理幀重複執行位移。
# ============================================================

func state_physics_update(_delta: float):

	if not is_instance_valid(character):

		return

	character.velocity = Vector2.ZERO


# ============================================================
# 5. 播放死亡動畫
#
# 安全檢查：
#
# - 動畫播放器是否存在
# - SpriteFrames 是否存在
# - 指定死亡動畫是否存在
# - 動畫是否為循環播放
#
# 若動畫異常，仍可繼續死亡流程。
# ============================================================

func _play_death_animation() -> void:

	var sprite: AnimatedSprite2D = (
		character.animated_sprite_2d
	)

	if not is_instance_valid(sprite):

		push_warning("【PlayerDie】找不到動畫播放器")

		return

	if sprite.sprite_frames == null:

		push_warning("【PlayerDie】缺少 SpriteFrames")

		return

	if not sprite.sprite_frames.has_animation(death_animation):

		push_warning(
			"【PlayerDie】找不到死亡動畫："
			+ String(death_animation)
		)

		return

	# 死亡動畫必須為非循環播放。
	sprite.sprite_frames.set_animation_loop(
		death_animation,
		false
	)

	sprite.stop()

	sprite.play(death_animation)

	var start_time: int = Time.get_ticks_msec()

	# 使用有時間上限的等待流程，
	# 避免 animation_finished 未發送時永久卡死。
	while (
		is_instance_valid(sprite)
		and sprite.is_playing()
		and sprite.animation == death_animation
	):

		var elapsed: float = (
			float(Time.get_ticks_msec() - start_time)
			/ 1000.0
		)

		if elapsed >= animation_timeout:

			push_warning("【PlayerDie】死亡動畫等待逾時")

			break

		await get_tree().process_frame

	_log("死亡動畫處理完成")


# ============================================================
# 6. 處理死亡懲罰
#
# 沿用原有規則：
#
# 死亡扣除目前一半金幣。
# 靈魂記錄死亡位置與遺失金額。
# 新死亡紀錄取代上一份死亡紀錄。
#
# 本階段只保存於運行時記憶體。
# 不直接寫入 JSON。
# ============================================================

func _handle_death_penalty() -> void:

	if _penalty_applied:

		return

	if not is_instance_valid(character):

		return

	var current_map: Node = get_tree().current_scene

	if not is_instance_valid(current_map):

		push_error("【PlayerDie】找不到死亡地圖")

		return

	_penalty_applied = true

	# --------------------------------------------------------
	# A. 扣除一半金幣
	# --------------------------------------------------------

	var penalty: int = int(
		float(DataManager.total_gold) * 0.5
	)

	DataManager.total_gold -= penalty

	# --------------------------------------------------------
	# B. 記錄死亡靈魂
	# --------------------------------------------------------

	DataManager.has_soul_on_ground = true

	DataManager.soul_spawn_pos = character.global_position

	DataManager.soul_stored_gold = penalty

	DataManager.soul_map_path = current_map.scene_file_path

	# --------------------------------------------------------
	# C. 靈魂實體生成
	#
	# 不在即將卸載的地圖生成新的靈魂。
	#
	# 由 Player._ready() 後續還原，
	# 避免死亡期間重複建立靈魂實體。
	# --------------------------------------------------------

	_log("玩家死亡，遺失金幣：" + str(penalty))

	_log(
		"死亡後剩餘金幣："
		+ str(DataManager.total_gold)
	)

	_log(
		"靈魂位置："
		+ str(DataManager.soul_spawn_pos)
	)

	_log(
		"靈魂地圖："
		+ DataManager.soul_map_path
	)


# ============================================================
# 7. 正式死亡重生
#
# 保留原本死亡後停留 2 秒的演出。
#
# 不再直接 change_scene_to_file()。
# 不再直接 reload_current_scene()。
#
# 正式重生交給 RespawnManager 統一管理。
# ============================================================

func _restart_game() -> void:

	await get_tree().create_timer(
		death_hold_time
	).timeout

	if not is_instance_valid(character):

		return

	_log("提出正式死亡重生要求")

	var accepted: bool = RespawnManager.request_respawn()

	if not accepted:

		push_error(
			"【PlayerDie】重生要求失敗，請檢查 RespawnManager"
		)


# ============================================================
# 8. 統一除錯輸出
# ============================================================

func _log(message: String) -> void:

	if debug_log:

		print("【PlayerDie】" + message)

extends BaseEnemy
class_name SpinningTopEnemy

# ============================================================
# 【失色陀螺怪 - 主控制器】
#
# 繼承 BaseEnemy 的共用功能：
# 血量、受傷、死亡、金幣、擊退、迷霧現形。
#
# 陀螺專屬功能：
# 1. 四象限動畫
# 2. 配合影格的彈跳移動
# 3. 高速旋轉攻擊
# 4. 單次攻擊防重複傷害
# 5. 動畫時間管理
# 6. 暈眩與恢復狀態保護
# ============================================================


# ============================================================
# Inspector - 彈跳移動設定
# ============================================================

@export_group("陀螺怪 - 彈跳設定")

# 普通漫遊的動畫播放速度
@export_range(0.1, 3.0, 0.1)
var wander_animation_speed: float = 1.0

# 追擊時的動畫播放速度
@export_range(0.1, 3.0, 0.1)
var chase_animation_speed: float = 1.5

# 彈跳節奏強度
# 0.0 = 等速平移
# 1.0 = 完整套用彈跳節奏
@export_range(0.0, 1.0, 0.05)
var hop_strength: float = 1.0


# ============================================================
# Inspector - 戰鬥設定
# ============================================================

@export_group("陀螺怪 - 戰鬥設定")

# 旋轉攻擊的額外擊退倍率
@export var spin_knockback_multiplier: float = 2.0

# 休息及暈眩期間的速度衰減
@export var recovery_friction: float = 1800.0


# ============================================================
# 彈跳動畫影格權重
#
# 對應目前 12 幀的行走動畫。
# 數值越大，代表這個影格向前移動越快。
# 數值越小，代表接近落地或停頓階段。
# ============================================================

const FRONT_WEIGHTS = [
	0.80, 1.80, 1.60, 0.80,
	0.15, 0.55, 0.35, 0.30,
	1.75, 1.65, 0.75, 0.15
]

const BACK_WEIGHTS = [
	1.00, 1.50, 0.85, 0.20,
	1.60, 0.50, 0.85, 0.25,
	1.45, 0.65, 0.25, 1.60
]


# ============================================================
# 內部狀態變數
# ============================================================

# 是否正在執行高速旋轉攻擊
var spin_active: bool = false

# 紀錄是否從暈眩狀態進入 Recover
var recover_from_stun: bool = false


# ============================================================
# 初始化
# ============================================================

func _ready() -> void:

	# 使用四象限動畫
	use_diagonal_anim = true

	# 素材本身已有跳躍動作，
	# 不使用青蛙額外的拋物線高度。
	use_jump_movement = false

	# 建立陀螺專屬動畫資源
	_prepare_sprite_frames()

	# 執行父類別初始化
	super._ready()

	# 確保不再使用遠程射擊狀態
	if state_machine:
		state_machine.states.erase("shoot")

	# 初始狀態關閉攻擊碰撞區
	set_spin_active(false)


# ============================================================
# 動畫資源初始化
#
# 複製 SpriteFrames，避免修改共用資源時
# 影響其他使用相同素材的敵人。
# ============================================================

func _prepare_sprite_frames() -> void:

	if not animated_sprite_2d:
		return

	if not animated_sprite_2d.sprite_frames:
		return

	animated_sprite_2d.sprite_frames = (
		animated_sprite_2d.sprite_frames.duplicate()
		as SpriteFrames
	)

	var frames = animated_sprite_2d.sprite_frames

	for anim in frames.get_animation_names():

		var anim_name = String(anim)

		# 持續性動畫：開啟循環
		if (
			anim_name.begins_with("idle_")
			or anim_name.begins_with("move_")
			or anim_name.begins_with("spin_")
		):
			frames.set_animation_loop(anim, true)

		# 一次性動作：關閉循環
		elif (
			anim_name.begins_with("charge_")
			or anim_name.begins_with("pant_")
			or anim_name.begins_with("stun_")
			or anim_name.begins_with("recover_")
		):
			frames.set_animation_loop(anim, false)


# ============================================================
# 普通動畫播放
#
# 沿用父類別的四象限方向判定。
# 切換移動方向時，保留原有影格進度。
# ============================================================

func play_animation(
	prefix: String,
	dir: Vector2 = Vector2.ZERO
) -> void:

	if not animated_sprite_2d:
		return

	var old_animation = String(animated_sprite_2d.animation)
	var old_frame = animated_sprite_2d.frame
	var old_progress = animated_sprite_2d.frame_progress

	super.play_animation(prefix, dir)

	var new_animation = String(animated_sprite_2d.animation)

	if prefix == "move":

		# 四象限切換時保持彈跳節奏
		if (
			old_animation.begins_with("move_")
			and new_animation.begins_with("move_")
			and old_animation != new_animation
		):

			var frame_count = (
				animated_sprite_2d.sprite_frames
				.get_frame_count(new_animation)
			)

			if frame_count > 0:

				animated_sprite_2d.set_frame_and_progress(
					clampi(old_frame, 0, frame_count - 1),
					old_progress
				)

		# 依照狀態調整動畫速度
		if (
			state_machine
			and state_machine.current_state
			and state_machine.current_state.name == "Chase"
		):
			animated_sprite_2d.speed_scale = chase_animation_speed

		else:
			animated_sprite_2d.speed_scale = wander_animation_speed

	else:

		# 其他動畫維持正常播放速度
		animated_sprite_2d.speed_scale = 1.0


# ============================================================
# 取得四象限動畫名稱
# ============================================================

func get_directional_animation_name(
	prefix: String,
	dir: Vector2
) -> String:

	var target_dir = dir

	if target_dir.is_zero_approx():
		target_dir = last_facing_vec

	var x_name: String
	var y_name: String

	if target_dir.x > 0.0:
		x_name = "right"

	elif target_dir.x < 0.0:
		x_name = "left"

	else:
		x_name = "left" if target_dir.y < 0.0 else "right"

	y_name = "up" if target_dir.y < 0.0 else "down"

	return prefix + "_" + x_name + "_" + y_name


# ============================================================
# 播放一次性動作動畫
#
# 適用於蓄力、暈倒、休息及恢復。
# 回傳動畫的實際播放時間。
#
# 如果缺少素材，暫時播放 Idle，
# 避免狀態機因動畫不存在而卡死。
# ============================================================

func play_top_action(
	prefix: String,
	dir: Vector2 = Vector2.ZERO,
	warn_if_missing: bool = true
) -> float:

	if not animated_sprite_2d:
		return 0.0

	var frames = animated_sprite_2d.sprite_frames

	if not frames:
		return 0.0

	var anim_name = get_directional_animation_name(
		prefix,
		dir
	)

	# 恢復動畫若只有左右素材，
	# 允許使用左右版本作為備用。
	if not frames.has_animation(anim_name):

		if prefix in ["recover", "pant_recover"]:

			var side = "left" if "_left_" in anim_name else "right"

			anim_name = prefix + "_" + side

	# 素材仍不存在時，使用待機動畫
	if (
		not frames.has_animation(anim_name)
		or frames.get_frame_count(anim_name) == 0
	):

		if warn_if_missing:

			push_warning(
				"陀螺怪缺少動畫：" + anim_name
			)

		play_animation("idle", dir)

		return 0.0

	# 強制從第一張影格開始播放
	animated_sprite_2d.stop()
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.play(anim_name)

	return get_animation_duration(anim_name)


# ============================================================
# 計算動畫的實際長度
#
# 同時考慮 FPS 和每張影格的相對持續時間。
# ============================================================

func get_animation_duration(anim_name: String) -> float:

	if not animated_sprite_2d:
		return 0.0

	var frames = animated_sprite_2d.sprite_frames

	if not frames or not frames.has_animation(anim_name):
		return 0.0

	var fps = frames.get_animation_speed(anim_name)

	if fps <= 0.0:
		return 0.0

	var total_duration: float = 0.0

	for i in range(frames.get_frame_count(anim_name)):

		total_duration += frames.get_frame_duration(
			anim_name,
			i
		)

	return total_duration / fps


# ============================================================
# 高速旋轉動畫
#
# 旋轉方向獨立於四象限移動方向。
# 一輪攻擊固定使用同一個自轉方向。
# ============================================================

func play_spin_animation(dir: Vector2) -> bool:

	if not animated_sprite_2d:
		return false

	var frames = animated_sprite_2d.sprite_frames

	if not frames:
		return false

	var anim_name = "spin_left" if dir.x < 0.0 else "spin_right"

	# 缺少其中一側時，使用另一側
	if not frames.has_animation(anim_name):

		anim_name = (
			"spin_right"
			if anim_name == "spin_left"
			else "spin_left"
		)

	# 兩種動畫都不存在，取消旋轉攻擊
	if (
		not frames.has_animation(anim_name)
		or frames.get_frame_count(anim_name) == 0
	):

		push_warning("陀螺怪缺少高速旋轉動畫")

		return false

	animated_sprite_2d.stop()
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.play(anim_name)

	return true


# ============================================================
# 彈跳移動系統
# ============================================================

func apply_locomotion(
	move_dir: Vector2,
	base_speed: float
) -> void:

	if move_dir.is_zero_approx():

		velocity = Vector2.ZERO
		return

	if not animated_sprite_2d:

		velocity = move_dir.normalized() * base_speed
		return

	var factor = _get_hop_factor()

	# Inspector 控制彈跳節奏的強弱
	factor = lerpf(
		1.0,
		factor,
		hop_strength
	)

	velocity = (
		move_dir.normalized()
		* base_speed
		* factor
	)


# ============================================================
# 取得目前動畫的移動權重
# ============================================================

func _get_hop_weights() -> Array:

	var anim_name = String(animated_sprite_2d.animation)

	if anim_name.ends_with("_up"):
		return BACK_WEIGHTS

	return FRONT_WEIGHTS


# ============================================================
# 計算平滑彈跳速度
# ============================================================

func _get_hop_factor() -> float:

	var anim_name = String(animated_sprite_2d.animation)

	if not anim_name.begins_with("move_"):
		return 1.0

	var weights = _get_hop_weights()

	var current_frame = animated_sprite_2d.frame % weights.size()
	var next_frame = (current_frame + 1) % weights.size()

	# 影格之間進行平滑插值
	var factor = lerpf(
		float(weights[current_frame]),
		float(weights[next_frame]),
		animated_sprite_2d.frame_progress
	)

	# 正規化平均速度
	var total: float = 0.0

	for weight in weights:
		total += float(weight)

	var average = total / float(weights.size())

	return factor / maxf(average, 0.001)


# ============================================================
# 判斷目前是否處於落地階段
# ============================================================

func is_jump_grounded() -> bool:

	if not animated_sprite_2d:
		return true

	var anim_name = String(animated_sprite_2d.animation)

	if not anim_name.begins_with("move_"):
		return true

	var weights = _get_hop_weights()

	var current_frame = animated_sprite_2d.frame % weights.size()

	return float(weights[current_frame]) <= 0.35


# ============================================================
# 開啟或關閉旋轉攻擊碰撞區
# ============================================================

func set_spin_active(active: bool) -> void:

	spin_active = active

	# 新的一輪攻擊，重置命中紀錄
	if active:
		has_hit_player = false

	var shape = get_node_or_null(
		"Hitbox/CollisionShape2D"
	) as CollisionShape2D

	if shape:

		shape.set_deferred(
			"disabled",
			not active
		)


# ============================================================
# 判斷碰撞對象是否為玩家
# ============================================================

func is_spin_player(target: Node) -> bool:

	if not is_instance_valid(target):
		return false

	return (
		target is Player
		or target.is_in_group("player")
		or target.name == "player"
	)


# ============================================================
# 判斷碰撞對象是否為場景障礙物
#
# 不會將其他 CharacterBody2D 敵人誤認為牆壁。
# 特殊障礙物可以加入 spin_wall 群組。
# ============================================================

func is_spin_obstacle(target: Node) -> bool:

	if not is_instance_valid(target):
		return false

	if is_spin_player(target):
		return false

	return (
		target is StaticBody2D
		or target is TileMapLayer
		or target.is_class("TileMap")
		or target.is_in_group("spin_wall")
	)


# ============================================================
# 統一處理旋轉傷害
#
# 一輪旋轉只允許命中玩家一次。
# ============================================================

func try_spin_hit(
	target: Node2D,
	target_area: Area2D = null
) -> void:

	if is_dead or not spin_active:
		return

	if has_hit_player:
		return

	if not is_spin_player(target):
		return

	# 鎖定本輪攻擊，防止重複扣血
	has_hit_player = true

	var knockback_dir = global_position.direction_to(
		target.global_position
	)

	if knockback_dir.is_zero_approx():
		knockback_dir = last_facing_vec

	# 優先透過 Hurtbox 傳遞傷害
	if (
		is_instance_valid(target_area)
		and target_area.has_method("take_damage")
	):

		target_area.call(
			"take_damage",
			melee_damage,
			global_position,
			knockback_dir,
			false,
			spin_knockback_multiplier
		)

	# 備用：直接傳遞給玩家
	elif target.has_method("take_damage"):

		target.call(
			"take_damage",
			melee_damage,
			global_position,
			knockback_dir,
			false,
			spin_knockback_multiplier
		)


# ============================================================
# 覆寫父類別的 Area 碰撞訊號
# ============================================================

func _on_hitbox_area_entered(area: Area2D) -> void:

	if not area is Hurtbox:
		return

	var target = area.get_parent() as Node2D

	if target:

		try_spin_hit(
			target,
			area
		)


# ============================================================
# 覆寫父類別的 Body 碰撞訊號
# ============================================================

func _on_hitbox_body_entered(body: Node2D) -> void:

	try_spin_hit(body)


# ============================================================
# 覆寫原本持續接觸扣血機制
#
# 只在高速旋轉期間偵測傷害。
# ============================================================

func _check_hitbox_overlap() -> void:

	if not spin_active or has_hit_player:
		return

	if not hitbox or not hitbox.monitoring:
		return

	# 優先偵測玩家 Hurtbox
	for area in hitbox.get_overlapping_areas():

		if area is Hurtbox:

			var target = area.get_parent() as Node2D

			if target:

				try_spin_hit(
					target,
					area
				)

	# 備用：偵測玩家本體
	for body in hitbox.get_overlapping_bodies():

		if body is Node2D:
			try_spin_hit(body)


# ============================================================
# 共用恢復煞車
# ============================================================

func apply_recovery_friction(delta: float) -> void:

	velocity = velocity.move_toward(
		Vector2.ZERO,
		recovery_friction * delta
	)


# ============================================================
# 受傷狀態保護
#
# 暈眩、休息、恢復期間依然可以扣血，
# 但一般受傷不會強制取消目前動畫。
# 死亡仍由 BaseEnemy 正常處理。
# ============================================================

func handle_hurt() -> void:

	if is_dead:
		return

	if not state_machine or not state_machine.current_state:
		return

	var state_name = String(
		state_machine.current_state.name
	).to_lower()

	if state_name in ["stun", "pant", "recover"]:
		return

	super.handle_hurt()

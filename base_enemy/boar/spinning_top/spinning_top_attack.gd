extends State

# ============================================================
# 【失色陀螺怪 - Attack 旋轉攻擊 V2】
#
# 保留原本的戰鬥邏輯：
# 1. 原地蓄力
# 2. 加速旋轉
# 3. 有慣性的追擊轉向
#
# 新增視覺演出：
# 1. 蓄力提示
# 2. 高速旋轉揚塵
# 3. 撞牆碎屑
# 4. 撞牆鏡頭震動與頓幀
# ============================================================


# ============================================================
# Inspector - 蓄力設定
# ============================================================

@export_group("蓄力設定")

@export var min_charge_duration: float = 0.6


# ============================================================
# Inspector - 旋轉攻擊設定
# ============================================================

@export_group("旋轉攻擊設定")

@export var spin_start_speed: float = 120.0

@export var spin_speed: float = 600.0

@export var acceleration: float = 1800.0

@export var spin_duration: float = 2.5

@export var turn_speed: float = 90.0


# ============================================================
# Inspector - 撞牆演出設定
# ============================================================

@export_group("撞牆演出設定")

# 鏡頭震動強度
@export var wall_shake_strength: float = 18.0

# 是否啟用撞牆頓幀
@export var enable_wall_hitstop: bool = true

# 頓幀持續時間
@export var wall_hitstop_duration: float = 0.06

# 頓幀期間的時間倍率
@export var wall_hitstop_time_scale: float = 0.08


# ============================================================
# 攻擊階段
# ============================================================

enum AttackPhase {
	CHARGE,
	SPIN
}

var phase: AttackPhase = AttackPhase.CHARGE


# ============================================================
# 節點引用
# ============================================================

var enemy: SpinningTopEnemy

var spin_fx: SpinningTopFX


# ============================================================
# 內部變數
# ============================================================

var charge_timer: float = 0.0

var spin_timer: float = 0.0

var spin_direction: Vector2 = Vector2.ZERO

var current_speed: float = 0.0


# ============================================================
# 進入攻擊狀態
# ============================================================

func enter() -> void:

	enemy = character as SpinningTopEnemy

	if not enemy:
		return

	# 取得專屬特效控制器
	spin_fx = enemy.get_node_or_null(
		"SpinFX"
	) as SpinningTopFX

	enemy.can_attack = false

	enemy.has_hit_player = false

	enemy.velocity = Vector2.ZERO

	enemy.set_spin_active(false)

	phase = AttackPhase.CHARGE

	current_speed = 0.0

	spin_timer = spin_duration

	# --------------------------------------------------------
	# 取得蓄力方向
	# --------------------------------------------------------

	spin_direction = enemy.last_facing_vec

	if is_instance_valid(enemy.player_node):

		var target_direction = enemy.global_position.direction_to(
			enemy.player_node.global_position
		)

		if not target_direction.is_zero_approx():

			spin_direction = target_direction

	if spin_direction.is_zero_approx():

		spin_direction = Vector2.DOWN

	enemy.last_facing_vec = spin_direction

	# --------------------------------------------------------
	# 播放蓄力動畫
	# --------------------------------------------------------

	var animation_duration = enemy.play_top_action(
		"charge",
		spin_direction
	)

	charge_timer = maxf(
		min_charge_duration,
		animation_duration
	)

	# --------------------------------------------------------
	# 啟動蓄力特效
	# --------------------------------------------------------

	if is_instance_valid(spin_fx):

		spin_fx.begin_charge(charge_timer)


# ============================================================
# 物理更新
# ============================================================

func state_physics_update(delta: float) -> void:

	if not is_instance_valid(enemy):
		return

	if enemy.is_dead:
		return

	match phase:

		AttackPhase.CHARGE:

			_update_charge(delta)

		AttackPhase.SPIN:

			_update_spin(delta)


# ============================================================
# 第一階段 - 原地蓄力
# ============================================================

func _update_charge(delta: float) -> void:

	enemy.velocity = Vector2.ZERO

	charge_timer -= delta

	if charge_timer <= 0.0:

		_start_spin()


# ============================================================
# 開始高速旋轉
# ============================================================

func _start_spin() -> void:

	# 重新確認玩家方向
	if (
		is_instance_valid(enemy.player_node)
		and enemy.can_see_player
	):

		var new_direction = enemy.global_position.direction_to(
			enemy.player_node.global_position
		)

		if not new_direction.is_zero_approx():

			spin_direction = new_direction

	enemy.last_facing_vec = spin_direction

	# 播放旋轉動畫
	if not enemy.play_spin_animation(spin_direction):

		_finish_spin("Pant")

		return

	phase = AttackPhase.SPIN

	current_speed = clampf(
		spin_start_speed,
		0.0,
		maxf(spin_speed, 0.0)
	)

	spin_timer = spin_duration

	# 正式開啟攻擊判定
	enemy.set_spin_active(true)

	enemy.velocity = spin_direction * current_speed

	# 啟動高速旋轉揚塵
	if is_instance_valid(spin_fx):

		spin_fx.begin_spin(spin_direction)


# ============================================================
# 第二階段 - 持續旋轉追擊
# ============================================================

func _update_spin(delta: float) -> void:

	# --------------------------------------------------------
	# 1. 已經撞到玩家
	# --------------------------------------------------------

	if enemy.has_hit_player:

		_finish_spin("Pant")

		return

	# --------------------------------------------------------
	# 2. 偵測實體碰撞
	# --------------------------------------------------------

	for i in range(enemy.get_slide_collision_count()):

		var collision = enemy.get_slide_collision(i)

		if not collision:
			continue

		var collider = collision.get_collider() as Node

		if not collider:
			continue

		# 撞到玩家
		if enemy.is_spin_player(collider):

			var target = collider as Node2D

			if target:

				enemy.try_spin_hit(target)

				_finish_spin("Pant")

				return

		# 撞到場景障礙物
		if enemy.is_spin_obstacle(collider):

			_handle_wall_impact(collision)

			return

	# --------------------------------------------------------
	# 3. 旋轉時間耗盡
	# --------------------------------------------------------

	spin_timer -= delta

	if spin_timer <= 0.0:

		_finish_spin("Pant")

		return

	# --------------------------------------------------------
	# 4. 具有慣性的追擊轉向
	# --------------------------------------------------------

	if (
		is_instance_valid(enemy.player_node)
		and enemy.can_see_player
	):

		var target_direction = enemy.global_position.direction_to(
			enemy.player_node.global_position
		)

		if not target_direction.is_zero_approx():

			var new_angle = rotate_toward(
				spin_direction.angle(),
				target_direction.angle(),
				deg_to_rad(turn_speed) * delta
			)

			spin_direction = Vector2.from_angle(
				new_angle
			)

	# --------------------------------------------------------
	# 5. 持續加速
	# --------------------------------------------------------

	current_speed = move_toward(
		current_speed,
		spin_speed,
		acceleration * delta
	)

	enemy.last_facing_vec = spin_direction

	enemy.velocity = (
		spin_direction
		* current_speed
	)

	# 持續更新揚塵的噴射方向
	if is_instance_valid(spin_fx):

		spin_fx.update_spin_direction(
			spin_direction
		)


# ============================================================
# 撞牆演出
# ============================================================

func _handle_wall_impact(
	collision: KinematicCollision2D
) -> void:

	# 取得真正撞擊牆壁的位置
	var hit_position = collision.get_position()

	# 取得牆壁表面法線
	var wall_normal = collision.get_normal()

	# 如果敵人目前可見，才播放全局撞擊演出，
	# 避免迷霧中的敵人撞牆造成莫名震動。
	if enemy.is_visible_in_tree():

		# 撞牆碎屑
		if is_instance_valid(spin_fx):

			spin_fx.play_wall_impact(
				hit_position,
				wall_normal
			)

		# 鏡頭震動
		enemy.get_tree().call_group(
			"main_camera",
			"apply_shake",
			wall_shake_strength
		)

		# 對接原本 DataManager 的頓幀系統
		if (
			enable_wall_hitstop
			and DataManager
			and DataManager.has_method("trigger_hitstop")
		):

			DataManager.trigger_hitstop(
				wall_hitstop_duration,
				wall_hitstop_time_scale
			)

	# 撞牆後進入暈眩
	_finish_spin("Stun")


# ============================================================
# 結束旋轉
# ============================================================

func _finish_spin(next_state: String) -> void:

	enemy.set_spin_active(false)

	enemy.velocity = Vector2.ZERO

	# 停止持續揚塵或蓄力提示
	if is_instance_valid(spin_fx):

		spin_fx.stop_attack_fx()

	state_machine.change_state(next_state)


# ============================================================
# 離開攻擊狀態
#
# 避免被擊倒或死亡時，
# 揚塵和蓄力特效仍然持續播放。
# ============================================================

func exit() -> void:

	if not is_instance_valid(enemy):
		return

	enemy.set_spin_active(false)

	enemy.velocity = Vector2.ZERO

	if is_instance_valid(spin_fx):

		spin_fx.stop_attack_fx()

	enemy.can_attack = not enemy.is_dead

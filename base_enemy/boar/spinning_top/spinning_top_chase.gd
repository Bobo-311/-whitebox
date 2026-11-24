extends State

# ============================================================
# 【失色陀螺怪 - Chase 追擊狀態】
#
# 發現玩家後：
# 1. 以彈跳方式逼近玩家。
# 2. 進入攻擊範圍後等待落地。
# 3. 落地後進入蓄力攻擊。
#
# 完全移除原本野豬的遠程射擊。
# ============================================================


@export_group("追擊設定")

# 彈跳追擊速度
@export var chase_speed: float = 220.0

# 發動旋轉攻擊的最大距離
@export var attack_range: float = 450.0

# 正式攻擊功能開關
@export var enable_spin_attack: bool = true

# 關閉攻擊功能時的測試停止距離
@export var test_stop_distance: float = 100.0


var enemy: SpinningTopEnemy


# ============================================================
# 進入追擊狀態
# ============================================================

func enter() -> void:

	enemy = character as SpinningTopEnemy

	if not enemy:
		return

	enemy.velocity = Vector2.ZERO


# ============================================================
# 追擊更新
# ============================================================

func state_physics_update(_delta: float) -> void:

	if not is_instance_valid(enemy):
		return

	if enemy.is_dead:
		return

	# 玩家離開視野，返回漫遊
	if (
		not is_instance_valid(enemy.player_node)
		or not enemy.can_see_player
	):

		enemy.velocity = Vector2.ZERO

		state_machine.change_state("Move")

		return

	# 計算玩家距離及方向
	var target_offset = (
		enemy.player_node.global_position
		- enemy.global_position
	)

	var distance = target_offset.length()
	var direction = target_offset.normalized()

	if not direction.is_zero_approx():

		enemy.last_facing_vec = direction

	# 尚未恢復攻擊權限
	if not enemy.can_attack:

		enemy.velocity = Vector2.ZERO
		enemy.play_animation("idle")

		return

	# --------------------------------------------------------
	# 正式攻擊判定
	# --------------------------------------------------------

	if enable_spin_attack:

		if (
			distance <= attack_range
			and enemy.is_jump_grounded()
		):

			enemy.velocity = Vector2.ZERO

			state_machine.change_state("Attack")

			return

	# --------------------------------------------------------
	# 開發測試模式
	# --------------------------------------------------------

	else:

		if (
			distance <= test_stop_distance
			and enemy.is_jump_grounded()
		):

			enemy.velocity = Vector2.ZERO
			enemy.play_animation("idle")

			return

	# 防止玩家與敵人座標重疊
	if direction.is_zero_approx():

		enemy.velocity = Vector2.ZERO

		return

	# --------------------------------------------------------
	# 彈跳逼近玩家
	# --------------------------------------------------------

	enemy.play_animation(
		"move",
		direction
	)

	enemy.apply_locomotion(
		direction,
		chase_speed
	)

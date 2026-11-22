extends State

# ============================================================
# 【失色陀螺怪 - Stun 暈眩狀態】
#
# 進入條件：
# 1. 高速旋轉撞到牆壁或場景障礙物。
# 2. 遭到玩家的控場技能攻擊。
#
# 保留原本黃色散彈槍的暈眩功能。
# ============================================================


# ============================================================
# Inspector 匯出設定
# ============================================================

@export_group("暈眩設定")

# 撞牆時的預設暈眩時間
@export var stun_duration: float = 3.0


# ============================================================
# 外部控場接口
#
# 用來接收 BaseEnemy.apply_stun()
# 傳入的指定暈眩時間。
# ============================================================

var custom_duration: float = 0.0


# ============================================================
# 內部變數
# ============================================================

var enemy: SpinningTopEnemy

var stun_timer: float = 0.0


# ============================================================
# 進入暈眩狀態
# ============================================================

func enter() -> void:

	enemy = character as SpinningTopEnemy

	if not enemy:
		return

	# 禁止攻擊
	enemy.can_attack = false

	# 關閉旋轉攻擊判定
	enemy.set_spin_active(false)

	# 停止目前移動
	enemy.velocity = Vector2.ZERO

	# 預設使用撞牆暈眩時間
	var requested_duration = stun_duration

	# 如果是玩家技能施加的暈眩，
	# 優先使用技能指定的時間。
	if custom_duration > 0.0:

		requested_duration = custom_duration

		# 使用完畢後清空
		custom_duration = 0.0

	# 播放撞到東西暈倒動畫
	var animation_duration = enemy.play_top_action(
		"stun",
		enemy.last_facing_vec
	)

	# 確保暈倒動畫完整播放
	stun_timer = maxf(
		requested_duration,
		animation_duration
	)


# ============================================================
# 暈眩狀態物理更新
# ============================================================

func state_physics_update(delta: float) -> void:

	if not is_instance_valid(enemy):
		return

	if enemy.is_dead:
		return

	# 暈眩期間若再次受到控場，
	# 更新目前剩餘的暈眩時間。
	if custom_duration > 0.0:

		stun_timer = maxf(
			stun_timer,
			custom_duration
		)

		custom_duration = 0.0

	# 扣除暈眩時間
	stun_timer -= delta

	# 保留受擊造成的擊退效果
	enemy.apply_recovery_friction(delta)

	# 暈眩結束
	if stun_timer <= 0.0:

		# 標記為暈倒後恢復
		enemy.recover_from_stun = true

		# 進入恢復狀態
		state_machine.change_state("Recover")


# ============================================================
# 離開暈眩狀態
# ============================================================

func exit() -> void:

	if not is_instance_valid(enemy):
		return

	enemy.can_attack = not enemy.is_dead

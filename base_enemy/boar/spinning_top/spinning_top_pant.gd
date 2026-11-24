extends State

# ============================================================
# 【失色陀螺怪 - Pant 疲勞休息狀態】
#
# 進入條件：
# 1. 高速旋轉撞到玩家。
# 2. 高速旋轉時間耗盡。
#
# 執行流程：
# 停止攻擊 → 播放休息動畫 → 等待恢復
# → 進入 Recover 狀態。
# ============================================================


# ============================================================
# Inspector 匯出設定
# ============================================================

@export_group("疲勞休息設定")

# 最短休息時間
@export var pant_duration: float = 2.0


# ============================================================
# 內部變數
# ============================================================

var enemy: SpinningTopEnemy

var pant_timer: float = 0.0


# ============================================================
# 進入休息狀態
# ============================================================

func enter() -> void:

	# 取得陀螺怪主控制器
	enemy = character as SpinningTopEnemy

	if not enemy:
		return

	# 暫時禁止攻擊
	enemy.can_attack = false

	# 關閉旋轉攻擊碰撞區
	enemy.set_spin_active(false)

	# 停止移動
	enemy.velocity = Vector2.ZERO

	# 播放轉太久休息動畫
	var animation_duration = enemy.play_top_action(
		"pant",
		enemy.last_facing_vec
	)

	# 確保休息動畫至少完整播放一次
	pant_timer = maxf(
		pant_duration,
		animation_duration
	)


# ============================================================
# 休息狀態物理更新
# ============================================================

func state_physics_update(delta: float) -> void:

	if not is_instance_valid(enemy):
		return

	if enemy.is_dead:
		return

	# 扣除剩餘休息時間
	pant_timer -= delta

	# 處理受到攻擊後的擊退及煞車效果
	enemy.apply_recovery_friction(delta)

	# 休息時間結束
	if pant_timer <= 0.0:

		# 標記為普通疲勞恢復
		enemy.recover_from_stun = false

		# 進入恢復狀態
		state_machine.change_state("Recover")


# ============================================================
# 離開休息狀態
# ============================================================

func exit() -> void:

	if not is_instance_valid(enemy):
		return

	enemy.can_attack = not enemy.is_dead

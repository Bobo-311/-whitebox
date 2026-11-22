extends State

# ============================================================
# 【失色陀螺怪 - Recover 恢復狀態】
#
# 負責處理兩種恢復情況：
#
# Stun：
# 暈倒後重新站起來。
#
# Pant：
# 疲勞休息後重新進入待機。
#
# 如果沒有對應的恢復動畫，
# 自動使用 Idle 作為替代。
# ============================================================


# ============================================================
# Inspector 匯出設定
# ============================================================

@export_group("恢復設定")

# 最短恢復時間
@export var min_recover_duration: float = 0.2


# ============================================================
# 內部變數
# ============================================================

var enemy: SpinningTopEnemy

var recover_timer: float = 0.0


# ============================================================
# 進入恢復狀態
# ============================================================

func enter() -> void:

	enemy = character as SpinningTopEnemy

	if not enemy:
		return

	# 恢復期間禁止攻擊
	enemy.can_attack = false

	# 關閉旋轉攻擊判定
	enemy.set_spin_active(false)

	# 停止移動
	enemy.velocity = Vector2.ZERO

	var animation_duration: float = 0.0

	# --------------------------------------------------------
	# 情況一：從 Stun 暈倒狀態恢復
	# --------------------------------------------------------

	if enemy.recover_from_stun:

		animation_duration = enemy.play_top_action(
			"recover",
			enemy.last_facing_vec
		)

	# --------------------------------------------------------
	# 情況二：從 Pant 疲勞狀態恢復
	#
	# 目前尚未有這組素材，
	# 系統會自動使用 Idle。
	#
	# 未來補上 pant_recover 動畫即可，
	# 不需要再修改此腳本。
	# --------------------------------------------------------

	else:

		animation_duration = enemy.play_top_action(
			"pant_recover",
			enemy.last_facing_vec,
			false
		)

	# 確保恢復動畫完整播放
	recover_timer = maxf(
		min_recover_duration,
		animation_duration
	)


# ============================================================
# 恢復狀態物理更新
# ============================================================

func state_physics_update(delta: float) -> void:

	if not is_instance_valid(enemy):
		return

	if enemy.is_dead:
		return

	# 保留受擊的擊退及煞車效果
	enemy.apply_recovery_friction(delta)

	# 扣除恢復時間
	recover_timer -= delta

	if recover_timer > 0.0:
		return

	# 恢復完成，重新取得攻擊能力
	enemy.can_attack = true

	# 玩家仍然在視野內
	if (
		is_instance_valid(enemy.player_node)
		and enemy.can_see_player
	):

		# 繼續追擊
		state_machine.change_state("Chase")

	else:

		# 失去玩家視野，返回漫遊
		state_machine.change_state("Move")


# ============================================================
# 離開恢復狀態
# ============================================================

func exit() -> void:

	if not is_instance_valid(enemy):
		return

	# 清除上一輪暈眩紀錄
	enemy.recover_from_stun = false

	# 恢復攻擊權限
	enemy.can_attack = not enemy.is_dead


extends State

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerIdle V2｜玩家待機與安全攻擊輸入
# Godot 4.5.1
# STEP 10.7.7-F-5.1
# ============================================================
# 主要職責：
# 1. 播放玩家待機動畫
# 2. 保留原本擊退滑行效果
# 3. 偵測玩家移動要求
# 4. 接收合法的近戰攻擊要求
#
# 攻擊輸入統一由 StateMachine V2 提供。
# 不直接讀取全域 attack 按鍵狀態。
# ============================================================

# ============================================================
# 1. 進入待機狀態
# ============================================================

func enter():
	# 擊退組件仍在作用時，不強制清除角色速度。
	if not (
		character.knockback_component
		and character.knockback_component.knockback_force.length() > 0.0
	):
		character.velocity = Vector2.ZERO

	character.play_animation("idle")

# ============================================================
# 2. 待機物理更新
# ============================================================

func state_physics_update(_delta: float):
	# A. 保留原本擊退滑行保護。
	if (
		character.knockback_component
		and character.knockback_component.knockback_force.length() > 0.0
	):
		return

	# B. 保留原本移動狀態切換優先順序。
	if character.input_direction != Vector2.ZERO:
		state_machine.change_state("PlayerMove")
		return

	# C. 取得合法且尚未消耗的玩家攻擊輸入。
	# StateMachine 已統一驗證：
	# 戰鬥解鎖、購物、閱讀、劇情、暫停及轉場狀態。
	if state_machine.consume_player_attack_input():
		if OS.is_debug_build():
			print("【玩家戰鬥】已接受合法近戰攻擊輸入")

		state_machine.change_state("PlayerAttack")

extends State

var enemy: Barbarian # 野蠻人角色引用

# =====================================================
# 進入第一階段追擊狀態
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	enemy.set_contact_enabled(false) # 保證追擊期間沒有肉身傷害
	enemy.play_animation("move", enemy.last_facing_vec)

# =====================================================
# 追擊與攻擊距離判定
# =====================================================
func state_physics_update(_delta: float) -> void:
	if enemy.is_berserk:
		state_machine.change_state("BerserkCharge") # 二階不得退回普通追擊
		return
	var player: Player = enemy.get_combat_target()
	if not player or not enemy.can_see_player:
		state_machine.change_state("Move") # 一階失去玩家視野後恢復漫遊
		return
	var target_vector: Vector2 = enemy.get_combat_vector(player) # 取得雙方地面基準的相對位置
	var move_dir: Vector2 = target_vector.normalized()
	if move_dir != Vector2.ZERO:
		enemy.last_facing_vec = move_dir # 更新角色方向，供攻擊動畫使用
	if enemy.can_start_sword() and enemy.can_reach_with_sword(player, enemy.last_facing_vec):
		enemy.velocity = Vector2.ZERO # 確認攻擊距離及碰撞範圍後停止移動
		state_machine.change_state("Attack")
		return
	enemy.velocity = move_dir * enemy.walk_speed # 尚未抵達攻擊距離，繼續靠近玩家
	enemy.play_animation("move", move_dir)

# =====================================================
# 離開追擊狀態
# =====================================================
func exit() -> void:
	enemy.velocity = Vector2.ZERO # 清除殘留移動速度

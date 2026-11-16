extends State

var enemy: Barbarian # 野蠻人角色引用

# =====================================================
# 進入第二階段永久追擊
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	enemy.end_sword_attack() # 清除上一輪攻擊的殘留判定
	enemy.set_contact_enabled(false) # 二階同樣不具有肉身碰撞傷害
	enemy.can_attack = true

# =====================================================
# 二階永久追擊與狂暴攻擊
# =====================================================
func state_physics_update(_delta: float) -> void:
	if enemy.is_dead or enemy.is_transforming:
		return
	var player: Player = enemy.get_combat_target() # 直接從 DataManager 取得玩家
	if not player:
		enemy.velocity = Vector2.ZERO
		enemy.play_animation("idle") # 玩家死亡或不存在時才停止追擊
		return
	var target_vector: Vector2 = enemy.get_combat_vector(player)
	var move_dir: Vector2 = target_vector.normalized()
	if move_dir != Vector2.ZERO:
		enemy.last_facing_vec = move_dir # 在攻擊開始前更新正確的四方向面向
	if enemy.can_start_sword() and enemy.can_reach_with_sword(player, enemy.last_facing_vec):
		enemy.velocity = Vector2.ZERO
		state_machine.change_state("Attack") # 根據二階攻擊距離發動狂暴揮刀
		return
	enemy.velocity = move_dir * enemy.walk_speed # 不受偵測距離及視線限制
	enemy.play_animation("run", move_dir) # 自動播放 berserk_run 對應方向動畫

# =====================================================
# 離開二階追擊狀態
# =====================================================
func exit() -> void:
	enemy.velocity = Vector2.ZERO
	enemy.set_contact_enabled(false)

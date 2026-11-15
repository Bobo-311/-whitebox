extends State

# =====================================================
# 野蠻人第一階段追擊狀態
# 一階依然遵守偵測範圍與視野限制
# =====================================================

@export_group("一階追擊設定")
@export var attack_range: float = 150.0     # 進入揮刀狀態的距離

var enemy: Barbarian

func enter() -> void:
	enemy = character as Barbarian
	if not enemy:
		return
	enemy.play_animation("move", enemy.last_facing_vec)

func state_physics_update(_delta: float) -> void:
	if not enemy or enemy.is_dead:
		return

	# 防止狂暴型態意外進入普通追擊
	if enemy.is_berserk:
		state_machine.change_state("BerserkCharge")
		return

	var player: Player = enemy.get_combat_target()

	# 一階找不到玩家或被地形遮擋時，恢復漫遊
	if not player or not enemy.can_see_player:
		enemy.velocity = Vector2.ZERO
		state_machine.change_state("Move")
		return

	var distance: float = enemy.global_position.distance_to(player.global_position)
	var move_dir: Vector2 = enemy.global_position.direction_to(player.global_position)

	# 先更新面向，再判斷是否攻擊
	if move_dir != Vector2.ZERO:
		enemy.last_facing_vec = move_dir

	if distance <= attack_range and enemy.can_attack:
		enemy.velocity = Vector2.ZERO
		state_machine.change_state("Attack")
		return

	# 一階使用慢速行走動畫
	enemy.velocity = move_dir * enemy.walk_speed
	enemy.play_animation("move", move_dir)

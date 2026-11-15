
extends State

# =====================================================
# 二階狂暴追擊
#
# 不依賴 DetectPlayer
# 不依賴 VisionRay
# 不受普通敵人的偵測範圍限制
#
# 直到玩家死亡、離開場景或野蠻人死亡
# 才停止追擊
# =====================================================

@export_group("狂暴追擊設定")
@export var attack_range: float = 130.0      # 二階進入揮刀狀態的距離

@export var use_berserk_sword_attack: bool = true
# 若二階攻擊素材尚未調整完成，可暫時取消勾選
# 關閉後只進行高速追擊與肉身碰撞傷害

var enemy: Barbarian

# =====================================================
# 進入二階追擊
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	if not enemy:
		return

	enemy.can_attack = true
	enemy.end_sword_attack()
	enemy.set_contact_enabled(true)         # 跑動期間具有肉身碰撞傷害

# =====================================================
# 狂暴追擊物理更新
# =====================================================
func state_physics_update(_delta: float) -> void:
	if not enemy or enemy.is_dead:
		return

	# 直接取得 DataManager 記錄的玩家
	# 無須依靠原本 DetectPlayer 的範圍與視野
	var player: Player = enemy.get_combat_target()

	# 只有玩家不存在或已經死亡時才停止追擊
	if not player:
		enemy.velocity = Vector2.ZERO
		enemy.play_animation("idle", enemy.last_facing_vec)
		return

	var distance: float = enemy.global_position.distance_to(player.global_position)
	var move_dir: Vector2 = enemy.global_position.direction_to(player.global_position)

	if move_dir != Vector2.ZERO:
		enemy.last_facing_vec = move_dir

	# 二階近距離揮刀
	# 若該方向的攻擊動畫還沒準備好，繼續衝撞而不中斷追擊
	if use_berserk_sword_attack and enemy.can_attack:
		if distance <= attack_range:
			if enemy.has_one_shot_animation("attack", enemy.last_facing_vec):
				enemy.velocity = Vector2.ZERO
				state_machine.change_state("Attack")
				return

	# 無視普通偵測距離，持續高速追向玩家
	enemy.velocity = move_dir * enemy.walk_speed
	enemy.play_animation("run", enemy.last_facing_vec)

# =====================================================
# 離開狂暴追擊
# 下一個狀態接管攻擊碰撞的開關
# =====================================================
func exit() -> void:
	if is_instance_valid(enemy):
		enemy.velocity = Vector2.ZERO

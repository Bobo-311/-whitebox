
extends State

# =====================================================
# 野蠻人共用揮刀狀態
#
# 一階：attack_方向
# 二階：berserk_attack_方向
#
# 依動畫影格開啟指定碰撞框
# 不再使用固定秒數猜測揮刀命中時機
# =====================================================

@export_group("一階 - 命中影格")
# Vector2i 的 X = 開始傷害幀、Y = 最後傷害幀
# Godot 的動畫影格索引從 0 開始
@export var stage1_left_up: Vector2i = Vector2i(4, 6)
@export var stage1_right_up: Vector2i = Vector2i(4, 6)
@export var stage1_left_down: Vector2i = Vector2i(4, 6)
@export var stage1_right_down: Vector2i = Vector2i(4, 6)

@export_group("二階 - 命中影格")
@export var stage2_left_up: Vector2i = Vector2i(3, 5)
@export var stage2_right_up: Vector2i = Vector2i(3, 5)
@export var stage2_left_down: Vector2i = Vector2i(3, 5)
@export var stage2_right_down: Vector2i = Vector2i(3, 5)

@export_group("攻擊節奏")
@export_range(0.1, 3.0, 0.05)
var stage1_playback_speed: float = 1.0       # 一階動畫播放倍率

@export_range(0.1, 3.0, 0.05)
var stage2_playback_speed: float = 1.0       # 二階動畫播放倍率

@export_range(0.0, 3.0, 0.05)
var stage1_recovery_time: float = 0.4       # 一階動畫結束後的收招時間

@export_range(0.0, 3.0, 0.05)
var stage2_recovery_time: float = 0.3       # 二階動畫結束後的收招時間

@export var debug_attack_frames: bool = false # 開啟後顯示目前攻擊影格

# =====================================================
# 內部狀態
# =====================================================
var enemy: Barbarian
var sprite: AnimatedSprite2D

var _attack_direction: Vector2 = Vector2.ZERO
var _attack_suffix: String = ""
var _attack_animation: StringName

var _hit_start: int = 0
var _hit_end: int = 0
var _hitbox_open: bool = false

var _animation_done: bool = false
var _recovery_remaining: float = 0.0

# =====================================================
# 進入揮刀狀態
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	if not enemy:
		return

	sprite = enemy.animated_sprite_2d
	enemy.velocity = Vector2.ZERO
	enemy.can_attack = false

	# 揮刀開始時停止殘留的擊退滑行，確保攻擊位置穩定
	if enemy.knockback_component:
		enemy.knockback_component.knockback_force = Vector2.ZERO

	_animation_done = false
	_hitbox_open = false
	_recovery_remaining = 0.0

	# 進入攻擊的瞬間鎖定玩家方向
	# 攻擊進行中不再追蹤玩家轉向，讓玩家有機會閃避
	var player: Player = enemy.get_combat_target()
	_attack_direction = enemy.last_facing_vec
	if player:
		var target_dir: Vector2 = enemy.global_position.direction_to(player.global_position)
		if target_dir != Vector2.ZERO:
			_attack_direction = target_dir

	_attack_suffix = enemy.get_direction_suffix(_attack_direction)
	_attack_animation = enemy.get_action_animation("attack", _attack_direction)

	enemy.begin_sword_attack()               # 初始化揮刀命中紀錄，暫停肉身傷害

	# 避免缺少動畫或動畫設定為 Loop，造成怪物永久卡在 Attack
	if not enemy.has_one_shot_animation("attack", _attack_direction):
		push_warning("攻擊動畫有誤，請確認名稱、幀數與 Loop：" + str(_attack_animation))
		_finish_attack_animation()
		return

	# 取得目前型態和方向對應的命中影格
	var hit_frames: Vector2i = _get_hit_frames()
	var frame_count: int = sprite.sprite_frames.get_frame_count(_attack_animation)

	# 設定超過幀數時限制於合法範圍，避免索引錯誤
	_hit_start = clampi(hit_frames.x, 0, frame_count - 1)
	_hit_end = clampi(hit_frames.y, _hit_start, frame_count - 1)

	if hit_frames.x != _hit_start or hit_frames.y != _hit_end:
		push_warning("攻擊命中幀已限制於動畫有效範圍：" + str(_attack_animation))

	# 每次進入攻擊時才連接訊號，離開狀態時解除
	if not sprite.frame_changed.is_connected(_on_attack_frame_changed):
		sprite.frame_changed.connect(_on_attack_frame_changed)

	if not sprite.animation_finished.is_connected(_on_attack_animation_finished):
		sprite.animation_finished.connect(_on_attack_animation_finished)

	var speed: float = stage2_playback_speed if enemy.is_berserk else stage1_playback_speed
	enemy.play_action("attack", _attack_direction, true, speed)

	# 主動處理第 0 幀，避免命中區間從第 0 幀開始時漏判
	_on_attack_frame_changed()

# =====================================================
# 取得目前型態與方向對應的影格設定
# =====================================================
func _get_hit_frames() -> Vector2i:
	if enemy.is_berserk:
		match _attack_suffix:
			"left_up": return stage2_left_up
			"right_up": return stage2_right_up
			"left_down": return stage2_left_down
			"right_down": return stage2_right_down
	else:
		match _attack_suffix:
			"left_up": return stage1_left_up
			"right_up": return stage1_right_up
			"left_down": return stage1_left_down
			"right_down": return stage1_right_down

	return Vector2i(4, 6)

# =====================================================
# 動畫影格改變事件
# 只有進入指定命中影格才會開啟對應的揮刀碰撞
# =====================================================
func _on_attack_frame_changed() -> void:
	if not enemy or enemy.is_dead or enemy.is_transforming:
		return
	if _animation_done or state_machine.current_state != self:
		return
	if sprite.animation != _attack_animation:
		return

	var frame: int = sprite.frame

	if debug_attack_frames:
		print("【野蠻人攻擊】", sprite.animation, " Frame：", frame)

	var should_open: bool = frame >= _hit_start and frame <= _hit_end

	# 只有碰撞狀態真正改變時才更新，不必每幀重新設定
	if should_open != _hitbox_open:
		_hitbox_open = should_open
		enemy.set_sword_window(_attack_suffix, _hitbox_open)

# =====================================================
# 一次性攻擊動畫播放完畢
# =====================================================
func _on_attack_animation_finished() -> void:
	if state_machine.current_state != self:
		return
	if sprite.animation == _attack_animation:
		_finish_attack_animation()

func _finish_attack_animation() -> void:
	if _animation_done:
		return

	_animation_done = true
	_hitbox_open = false
	enemy.set_sword_window("", false)        # 動畫播完，強制關閉全部揮刀碰撞

	_recovery_remaining = (
		stage2_recovery_time if enemy.is_berserk
		else stage1_recovery_time
	)

	enemy.play_animation("idle", _attack_direction)

# =====================================================
# 物理更新
# 攻擊時不可移動，收招完成後返回對應階段的追擊
# =====================================================
func state_physics_update(delta: float) -> void:
	if not enemy or enemy.is_dead:
		return

	enemy.velocity = Vector2.ZERO

	if not _animation_done:
		# 若播放被意外中斷，立即關閉傷害並進入收招
		if sprite.animation != _attack_animation or not sprite.is_playing():
			_finish_attack_animation()
		return

	_recovery_remaining = maxf(_recovery_remaining - delta, 0.0)

	if _recovery_remaining <= 0.0:
		enemy.can_attack = true
		if enemy.is_berserk:
			state_machine.change_state("BerserkCharge")
		else:
			state_machine.change_state("Chase")

# =====================================================
# 狀態退場
# 受傷、鎖血變身、死亡等情況都能安全中斷攻擊
# =====================================================
func exit() -> void:
	if is_instance_valid(sprite):
		if sprite.frame_changed.is_connected(_on_attack_frame_changed):
			sprite.frame_changed.disconnect(_on_attack_frame_changed)
		if sprite.animation_finished.is_connected(_on_attack_animation_finished):
			sprite.animation_finished.disconnect(_on_attack_animation_finished)

	if not is_instance_valid(enemy):
		return

	enemy.end_sword_attack()
	enemy.set_contact_enabled(true)           # 非變身、死亡狀態才會恢復肉身傷害
	enemy.can_attack = not enemy.is_dead and not enemy.is_transforming
	_hitbox_open = false

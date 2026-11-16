extends State

# =====================================================
# 第一階段武器攻擊影格
# X：傷害開始影格
# Y：傷害結束影格（包含該格）
# =====================================================
@export_group("一階・攻擊影格")
@export var stage1_left_up_frames: Vector2i = Vector2i(4, 6)
@export var stage1_right_up_frames: Vector2i = Vector2i(4, 6)
@export var stage1_left_down_frames: Vector2i = Vector2i(4, 6)
@export var stage1_right_down_frames: Vector2i = Vector2i(4, 6)

@export_group("一階・攻擊節奏")
@export var stage1_playback_speed: float = 1.0 # 動畫播放倍率
@export var stage1_recovery_time: float = 0.4 # 攻擊動畫播完後的休息時間

# =====================================================
# 第二階段武器攻擊影格
# =====================================================
@export_group("二階・攻擊影格")
@export var stage2_left_up_frames: Vector2i = Vector2i(3, 5)
@export var stage2_right_up_frames: Vector2i = Vector2i(3, 5)
@export var stage2_left_down_frames: Vector2i = Vector2i(3, 5)
@export var stage2_right_down_frames: Vector2i = Vector2i(3, 5)

@export_group("二階・攻擊節奏")
@export var stage2_playback_speed: float = 1.0 # 狂暴攻擊動畫播放倍率
@export var stage2_recovery_time: float = 0.3 # 狂暴攻擊後的休息時間

@export_group("開發測試")
@export var debug_attack_frames: bool = false # 是否印出有效傷害影格

# =====================================================
# 內部狀態
# =====================================================
var enemy: Barbarian
var sprite: AnimatedSprite2D
var _attack_dir: Vector2 = Vector2.ZERO # 本次攻擊鎖定方向
var _direction_suffix: String = ""
var _animation_name: String = ""
var _hit_start: int = 0
var _hit_end: int = 0
var _attack_running: bool = false
var _damage_window_open: bool = false
var _is_recovering: bool = false
var _recovery_timer: float = 0.0

# =====================================================
# 進入攻擊狀態
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	sprite = enemy.animated_sprite_2d
	enemy.velocity = Vector2.ZERO
	enemy.knockback_force = Vector2.ZERO
	if enemy.knockback_component:
		enemy.knockback_component.knockback_force = Vector2.ZERO
	enemy.can_attack = false
	enemy.begin_sword_attack() # 關閉肉身傷害並清空前一次命中紀錄
	_attack_dir = enemy.last_facing_vec
	_direction_suffix = enemy.get_direction_suffix(_attack_dir)
	_animation_name = enemy.get_action_animation("attack", _attack_dir)
	_attack_running = false
	_damage_window_open = false
	_is_recovering = false
	if not enemy.has_one_shot_animation("attack", _attack_dir):
		push_warning("攻擊動畫不存在或未關閉 Loop：" + _animation_name)
		_begin_recovery() # 素材不完整時安全取消攻擊
		return
	var frame_range: Vector2i = _get_attack_frame_range()
	var frame_count: int = sprite.sprite_frames.get_frame_count(_animation_name)
	_hit_start = clampi(frame_range.x, 0, frame_count - 1)
	_hit_end = clampi(frame_range.y, _hit_start, frame_count - 1)
	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)
	var playback_speed: float = stage2_playback_speed if enemy.is_berserk else stage1_playback_speed
	_attack_running = true
	enemy.play_action("attack", _attack_dir, true, maxf(playback_speed, 0.01))
	_on_frame_changed() # 檢查第 0 格是否已位於有效傷害範圍

# =====================================================
# 取得對應階段與方向的攻擊影格
# =====================================================
func _get_attack_frame_range() -> Vector2i:
	if enemy.is_berserk:
		match _direction_suffix:
			"left_up":
				return stage2_left_up_frames
			"right_up":
				return stage2_right_up_frames
			"left_down":
				return stage2_left_down_frames
			_:
				return stage2_right_down_frames
	match _direction_suffix:
		"left_up":
			return stage1_left_up_frames
		"right_up":
			return stage1_right_up_frames
		"left_down":
			return stage1_left_down_frames
		_:
			return stage1_right_down_frames

# =====================================================
# 動畫影格驅動傷害判定
# =====================================================
func _on_frame_changed() -> void:
	if not _attack_running or enemy.is_dead:
		return
	if state_machine.current_state != self:
		return
	if sprite.animation != _animation_name:
		return
	var should_open: bool = sprite.frame >= _hit_start and sprite.frame <= _hit_end
	if should_open == _damage_window_open:
		return
	_damage_window_open = should_open
	enemy.set_sword_window(_direction_suffix, should_open)
	if debug_attack_frames:
		print("野蠻人攻擊：", _animation_name, " | Frame：", sprite.frame, " | Hitbox：", should_open)

# =====================================================
# 攻擊動畫播放完成
# =====================================================
func _on_animation_finished() -> void:
	if not _attack_running or state_machine.current_state != self:
		return
	if sprite.animation != _animation_name:
		return
	_begin_recovery()

func _begin_recovery() -> void:
	_attack_running = false
	_damage_window_open = false
	_is_recovering = true
	enemy.set_sword_window("", false) # 動畫播完立即停止武器傷害
	enemy.set_contact_enabled(false) # 後搖期間也不能造成肉身傷害
	enemy.velocity = Vector2.ZERO
	_recovery_timer = stage2_recovery_time if enemy.is_berserk else stage1_recovery_time
	enemy.play_animation("idle", _attack_dir)

# =====================================================
# 攻擊恢復計時
# =====================================================
func state_physics_update(delta: float) -> void:
	if not _is_recovering:
		return
	_recovery_timer -= delta
	if _recovery_timer <= 0.0:
		if enemy.is_berserk:
			state_machine.change_state("BerserkCharge")
		else:
			state_machine.change_state("Chase")

# =====================================================
# 安全退場
# =====================================================
func exit() -> void:
	_attack_running = false
	_damage_window_open = false
	_is_recovering = false
	if is_instance_valid(sprite):
		if sprite.frame_changed.is_connected(_on_frame_changed):
			sprite.frame_changed.disconnect(_on_frame_changed)
		if sprite.animation_finished.is_connected(_on_animation_finished):
			sprite.animation_finished.disconnect(_on_animation_finished)
	enemy.end_sword_attack()
	enemy.set_contact_enabled(false) # 攻擊結束後禁止自動恢復肉身傷害
	enemy.can_attack = not enemy.is_dead and not enemy.is_transforming

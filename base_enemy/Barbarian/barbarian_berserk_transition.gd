
extends State

# =====================================================
# 野蠻人鎖血變身狀態
# 變身動畫完整播放後，才正式進入狂暴追擊
# =====================================================

@export_group("狂暴變身設定")
@export_range(0.1, 3.0, 0.05)
var transition_playback_speed: float = 1.0  # 變身動畫播放倍率

@export_range(0.1, 10.0, 0.1)
var fallback_duration: float = 2.0         # 動畫缺失或設定異常時的備用演出時間

@export var transition_camera_shake: float = 20.0 # 變身鏡頭震動強度

var enemy: Barbarian
var sprite: AnimatedSprite2D
var _transition_animation: StringName

var _animation_done: bool = false
var _using_fallback: bool = false
var _fallback_timer: float = 0.0

# =====================================================
# 進入變身演出
# =====================================================
func enter() -> void:
	enemy = character as Barbarian
	if not enemy:
		return

	sprite = enemy.animated_sprite_2d
	enemy.velocity = Vector2.ZERO
	enemy.can_attack = false
	enemy.set_contact_enabled(false)
	enemy.end_sword_attack()

	# 清除殘留擊退，避免變身時角色持續滑行
	if enemy.knockback_component:
		enemy.knockback_component.knockback_force = Vector2.ZERO

	_animation_done = false
	_using_fallback = false
	_fallback_timer = fallback_duration

	_transition_animation = enemy.get_action_animation("transform", enemy.last_facing_vec)

	# 確認正式變身動畫存在，而且沒有設定循環
	if enemy.has_one_shot_animation("transform", enemy.last_facing_vec):
		if not sprite.animation_finished.is_connected(_on_transition_finished):
			sprite.animation_finished.connect(_on_transition_finished)

		enemy.play_action(
			"transform",
			enemy.last_facing_vec,
			true,
			transition_playback_speed
		)
	else:
		# 即使動畫組素材尚未完成，也不會卡在變身狀態
		_using_fallback = true
		enemy.play_animation("idle")
		push_warning("變身動畫設定有誤，使用備用演出時間：" + str(_transition_animation))

	var camera = enemy.get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(transition_camera_shake)

# =====================================================
# 正式變身動畫播放結束
# =====================================================
func _on_transition_finished() -> void:
	if state_machine.current_state != self:
		return
	if sprite.animation == _transition_animation:
		_animation_done = true

# =====================================================
# 演出期間鎖定移動
# 動畫完成後交回野蠻人控制器
# =====================================================
func state_physics_update(delta: float) -> void:
	if not enemy or enemy.is_dead:
		return

	enemy.velocity = Vector2.ZERO

	if _using_fallback:
		_fallback_timer -= delta
		if _fallback_timer <= 0.0:
			_animation_done = true
	else:
		# 正常動畫被外部意外替換時，使用備用計時避免卡死
		if sprite.animation != _transition_animation:
			_using_fallback = true
			_fallback_timer = fallback_duration
		elif not sprite.is_playing():
			_animation_done = true

	if _animation_done:
		enemy.finish_berserk_transition()

# =====================================================
# 離開變身狀態
# =====================================================
func exit() -> void:
	if is_instance_valid(sprite):
		if sprite.animation_finished.is_connected(_on_transition_finished):
			sprite.animation_finished.disconnect(_on_transition_finished)
	

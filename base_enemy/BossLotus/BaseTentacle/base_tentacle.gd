
extends StaticBody2D
class_name Tentacle

# ============================================================
# 淵獄蓮華 - 觸手共用腳本 v5.2
#
# 支援：
# 1. 一階普通觸手
# 2. 二階狂暴紅色觸手
# 3. 二階假動作觸手
#
# 普通觸手：
# 出土 -> 預警 -> 砸擊 -> 實體化 -> 收回
#
# 假觸手：
# 出土 -> 預警 -> 假動作 -> 收回
#
# 只有真正被玩家擊殺的觸手才提供墨水
# ============================================================


# ============================================================
# 1. 方向設定
# ============================================================

@export_group("觸手 - 方向設定")

@export_enum(
	"right_up",
	"right_down",
	"left_up",
	"left_down"
)
var facing_dir: String = "right_up"


# ============================================================
# 2. 生命數值
# ============================================================

@export_group("觸手 - 生命數值")

@export_range(1, 500, 1)
var max_hp: int = 30

var current_hp: int = 0

@export_range(0.1, 30.0, 0.1)
var lifespan: float = 11.0


# ============================================================
# 3. 攻擊數值
# ============================================================

@export_group("觸手 - 攻擊數值")

@export_range(0, 100, 1)
var smash_damage: int = 20

# 沿用原本攻擊動畫第 6 幀的命中判定
@export_range(0, 100, 1)
var attack_hit_frame: int = 6

@export_range(0.01, 2.0, 0.01)
var hitbox_active_time: float = 0.15

@export_range(0.1, 5.0, 0.05)
var telegraph_time: float = 1.0

@export_range(0.0, 50.0, 0.5)
var smash_camera_shake: float = 15.0


# ============================================================
# 4. 墨水獎勵
# ============================================================

@export_group("觸手 - 資源獎勵")

@export_range(0.0, 200.0, 1.0)
var ink_reward: float = 30.0


# ============================================================
# 5. 紅影預警數值
# ============================================================

@export_group("觸手 - 預警效果")

@export_range(0.0, 1.0, 0.05)
var warning_min_alpha: float = 0.2

@export_range(0.0, 1.0, 0.05)
var warning_max_alpha: float = 0.7

@export_range(0.02, 0.5, 0.01)
var warning_blink_duration: float = 0.1


# ============================================================
# 6. 外觀設定
# ============================================================

@export_group("觸手 - 外觀效果")

# 第二階段觸手顏色
@export var enraged_color: Color = Color(1.0, 0.25, 0.25)

@export_range(0.0, 0.2, 0.01)
var breathing_amount: float = 0.03

@export_range(0.1, 5.0, 0.1)
var breathing_half_cycle: float = 1.2


# ============================================================
# 7. 假觸手效果
#
# 假觸手不使用 attack 動畫砸地
# 使用縮放動作模擬突然蓄力
#
# 不需要新增美術素材
# ============================================================

@export_group("觸手 - 假動作效果")

# 假動作突然膨脹的倍率
@export_range(1.0, 1.5, 0.05)
var fake_pulse_scale: float = 1.15


# ============================================================
# 8. 內部狀態
# ============================================================

var is_active: bool = false
var is_dead: bool = false

var can_deal_damage: bool = false
var attack_hit_done: bool = false

# 假觸手模式
var is_fake: bool = false

# 假觸手預警後，短暫震動的時間
var fake_shout_duration: float = 0.2

# 防止同一次砸擊對同一個 Hurtbox 重複傷害
var damaged_areas: Array[Area2D] = []

# Sprite 基準
var original_sprite_scale: Vector2 = Vector2.ONE
var original_sprite_color: Color = Color.WHITE
var current_base_color: Color = Color.WHITE

# 紅色預警
var warning_indicator: Sprite2D = null

# 各種視覺 Tween
var warning_tween: Tween
var breathing_tween: Tween
var hit_flash_tween: Tween
var fake_tween: Tween


# ============================================================
# 9. 節點參照
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# 實體阻擋碰撞
@onready var wall_shape: CollisionShape2D = $CollisionShape2D

# 傷害玩家的判定區
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = (
	$Hitbox/CollisionShape2D
)

# 被玩家攻擊的判定區
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_shape: CollisionShape2D = (
	$Hurtbox/CollisionShape2D
)


# ============================================================
# 10. 三個獨立計時器
#
# hitbox_timer：
# 傷害判定窗口
#
# warning_timer：
# 紅影預警時間
#
# retract_timer：
# 自然收回倒數
# ============================================================

var hitbox_timer: Timer
var warning_timer: Timer
var retract_timer: Timer


# ============================================================
# 11. 初始化
# ============================================================

func _ready() -> void:

	current_hp = max_hp

	original_sprite_scale = sprite.scale
	original_sprite_color = sprite.modulate
	current_base_color = original_sprite_color

	# 初始時全部碰撞關閉
	wall_shape.set_deferred("disabled", true)
	hitbox_shape.set_deferred("disabled", true)
	hurtbox_shape.set_deferred("disabled", true)

	hitbox.monitoring = false
	hurtbox.monitoring = false
	hurtbox.monitorable = true

	# 連接動畫訊號
	if not sprite.frame_changed.is_connected(
		_on_sprite_frame_changed
	):
		sprite.frame_changed.connect(
			_on_sprite_frame_changed
		)

	if not sprite.animation_finished.is_connected(
		_on_animation_finished
	):
		sprite.animation_finished.connect(
			_on_animation_finished
		)

	# 砸擊傷害 Timer
	hitbox_timer = Timer.new()
	hitbox_timer.one_shot = true
	add_child(hitbox_timer)
	hitbox_timer.timeout.connect(_on_hitbox_timeout)

	# 預警 Timer
	warning_timer = Timer.new()
	warning_timer.one_shot = true
	add_child(warning_timer)
	warning_timer.timeout.connect(_on_warning_timeout)

	# 壽命 Timer
	retract_timer = Timer.new()
	retract_timer.one_shot = true
	add_child(retract_timer)
	retract_timer.timeout.connect(_on_lifespan_timeout)

	# 攻擊碰撞訊號
	if not hitbox.area_entered.is_connected(
		_on_hitbox_area_entered
	):
		hitbox.area_entered.connect(
			_on_hitbox_area_entered
		)

	# 一開始播放出土動畫
	_play_anim("spawn")


# ============================================================
# 12. 二階外觀
#
# 普通觸手：原始顏色
# 狂暴觸手：血紅色
# ============================================================

func set_enraged(enabled: bool) -> void:

	if enabled:
		current_base_color = enraged_color
	else:
		current_base_color = original_sprite_color

	sprite.modulate = current_base_color


# ============================================================
# 13. 獨立壽命
#
# Boss 傳入的是從現在開始剩餘幾秒
# 倒數結束後呼叫 retract()
# ============================================================

func start_lifespan_countdown(
	seconds_from_now: float
) -> void:

	if is_dead:
		return

	lifespan = maxf(seconds_from_now, 0.0)

	if lifespan <= 0.0:
		retract()
		return

	retract_timer.start(lifespan)


func _on_lifespan_timeout() -> void:

	if is_dead:
		return

	print("【觸手】", name, " 壽命結束")

	# 自然收回不補墨水
	retract()


# ============================================================
# 14. 正常觸手攻擊入口
#
# 一階與二階 A/B 的真觸手都使用這裡
# ============================================================

func execute_smash() -> void:

	if is_dead or is_active:
		return

	if not warning_timer.is_stopped():
		return

	# 標記為真正攻擊
	is_fake = false

	# 顯示紅色預警
	_create_red_silhouette_phantom()

	# 預警倒數
	warning_timer.start(
		maxf(telegraph_time, 0.01)
	)


# ============================================================
# 15. 假觸手攻擊入口
#
# 流程：
# 1. 顯示紅影
# 2. 播放出土動畫
# 3. 預警結束
# 4. 假裝蓄力
# 5. 直接收回
#
# 不會執行 _perform_actual_smash()
# 不啟用任何傷害判定
# ============================================================

func execute_fake_smash(
	shout_duration: float = 0.2
) -> void:

	if is_dead or is_active:
		return

	if not warning_timer.is_stopped():
		return

	is_fake = true

	fake_shout_duration = maxf(
		shout_duration,
		0.05
	)

	# 利用現有攻擊幀產生紅影
	_create_red_silhouette_phantom()

	# 等待假動作預警結束
	warning_timer.start(
		maxf(telegraph_time, 0.01)
	)


# ============================================================
# 16. 預警結束分流
#
# 真觸手 -> 真正砸下
# 假觸手 -> 假蓄力後收回
# ============================================================

func _on_warning_timeout() -> void:

	if is_dead:
		return

	if is_fake:
		_perform_fake_shout()
	else:
		_perform_actual_smash()


# ============================================================
# 17. 假動作演出
#
# 利用 Tween 做一次快速膨脹
# 模擬觸手正準備攻擊
#
# 假動作完成後直接 retract()
#
# 不播放 attack 動畫
# 因為 attack 的第 6 幀會啟用傷害
# ============================================================

func _perform_fake_shout() -> void:

	if is_dead or not is_fake:
		return

	_clear_warning()

	# 先停止原本出土動畫
	# 避免其他動畫同時修改 Sprite
	sprite.stop()

	if fake_tween and fake_tween.is_running():
		fake_tween.kill()

	fake_tween = create_tween()

	var half_duration: float = fake_shout_duration / 2.0

	# 瞬間膨脹，看起來像即將砸下
	fake_tween.tween_property(
		sprite,
		"scale",
		original_sprite_scale * fake_pulse_scale,
		half_duration
	).set_trans(Tween.TRANS_SINE)

	# 再縮回原本大小
	fake_tween.tween_property(
		sprite,
		"scale",
		original_sprite_scale,
		half_duration
	).set_trans(Tween.TRANS_SINE)

	# 假動作結束後開始收回
	fake_tween.tween_callback(retract)

	print("【假觸手】", name, " 假動作，不造成傷害")


# ============================================================
# 18. 真正開始砸擊
#
# 只處理真正觸手
# 假觸手絕對不會進入這個流程
# ============================================================

func _perform_actual_smash() -> void:

	if is_dead or is_active or is_fake:
		return

	_clear_warning()

	attack_hit_done = false

	_play_anim("attack")


# ============================================================
# 19. 建立純紅預警剪影
#
# 使用 attack 第 6 幀圖片
# 保留原圖 Alpha 輪廓
# 將畫面變成純紅色
#
# 不需要另外製作紅影素材
# ============================================================

func _create_red_silhouette_phantom() -> void:

	_clear_warning()

	var anim_name: String = "attack_" + facing_dir

	if not sprite.sprite_frames.has_animation(anim_name):

		var fallback_dir: String = "right"

		if facing_dir.begins_with("left"):
			fallback_dir = "left"

		anim_name = "attack_" + fallback_dir

	if not sprite.sprite_frames.has_animation(anim_name):

		push_warning(
			"觸手缺少攻擊預警動畫：" + anim_name
		)
		return

	var frame_count: int = (
		sprite.sprite_frames.get_frame_count(anim_name)
	)

	if frame_count <= attack_hit_frame:

		push_warning(
			"觸手命中幀超出動畫長度：" + anim_name
		)
		return

	var hit_texture: Texture2D = (
		sprite.sprite_frames.get_frame_texture(
			anim_name,
			attack_hit_frame
		)
	)

	if hit_texture == null:
		return

	warning_indicator = Sprite2D.new()

	warning_indicator.texture = hit_texture

	# 與原本動畫的 Transform 對齊
	warning_indicator.position = sprite.position
	warning_indicator.rotation = sprite.rotation
	warning_indicator.scale = sprite.scale
	warning_indicator.offset = sprite.offset
	warning_indicator.centered = sprite.centered
	warning_indicator.flip_h = sprite.flip_h
	warning_indicator.flip_v = sprite.flip_v

	# 純紅輪廓 Shader
	var shader := Shader.new()

	shader.code = """
shader_type canvas_item;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(
		1.0,
		0.0,
		0.0,
		tex_color.a * COLOR.a
	);
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader

	warning_indicator.material = material

	# 放在觸手圖片後方
	add_child(warning_indicator)
	move_child(warning_indicator, 0)

	# 預警閃爍
	var blink_duration: float = maxf(
		warning_blink_duration,
		0.01
	)

	var blink_count: int = maxi(
		1,
		int(
			ceil(
				telegraph_time
				/ (blink_duration * 2.0)
			)
		)
	)

	warning_indicator.modulate.a = warning_min_alpha

	warning_tween = create_tween().set_loops(blink_count)

	warning_tween.tween_property(
		warning_indicator,
		"modulate:a",
		warning_max_alpha,
		blink_duration
	).set_trans(Tween.TRANS_SINE)

	warning_tween.tween_property(
		warning_indicator,
		"modulate:a",
		warning_min_alpha,
		blink_duration
	).set_trans(Tween.TRANS_SINE)


# ============================================================
# 20. 清理預警
# ============================================================

func _clear_warning() -> void:

	if warning_tween and warning_tween.is_running():
		warning_tween.kill()

	warning_tween = null

	if is_instance_valid(warning_indicator):
		warning_indicator.queue_free()

	warning_indicator = null


# ============================================================
# 21. 真觸手動畫命中幀
#
# 播放到第 6 幀時才真正實體化
# ============================================================

func _on_sprite_frame_changed() -> void:

	if is_dead or is_fake:
		return

	if not sprite.animation.begins_with("attack"):
		return

	if (
		sprite.frame >= attack_hit_frame
		and not attack_hit_done
	):

		attack_hit_done = true

		_activate_barricade_and_damage()


# ============================================================
# 22. 真觸手砸下後實體化
#
# 啟動：
# 1. 阻擋玩家的實體碰撞
# 2. 玩家可攻擊的 Hurtbox
# 3. 短暫砸擊傷害 Hitbox
# ============================================================

func _activate_barricade_and_damage() -> void:

	if is_dead or is_active or is_fake:
		return

	is_active = true
	damaged_areas.clear()

	# 開啟實體障礙
	wall_shape.set_deferred("disabled", false)

	# 開啟受傷判定
	hurtbox_shape.set_deferred("disabled", false)
	hurtbox.monitoring = true

	# 開啟砸擊傷害
	hitbox_shape.set_deferred("disabled", false)
	hitbox.monitoring = true

	can_deal_damage = true

	hitbox_timer.start(
		maxf(hitbox_active_time, 0.01)
	)

	# 砸地震動
	var camera = get_tree().get_first_node_in_group("camera")

	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(smash_camera_shake)

	_start_breathing_effect()


# ============================================================
# 23. 砸擊傷害窗口結束
#
# 關閉傷害 Hitbox
# 保留障礙碰撞與可攻擊 Hurtbox
# ============================================================

func _on_hitbox_timeout() -> void:

	if is_dead:
		return

	hitbox_shape.set_deferred("disabled", true)
	hitbox.monitoring = false

	can_deal_damage = false


# ============================================================
# 24. 砸擊命中玩家
#
# 同一次砸擊對同一個 Hurtbox 只傷害一次
# ============================================================

func _on_hitbox_area_entered(area: Area2D) -> void:

	if is_dead or is_fake or not can_deal_damage:
		return

	if not area.has_method("take_damage"):
		return

	if damaged_areas.has(area):
		return

	damaged_areas.append(area)

	area.take_damage(smash_damage)


# ============================================================
# 25. 觸手受傷
#
# 真觸手可以近戰擊殺
# 也可以接受遠程傷害
#
# 只有 HP 歸零才給墨水
#
# 假觸手不接受傷害、不提供墨水
# ============================================================

func take_damage(
	amount: float,
	_hit_position: Vector2 = Vector2.ZERO,
	_hit_direction: Vector2 = Vector2.ZERO,
	_is_melee: bool = false,
	_extra_knockback: float = 1.0
) -> void:

	if is_dead or not is_active or is_fake:
		return

	if amount <= 0.0:
		return

	current_hp -= int(amount)

	if current_hp <= 0:

		current_hp = 0

		# 玩家成功擊殺，回復墨水
		_restore_player_ink()

		# 接著觸手退場
		retract()

	else:
		_play_hit_flash()


# ============================================================
# 26. 擊殺獎勵
#
# 只有真正被擊殺才執行
# 自然收回不會呼叫
# ============================================================

func _restore_player_ink() -> void:

	if is_fake:
		return

	var player = get_tree().get_first_node_in_group(
		"Player"
	)

	if player == null:
		return

	if player.has_method("restore_ink"):
		player.restore_ink(ink_reward)

	print(
		"【觸手擊殺】",
		name,
		" 回復墨水：",
		ink_reward
	)


# ============================================================
# 27. 觸手收回
#
# 適用：
# 1. 玩家擊殺
# 2. 自然壽命結束
# 3. 假動作結束
# 4. Boss 轉階
# 5. Boss 死亡
#
# 不會自行給予墨水
# ============================================================

func retract() -> void:

	if is_dead:
		return

	is_dead = true
	is_active = false
	can_deal_damage = false

	# 停止所有 Timer
	if warning_timer:
		warning_timer.stop()

	if retract_timer:
		retract_timer.stop()

	if hitbox_timer:
		hitbox_timer.stop()

	# 停止其他視覺效果
	if breathing_tween and breathing_tween.is_running():
		breathing_tween.kill()

	if hit_flash_tween and hit_flash_tween.is_running():
		hit_flash_tween.kill()

	if fake_tween and fake_tween.is_running():
		fake_tween.kill()

	# 關閉所有碰撞
	wall_shape.set_deferred("disabled", true)
	hitbox_shape.set_deferred("disabled", true)
	hurtbox_shape.set_deferred("disabled", true)

	hitbox.monitoring = false
	hurtbox.monitoring = false

	damaged_areas.clear()

	# 清除預警
	_clear_warning()

	# 恢復原本 Sprite
	sprite.scale = original_sprite_scale
	sprite.modulate = current_base_color

	# 播放縮回動畫
	var has_die_animation: bool = _play_anim("die")

	if not has_die_animation:
		queue_free()


# ============================================================
# 28. 保留舊版 _die() 相容入口
#
# 若其他腳本仍有呼叫 _die()
# 不會造成函式不存在
# ============================================================

func _die() -> void:
	retract()


# ============================================================
# 29. 動畫結束
# ============================================================

func _on_animation_finished() -> void:

	# 退場動畫播放完畢
	if is_dead:

		if sprite.animation.begins_with("die"):
			queue_free()

		return

	# 假觸手不能啟動攻擊
	if is_fake:
		return

	# 原本攻擊動畫的保險機制
	if sprite.animation.begins_with("attack"):

		if not attack_hit_done:

			attack_hit_done = true

			_activate_barricade_and_damage()


# ============================================================
# 30. 受擊閃爍
# ============================================================

func _play_hit_flash() -> void:

	if hit_flash_tween and hit_flash_tween.is_running():
		hit_flash_tween.kill()

	hit_flash_tween = create_tween()

	hit_flash_tween.tween_property(
		sprite,
		"modulate",
		Color(1.0, 0.5, 0.5),
		0.08
	)

	hit_flash_tween.tween_property(
		sprite,
		"modulate",
		current_base_color,
		0.08
	)


# ============================================================
# 31. 播放方向動畫
#
# 例如：
# attack + left_up = attack_left_up
#
# 找不到完整方向時，嘗試左右方向備用動畫
# ============================================================

func _play_anim(action: String) -> bool:

	var animation_name: String = (
		action + "_" + facing_dir
	)

	if sprite.sprite_frames.has_animation(animation_name):

		sprite.play(animation_name)
		return true

	var fallback_dir: String = "right"

	if facing_dir.begins_with("left"):
		fallback_dir = "left"

	var fallback_animation: String = (
		action + "_" + fallback_dir
	)

	if sprite.sprite_frames.has_animation(fallback_animation):

		sprite.play(fallback_animation)
		return true

	push_warning(
		"觸手缺少動畫："
		+ animation_name
		+ " / "
		+ fallback_animation
	)

	return false


# ============================================================
# 32. 觸手呼吸效果
#
# 只修改 Sprite Scale
# 不移動觸手實體碰撞
#
# Tween 由 Node 建立並綁定節點生命週期
# 收回時會主動停止
# ============================================================

func _start_breathing_effect() -> void:

	if breathing_tween and breathing_tween.is_running():
		breathing_tween.kill()

	var stretch_scale := (
		original_sprite_scale
		* Vector2(
			1.0 - breathing_amount,
			1.0 + breathing_amount
		)
	)

	breathing_tween = create_tween().set_loops()

	breathing_tween.tween_property(
		sprite,
		"scale",
		stretch_scale,
		breathing_half_cycle
	).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)

	breathing_tween.tween_property(
		sprite,
		"scale",
		original_sprite_scale,
		breathing_half_cycle
	).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)

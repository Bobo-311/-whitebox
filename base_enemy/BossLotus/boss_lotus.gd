
extends Node2D

# ============================================================
# 淵獄蓮華 - Boss 主控制器 v5.3
#
# 本次修正：
# 1. 雷射動畫與實際攻擊時間同步
# 2. laser_start 自動符合預警秒數
# 3. 雷射停止後立刻播放 laser_end
# 4. laser_end 結束後自動恢復 pant
# 5. 受傷不再打亂雷射動畫
#
# 保留：
# 一階四觸手、螺旋彈幕、二階 A/B 模式、
# 墨水機制、轉階、Boss 傷害與死亡處理
# ============================================================


# ============================================================
# 1. Boss 基本數值
# ============================================================

@export_group("Boss - 核心數值")

@export_range(1, 10000, 1)
var max_hp: int = 500

@export_range(1, 10000, 1)
var phase_2_threshold: int = 250

@export var boss_display_name: String = "淵獄蓮華"

var current_hp: int = 0


# ============================================================
# 2. 第一階段 - 觸手數值
# ============================================================

@export_group("一階 - 觸手數值")

@export_range(1, 500, 1)
var phase1_tentacle_hp: int = 30

@export_range(0, 100, 1)
var phase1_smash_damage: int = 20

@export_range(0.0, 200.0, 1.0)
var phase1_ink_reward: float = 30.0

@export_range(0.1, 5.0, 0.05)
var phase1_telegraph_time: float = 1.0


# ============================================================
# 3. 第一階段 - 隨機收回
# 每輪從四種時間中洗牌分配
# ============================================================

@export_group("一階 - 觸手收回時間")

@export_range(0.1, 30.0, 0.1)
var retract_time_1: float = 4.0

@export_range(0.1, 30.0, 0.1)
var retract_time_2: float = 7.0

@export_range(0.1, 30.0, 0.1)
var retract_time_3: float = 9.0

@export_range(0.1, 30.0, 0.1)
var retract_time_4: float = 11.0


# ============================================================
# 4. 第一階段 - 攻擊時間軸
# 預設一輪 15 秒
# ============================================================

@export_group("一階 - 攻擊時間軸")

@export_range(0.1, 10.0, 0.1)
var phase1_start_delay: float = 1.0

@export_range(0.1, 15.0, 0.1)
var phase1_first_spiral: float = 4.0

@export_range(0.1, 10.0, 0.1)
var phase1_middle_rest: float = 2.0

@export_range(0.1, 15.0, 0.1)
var phase1_second_spiral: float = 4.0

@export_range(0.1, 5.0, 0.1)
var phase1_retract_wait: float = 1.0

@export_range(0.1, 10.0, 0.1)
var phase1_safe_rest: float = 3.0


# ============================================================
# 5. 第二階段 - 基本數值
# ============================================================

@export_group("二階 - 基本數值")

@export_range(1, 500, 1)
var phase2_tentacle_hp: int = 45

@export_range(0, 100, 1)
var phase2_smash_damage: int = 20

@export_range(0.0, 200.0, 1.0)
var phase2_ink_reward: float = 30.0

@export_range(8.0, 30.0, 0.5)
var phase2_round_duration: float = 12.0

@export_range(1.0, 30.0, 0.1)
var phase2_final_retract_at: float = 11.5


# ============================================================
# 6. 第二階段 - 隨機模式
# ============================================================

@export_group("二階 - 模式隨機設定")

@export var phase2_first_round_force_a: bool = true

@export var phase2_prevent_consecutive_b: bool = true

@export_range(0.0, 1.0, 0.05)
var phase2_pattern_b_chance: float = 0.4


# ============================================================
# 7. 第二階段 A - 極速血牢
# ============================================================

@export_group("二階 A - 極速血牢")

@export_range(0.1, 3.0, 0.05)
var phase2_a_telegraph: float = 0.7

@export_range(0.1, 10.0, 0.1)
var phase2_a_short1_min: float = 2.0

@export_range(0.1, 10.0, 0.1)
var phase2_a_short1_max: float = 3.0

@export_range(0.1, 10.0, 0.1)
var phase2_a_short2_min: float = 4.0

@export_range(0.1, 10.0, 0.1)
var phase2_a_short2_max: float = 5.0

@export_range(0.0, 10.0, 0.1)
var phase2_a_laser1_at: float = 0.5

@export_range(0.0, 20.0, 0.1)
var phase2_a_laser2_at: float = 5.0

@export_range(0.1, 10.0, 0.1)
var phase2_a_laser_damage_duration: float = 2.5


# ============================================================
# 8. 第二階段 B - 虛實雙殺
# ============================================================

@export_group("二階 B - 虛實雙殺")

@export_range(0.1, 3.0, 0.05)
var phase2_b_fake_warning: float = 0.5

@export_range(0.05, 1.0, 0.05)
var phase2_b_fake_shout: float = 0.2

@export_range(0.0, 2.0, 0.05)
var phase2_b_gap_after_fake: float = 0.3

@export_range(0.1, 3.0, 0.05)
var phase2_b_real_warning: float = 0.75

@export_range(0.0, 20.0, 0.1)
var phase2_b_laser_at: float = 2.5

@export_range(0.1, 10.0, 0.1)
var phase2_b_laser_damage_duration: float = 2.5


# ============================================================
# 9. 雷射 - 動畫同步設定【本次新增】
#
# 核心設計：
# 攻擊時間軸是唯一的戰鬥時間依據
# Sprite 動畫配合時間軸播放
#
# laser_start：
# 自動配合預警時間，不另外設定速度
#
# laser_loop：
# 真正雷射攻擊期間持續播放
#
# laser_end：
# 雷射停止瞬間播放，時間可由 Inspector 調整
# ============================================================

@export_group("雷射 - 動畫同步")

# 雷射開始預警的持續時間
# 同時決定 laser_start 應播放多久
@export_range(0.1, 3.0, 0.05)
var phase2_laser_warning_duration: float = 0.5

# 雷射結束動畫目標長度
# 例如原動畫長 1 秒，設定 0.35 秒會自動加速
@export_range(0.05, 2.0, 0.05)
var laser_end_visual_duration: float = 0.35


# ============================================================
# 10. 轉階演出
# ============================================================

@export_group("Boss - 轉階演出")

@export_range(0.5, 10.0, 0.1)
var transition_duration: float = 3.0

@export_range(0.1, 10.0, 0.1)
var transition_burst_time: float = 2.5

@export var phase_2_color: Color = Color(1.0, 0.2, 0.2)

@export_range(1.0, 2.0, 0.05)
var phase2_scale_multiplier: float = 1.1

@export_range(0.0, 50.0, 1.0)
var transition_camera_shake: float = 30.0

@export_range(0.0, 30.0, 1.0)
var transition_sprite_shake: float = 10.0

@export_range(0.01, 0.2, 0.01)
var transition_shake_step: float = 0.05


# ============================================================
# 11. 四種觸手場景
# ============================================================

@export_group("觸手 - 場景資源")

@export var tentacle_left_top: PackedScene
@export var tentacle_left_down: PackedScene
@export var tentacle_right_top: PackedScene
@export var tentacle_right_down: PackedScene


# ============================================================
# 12. 內部狀態
# ============================================================

var current_phase: int = 1
var is_transitioning: bool = false
var is_dead: bool = false

var current_active_tentacles: Array[Tentacle] = []

var _phase_timeline: Tween
var _hit_tween: Tween

var _transition_color_tween: Tween
var _transition_shake_tween: Tween

var original_sprite_scale: Vector2 = Vector2.ONE
var original_sprite_pos: Vector2 = Vector2.ZERO

# 第二階段輪次
var _phase2_round_count: int = 0
var _last_phase2_pattern: String = ""

# B 模式角落分配
var _phase2_b_corner_order: Array[int] = []

# 避免爆氣效果重複執行
var _transition_burst_done: bool = false


# ============================================================
# 13. 雷射動畫狀態【本次新增】
#
# _laser_sequence_active：
# 從雷射開始預警到雷射停止，都維持 true
#
# _laser_visual_tween：
# 專門控制雷射動畫切換
# 與 Boss 攻擊時間軸互相獨立
#
# 只控制畫面，不控制實際傷害
# ============================================================

var _laser_sequence_active: bool = false

var _laser_visual_tween: Tween


# ============================================================
# 14. 節點參照
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var spawners = $Spawners
@onready var laser_weapon = $LaserWeapon
@onready var boss_ui = $BossUI


# ============================================================
# 15. 初始化
# ============================================================

func _ready() -> void:

	current_hp = max_hp
	current_phase = 1

	is_dead = false
	is_transitioning = false

	original_sprite_scale = sprite.scale
	original_sprite_pos = sprite.position

	sprite.play("idle")

	if boss_ui:
		boss_ui.init_boss(boss_display_name, max_hp)

	# 本版雷射動畫改由獨立 Tween 控制
	# 不再依賴 animation_finished 才切換
	_play_phase_1_timeline()


# ============================================================
# 16. 第一階段 - 15 秒時間軸
# ============================================================

func _play_phase_1_timeline() -> void:

	if is_dead or is_transitioning:
		return

	current_phase = 1

	_stop_phase_timeline()

	_phase_timeline = create_tween()

	# 第 0 秒：四根觸手
	_phase_timeline.tween_callback(trigger_vine_obstacles)

	# 順時針彈幕
	_phase_timeline.tween_interval(phase1_start_delay)

	_phase_timeline.tween_callback(
		start_spiral_bullets.bind(true)
	)

	_phase_timeline.tween_interval(phase1_first_spiral)
	_phase_timeline.tween_callback(stop_bullets)

	# 中間喘息
	_phase_timeline.tween_interval(phase1_middle_rest)

	# 逆時針彈幕
	_phase_timeline.tween_callback(
		start_spiral_bullets.bind(false)
	)

	_phase_timeline.tween_interval(phase1_second_spiral)
	_phase_timeline.tween_callback(stop_bullets)

	# 清場
	_phase_timeline.tween_callback(
		_force_retract_all_tentacles
	)

	# 退場及休息
	_phase_timeline.tween_interval(phase1_retract_wait)
	_phase_timeline.tween_interval(phase1_safe_rest)

	_phase_timeline.tween_callback(
		_play_phase_1_timeline
	)


# ============================================================
# 17. 第二階段 - 模式選擇
# ============================================================

func _play_phase_2_timeline() -> void:

	if is_dead or is_transitioning:
		return

	current_phase = 2

	_stop_phase_timeline()

	# 下一輪前清場
	_force_retract_all_tentacles()

	_phase_timeline = create_tween()

	var pattern: String = _choose_phase2_pattern()

	print(
		"【淵獄蓮華】二階第 ",
		_phase2_round_count,
		" 輪，模式：",
		pattern
	)

	if pattern == "A":
		_build_phase2_a_timeline()
	else:
		_build_phase2_b_timeline()


func _choose_phase2_pattern() -> String:

	_phase2_round_count += 1

	var chosen: String = "A"

	if (
		phase2_first_round_force_a
		and _phase2_round_count == 1
	):
		chosen = "A"

	elif (
		phase2_prevent_consecutive_b
		and _last_phase2_pattern == "B"
	):
		chosen = "A"

	elif randf() < phase2_pattern_b_chance:
		chosen = "B"

	_last_phase2_pattern = chosen

	return chosen


# ============================================================
# 18. 二階 A：極速血牢
#
# 預設：
# 0.0：觸手出現
# 0.5：第一道雷射開始預警
# 1.0：雷射生效
# 3.5：雷射停止，立刻播放收招動畫
# 5.0：第二道雷射預警
# 5.5：雷射生效
# 8.0：雷射停止
# 11.5：觸手清場
# 12.0：下一輪
# ============================================================

func _build_phase2_a_timeline() -> void:

	var first_at: float = phase2_a_laser1_at

	var first_end: float = (
		first_at
		+ phase2_laser_warning_duration
		+ phase2_a_laser_damage_duration
	)

	var second_at: float = maxf(
		phase2_a_laser2_at,
		first_end
	)

	var second_end: float = (
		second_at
		+ phase2_laser_warning_duration
		+ phase2_a_laser_damage_duration
	)

	var events: Array[Dictionary] = [
		{
			"at": 0.0,
			"call": Callable(self, "_spawn_phase2_a_tentacles")
		},
		{
			"at": first_at,
			"call": Callable(self, "start_laser_sweep").bind(false)
		},
		{
			"at": first_end,
			"call": Callable(self, "stop_laser_sweep")
		},
		{
			"at": second_at,
			"call": Callable(self, "start_laser_sweep").bind(true)
		},
		{
			"at": second_end,
			"call": Callable(self, "stop_laser_sweep")
		},
		{
			"at": _get_phase2_retract_deadline(),
			"call": Callable(self, "_force_retract_all_tentacles")
		}
	]

	_schedule_phase2_events(events)


# ============================================================
# 19. 二階 B：虛實雙殺
# ============================================================

func _build_phase2_b_timeline() -> void:

	var real_spawn_at: float = _get_phase2_b_real_spawn_at()

	var laser_at: float = maxf(
		phase2_b_laser_at,
		real_spawn_at + phase2_b_real_warning
	)

	var laser_end: float = (
		laser_at
		+ phase2_laser_warning_duration
		+ phase2_b_laser_damage_duration
	)

	var events: Array[Dictionary] = [
		{
			"at": 0.0,
			"call": Callable(self, "_spawn_phase2_b_fake_pair")
		},
		{
			"at": real_spawn_at,
			"call": Callable(self, "_spawn_phase2_b_real_pair")
		},
		{
			"at": laser_at,
			"call": Callable(self, "start_laser_sweep").bind(false)
		},
		{
			"at": laser_end,
			"call": Callable(self, "stop_laser_sweep")
		},
		{
			"at": _get_phase2_retract_deadline(),
			"call": Callable(self, "_force_retract_all_tentacles")
		}
	]

	_schedule_phase2_events(events)


# ============================================================
# 20. 第二階段 - 共用事件排程器
#
# 將 A/B 模式的事件統一放入時間軸
# 時間軸可以在轉階、死亡時立即取消
# ============================================================

func _schedule_phase2_events(
	events: Array[Dictionary]
) -> void:

	events.sort_custom(
		func(a, b):
			return float(a["at"]) < float(b["at"])
	)

	var last_time: float = 0.0

	for event in events:

		var event_time: float = maxf(
			float(event["at"]),
			last_time
		)

		var delay: float = event_time - last_time

		if delay > 0.0:
			_phase_timeline.tween_interval(delay)

		var action: Callable = event["call"]

		_phase_timeline.tween_callback(action)

		last_time = event_time

	if last_time > phase2_round_duration:

		push_warning(
			"二階時間軸超過循環長度，請檢查 Inspector。"
		)

	else:

		_phase_timeline.tween_interval(
			phase2_round_duration - last_time
		)

	_phase_timeline.tween_callback(
		_play_phase_2_timeline
	)


# ============================================================
# 21. 時間計算工具
# ============================================================

func _get_phase1_clear_time() -> float:

	return (
		phase1_start_delay
		+ phase1_first_spiral
		+ phase1_middle_rest
		+ phase1_second_spiral
	)


func _get_phase2_retract_deadline() -> float:

	return minf(
		phase2_final_retract_at,
		phase2_round_duration - 0.1
	)


func _get_phase2_b_real_spawn_at() -> float:

	return (
		phase2_b_fake_warning
		+ phase2_b_fake_shout
		+ phase2_b_gap_after_fake
	)


func _stop_phase_timeline() -> void:

	if _phase_timeline and _phase_timeline.is_running():
		_phase_timeline.kill()


# ============================================================
# 22. 四角資料
#
# 使用原本四個繼承場景
# ============================================================

func _get_tentacle_corners() -> Array[Dictionary]:

	var corners: Array[Dictionary] = [
		{
			"name": "左上",
			"point": $TentacleAnchors/SpawnPoint_LeftTop,
			"scene": tentacle_right_down
		},
		{
			"name": "左下",
			"point": $TentacleAnchors/SpawnPoint_LeftDown,
			"scene": tentacle_right_top
		},
		{
			"name": "右上",
			"point": $TentacleAnchors/SpawnPoint_RightTop,
			"scene": tentacle_left_down
		},
		{
			"name": "右下",
			"point": $TentacleAnchors/SpawnPoint_RightDown,
			"scene": tentacle_left_top
		}
	]

	return corners


func _tentacle_scenes_ready() -> bool:

	return (
		tentacle_left_top != null
		and tentacle_left_down != null
		and tentacle_right_top != null
		and tentacle_right_down != null
	)


# ============================================================
# 23. 第一階段 - 觸手生成入口
# ============================================================

func trigger_vine_obstacles() -> void:

	if is_dead or is_transitioning:
		return

	if not _tentacle_scenes_ready():

		push_error("BossLotus：觸手場景未掛載完整！")
		return

	if current_phase == 1:
		_spawn_phase1_tentacles()


# ============================================================
# 24. 第一階段 - 四觸手隨機收回
# ============================================================

func _spawn_phase1_tentacles() -> void:

	var corners: Array[Dictionary] = _get_tentacle_corners()

	var retract_times: Array[float] = [
		retract_time_1,
		retract_time_2,
		retract_time_3,
		retract_time_4
	]

	retract_times.shuffle()

	var clear_time: float = _get_phase1_clear_time()

	for i in range(4):

		var retract_at: float = clampf(
			retract_times[i],
			0.1,
			clear_time
		)

		_spawn_one_tentacle(
			corners[i],
			phase1_tentacle_hp,
			phase1_smash_damage,
			phase1_ink_reward,
			phase1_telegraph_time,
			retract_at,
			0.0,
			false
		)


# ============================================================
# 25. 二階 A - 四根狂暴觸手
# ============================================================

func _spawn_phase2_a_tentacles() -> void:

	if is_dead or is_transitioning:
		return

	if not _tentacle_scenes_ready():
		push_error("BossLotus：觸手場景未設定！")
		return

	var corners: Array[Dictionary] = _get_tentacle_corners()

	var short1: float = randf_range(
		minf(phase2_a_short1_min, phase2_a_short1_max),
		maxf(phase2_a_short1_min, phase2_a_short1_max)
	)

	var short2: float = randf_range(
		minf(phase2_a_short2_min, phase2_a_short2_max),
		maxf(phase2_a_short2_min, phase2_a_short2_max)
	)

	var final_time: float = _get_phase2_retract_deadline()

	var retract_times: Array[float] = [
		short1,
		short2,
		final_time,
		final_time
	]

	retract_times.shuffle()

	for i in range(4):

		var retract_at: float = minf(
			retract_times[i],
			final_time
		)

		_spawn_one_tentacle(
			corners[i],
			phase2_tentacle_hp,
			phase2_smash_damage,
			phase2_ink_reward,
			phase2_a_telegraph,
			retract_at,
			0.0,
			false
		)


# ============================================================
# 26. 二階 B - 兩根假觸手
# ============================================================

func _spawn_phase2_b_fake_pair() -> void:

	if is_dead or is_transitioning:
		return

	if not _tentacle_scenes_ready():
		push_error("BossLotus：觸手場景未設定！")
		return

	_phase2_b_corner_order = [0, 1, 2, 3]
	_phase2_b_corner_order.shuffle()

	var corners: Array[Dictionary] = _get_tentacle_corners()

	for i in range(2):

		var corner_index: int = _phase2_b_corner_order[i]

		_spawn_one_tentacle(
			corners[corner_index],
			phase2_tentacle_hp,
			phase2_smash_damage,
			0.0,
			phase2_b_fake_warning,
			-1.0,
			0.0,
			true,
			phase2_b_fake_shout
		)


# ============================================================
# 27. 二階 B - 兩根真觸手
# ============================================================

func _spawn_phase2_b_real_pair() -> void:

	if is_dead or is_transitioning:
		return

	if _phase2_b_corner_order.size() != 4:
		return

	var corners: Array[Dictionary] = _get_tentacle_corners()

	var spawn_at: float = _get_phase2_b_real_spawn_at()
	var retract_at: float = _get_phase2_retract_deadline()

	for i in range(2, 4):

		var corner_index: int = _phase2_b_corner_order[i]

		_spawn_one_tentacle(
			corners[corner_index],
			phase2_tentacle_hp,
			phase2_smash_damage,
			phase2_ink_reward,
			phase2_b_real_warning,
			retract_at,
			spawn_at,
			false
		)


# ============================================================
# 28. 共用觸手生成器
#
# 與 v5.2 的 tentacle.gd 相容
# ============================================================

func _spawn_one_tentacle(
	corner: Dictionary,
	hp: int,
	damage: int,
	ink: float,
	warning: float,
	retract_at: float,
	born_at: float,
	fake: bool,
	fake_shout_time: float = 0.2
) -> void:

	if is_dead or is_transitioning:
		return

	_prune_tentacle_references()

	var scene: PackedScene = corner["scene"]

	if scene == null:
		push_error("觸手 PackedScene 為空！")
		return

	var tentacle: Tentacle = scene.instantiate() as Tentacle

	if tentacle == null:
		push_error("觸手場景沒有使用 Tentacle 腳本！")
		return

	# 必須在 add_child 前設定數值
	tentacle.max_hp = hp
	tentacle.smash_damage = damage
	tentacle.ink_reward = ink
	tentacle.telegraph_time = warning

	get_parent().add_child(tentacle)

	var point: Node2D = corner["point"]
	tentacle.global_position = point.global_position

	tentacle.set_enraged(current_phase == 2)

	current_active_tentacles.append(tentacle)

	# 假觸手只做假動作
	if fake:

		tentacle.execute_fake_smash(fake_shout_time)
		return

	# 真觸手啟動壽命
	if retract_at >= 0.0:

		var remaining: float = maxf(
			retract_at - born_at,
			0.05
		)

		tentacle.start_lifespan_countdown(remaining)

	tentacle.execute_smash()


# ============================================================
# 29. 移除已退場的觸手參照
# ============================================================

func _prune_tentacle_references() -> void:

	for i in range(
		current_active_tentacles.size() - 1,
		-1,
		-1
	):

		var tentacle: Tentacle = current_active_tentacles[i]

		if not is_instance_valid(tentacle):

			current_active_tentacles.remove_at(i)
			continue

		if tentacle.is_dead:
			current_active_tentacles.remove_at(i)


# ============================================================
# 30. 強制清場
# ============================================================

func _force_retract_all_tentacles() -> void:

	for tentacle in current_active_tentacles:

		if not is_instance_valid(tentacle):
			continue

		if tentacle.is_dead:
			continue

		tentacle.retract()

	current_active_tentacles.clear()


# ============================================================
# 31. 傷害計算
#
# Boss 本體只能被遠程攻擊
# ============================================================

func take_damage(
	amount: float,
	_hit_position: Vector2 = Vector2.ZERO,
	_hit_direction: Vector2 = Vector2.ZERO,
	is_melee: bool = false,
	_extra_knockback: float = 1.0
) -> void:

	if is_melee:
		return

	if is_dead or is_transitioning:
		return

	if amount <= 0.0:
		return

	current_hp -= int(amount)

	if (
		current_phase == 1
		and current_hp <= phase_2_threshold
	):

		current_hp = phase_2_threshold

		if boss_ui:
			boss_ui.update_health(current_hp)

		_enter_phase_2()
		return

	current_hp = clampi(current_hp, 0, max_hp)

	if boss_ui:
		boss_ui.update_health(current_hp)

	if current_hp <= 0:

		_die()

	else:

		_play_hit_flash_tween()


# ============================================================
# 32. 進入第二階段
# ============================================================

func _enter_phase_2() -> void:

	if is_transitioning or is_dead:
		return

	is_transitioning = true
	_transition_burst_done = false

	_stop_phase_timeline()

	# 【本次修正】
	# 轉階時清除所有雷射動畫的延遲回呼
	_laser_sequence_active = false
	_cancel_laser_visual_tween()

	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()

	sprite.position = original_sprite_pos
	sprite.scale = original_sprite_scale

	if spawners:
		spawners.stop_all()

	if laser_weapon:
		laser_weapon.stop_laser()

	_clear_boss_bullets()
	_force_retract_all_tentacles()

	sprite.play("hurt")

	_play_phase_transition_effect()

	get_tree().create_timer(
		transition_duration
	).timeout.connect(finish_transition)


# ============================================================
# 33. 轉階震動、變色
# ============================================================

func _play_phase_transition_effect() -> void:

	var burst_time: float = minf(
		transition_burst_time,
		transition_duration
	)

	_transition_color_tween = create_tween()

	_transition_color_tween.tween_property(
		sprite,
		"modulate",
		phase_2_color,
		burst_time
	).set_trans(Tween.TRANS_SINE)

	_transition_shake_tween = create_tween()

	var step_time: float = maxf(
		transition_shake_step,
		0.01
	)

	var shake_count: int = maxi(
		1,
		int(burst_time / (step_time * 2.0))
	)

	for i in range(shake_count):

		var offset := Vector2(
			randf_range(
				-transition_sprite_shake,
				transition_sprite_shake
			),
			randf_range(
				-transition_sprite_shake,
				transition_sprite_shake
			)
		)

		_transition_shake_tween.tween_property(
			sprite,
			"position",
			original_sprite_pos + offset,
			step_time
		)

		_transition_shake_tween.tween_property(
			sprite,
			"position",
			original_sprite_pos,
			step_time
		)

	get_tree().create_timer(
		burst_time
	).timeout.connect(_on_transition_burst)


# ============================================================
# 34. 轉階紅色衝擊波
# ============================================================

func _on_transition_burst() -> void:

	if not is_inside_tree() or is_dead:
		return

	if not is_transitioning:
		return

	if _transition_burst_done:
		return

	_transition_burst_done = true

	if _transition_shake_tween:
		_transition_shake_tween.kill()

	sprite.position = original_sprite_pos

	var camera = get_tree().get_first_node_in_group("camera")

	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(transition_camera_shake)

	var shockwave := Line2D.new()

	shockwave.width = 15.0
	shockwave.default_color = phase_2_color
	shockwave.closed = true
	shockwave.position = original_sprite_pos

	var points := PackedVector2Array()

	for i in range(32):

		var angle: float = TAU * float(i) / 32.0

		points.append(
			Vector2(cos(angle), sin(angle)) * 100.0
		)

	shockwave.points = points

	add_child(shockwave)

	var blast_tween = create_tween().set_parallel(true)

	blast_tween.tween_property(
		shockwave,
		"scale",
		Vector2(10.0, 10.0),
		0.5
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	blast_tween.tween_property(
		shockwave,
		"modulate:a",
		0.0,
		0.5
	)

	blast_tween.chain().tween_callback(
		shockwave.queue_free
	)

	current_phase = 2

	sprite.modulate = phase_2_color

	original_sprite_scale *= phase2_scale_multiplier
	sprite.scale = original_sprite_scale


# ============================================================
# 35. 完成轉階
# ============================================================

func finish_transition() -> void:

	if not is_inside_tree() or is_dead:
		return

	if not _transition_burst_done:
		_on_transition_burst()

	is_transitioning = false

	sprite.position = original_sprite_pos
	sprite.play("idle")

	_phase2_round_count = 0
	_last_phase2_pattern = ""

	_play_phase_2_timeline()


# ============================================================
# 36. 螺旋彈幕控制
#
# 完全保留原本 Spawners 的 API
# 不需修改彈幕腳本
# ============================================================

func start_spiral_bullets(is_clockwise: bool) -> void:

	if is_dead or is_transitioning:
		return

	sprite.play("attack_bullet")

	if is_clockwise:
		spawners.start_clockwise()
	else:
		spawners.start_counter_clockwise()


func stop_bullets() -> void:

	if spawners:
		spawners.stop_all()

	if not is_dead and not is_transitioning:
		sprite.play("pant")


# ============================================================
# 37. 雷射開始【本次主要修改】
#
# 動畫流程：
# laser_start -> laser_loop
#
# laser_start 的長度自動符合預警秒數
#
# 注意：
# 雷射真正啟動由 LaserWeapon 負責
# 這裡的 Tween 只負責顯示動畫
# ============================================================

func start_laser_sweep(is_clockwise: bool) -> void:

	if is_dead or is_transitioning:
		return

	# 取消上一道雷射殘留的動畫切換
	_cancel_laser_visual_tween()

	_laser_sequence_active = true

	# -------------------------------------
	# 1. 播放蓄力動畫
	#
	# 不管原動畫長度多少，
	# 都會自動調整成設定的預警時間
	# -------------------------------------
	_play_fitted_animation(
		&"laser_start",
		phase2_laser_warning_duration
	)

	# -------------------------------------
	# 2. 啟動雷射武器
	#
	# 使用前一版已修改的 LaserWeapon API
	# -------------------------------------
	if laser_weapon:

		laser_weapon.fire_laser(
			is_clockwise,
			phase2_laser_warning_duration
		)

	# -------------------------------------
	# 3. 預警結束後切換成持續攻擊動畫
	#
	# 即使 laser_start 的原始幀數很長，
	# 也不會拖延進入 laser_loop 的時間
	# -------------------------------------
	_laser_visual_tween = create_tween()

	_laser_visual_tween.tween_interval(
		phase2_laser_warning_duration
	)

	_laser_visual_tween.tween_callback(
		func():

			# 攻擊中斷後不允許繼續切換
			if not _laser_sequence_active:
				return

			if is_dead or is_transitioning:
				return

			# 持續攻擊動畫
			sprite.play("laser_loop")
	)


# ============================================================
# 38. 雷射停止【本次主要修改】
#
# 真正的雷射停止瞬間：
# 1. 停止傷害
# 2. 取消舊動畫回呼
# 3. 立刻播放 laser_end
# 4. 收招結束後回到 pant
#
# 不再等待 laser_loop 自己播完
# ============================================================

func stop_laser_sweep() -> void:

	# -------------------------------------
	# 1. 立即停止真正雷射
	# -------------------------------------
	if laser_weapon:
		laser_weapon.stop_laser()

	_laser_sequence_active = false

	# -------------------------------------
	# 2. 取消之前的預警動畫切換
	# -------------------------------------
	_cancel_laser_visual_tween()

	if is_dead or is_transitioning:
		return

	# -------------------------------------
	# 3. 立刻切換收招動畫
	#
	# 收招播放時間由 Inspector 控制
	# -------------------------------------
	_play_fitted_animation(
		&"laser_end",
		laser_end_visual_duration
	)

	# -------------------------------------
	# 4. 收招動畫完成後恢復喘息
	#
	# 使用同一個視覺 Tween，
	# 下一次雷射開始可以直接取消它
	# -------------------------------------
	_laser_visual_tween = create_tween()

	_laser_visual_tween.tween_interval(
		laser_end_visual_duration
	)

	_laser_visual_tween.tween_callback(
		func():

			if is_dead or is_transitioning:
				return

			if _laser_sequence_active:
				return

			# 如果中途已經被其他動作切換
			# 就不要強行覆蓋目前動畫
			if sprite.animation != &"laser_end":
				return

			sprite.play("pant")
	)


# ============================================================
# 39. 動畫自動配速【本次新增】
#
# 根據：
# 1. 動畫總幀數
# 2. SpriteFrames FPS
# 3. 每幀的相對持續時間
#
# 計算原本動畫播放秒數，
# 再用 AnimatedSprite2D.play(custom_speed)
# 將動畫調整到指定時間
#
# 不修改 SpriteFrames 資源本身的 FPS，
# 因此不會影響其他使用相同資源的動畫
# ============================================================

func _play_fitted_animation(
	animation_name: StringName,
	target_duration: float
) -> void:

	var frames: SpriteFrames = sprite.sprite_frames

	if frames == null:
		return

	# 找不到動畫時顯示警告
	if not frames.has_animation(animation_name):

		push_warning(
			"Boss 缺少動畫：" + str(animation_name)
		)
		return

	var frame_count: int = frames.get_frame_count(
		animation_name
	)

	var animation_fps: float = frames.get_animation_speed(
		animation_name
	)

	# 避免除以零
	if frame_count <= 0 or animation_fps <= 0.0:

		sprite.play(animation_name)
		return

	# -------------------------------------
	# 計算所有幀的相對持續時間
	#
	# 有些動畫幀可能特別長，
	# 不能只用總幀數 / FPS 猜測
	# -------------------------------------
	var total_frame_units: float = 0.0

	for i in range(frame_count):

		total_frame_units += frames.get_frame_duration(
			animation_name,
			i
		)

	# 動畫在標準速度下的總長度
	var natural_duration: float = (
		total_frame_units / animation_fps
	)

	# 目標動畫時間
	var safe_duration: float = maxf(
		target_duration,
		0.01
	)

	# 若 Sprite 的全域播放速度為零
	# 先恢復，避免動畫完全不播放
	if is_zero_approx(sprite.speed_scale):
		sprite.speed_scale = 1.0

	# -------------------------------------
	# 計算個別動畫播放倍率
	#
	# 範例：
	# 原動畫 1.0 秒
	# 目標 0.5 秒
	# 播放速度 = 2 倍
	# -------------------------------------
	var custom_speed: float = (
		natural_duration
		/ safe_duration
		/ absf(sprite.speed_scale)
	)

	custom_speed = maxf(custom_speed, 0.01)

	# stop() 確保從第一幀重新播放
	sprite.stop()

	sprite.play(
		animation_name,
		custom_speed
	)


# ============================================================
# 40. 取消雷射視覺排程【本次新增】
#
# 用於：
# 1. 新雷射開始
# 2. 雷射停止
# 3. Boss 轉階
# 4. Boss 死亡
#
# 防止舊 Tween 把新動畫覆蓋掉
# ============================================================

func _cancel_laser_visual_tween() -> void:

	if _laser_visual_tween:

		if _laser_visual_tween.is_running():
			_laser_visual_tween.kill()

	_laser_visual_tween = null


# ============================================================
# 41. Boss 受擊效果
#
# 【本次修正】
#
# 正在雷射攻擊或收招時：
# 只做顏色、縮放、震動回饋
# 不切換 hurt 動畫
#
# 避免雷射動畫被受傷動畫覆蓋
#
# 其他狀態：
# 仍然保留原本 hurt 動畫
# ============================================================

func _play_hit_flash_tween() -> void:

	if is_dead or is_transitioning:
		return

	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()

	sprite.position = original_sprite_pos
	sprite.scale = original_sprite_scale

	var previous_anim: StringName = sprite.animation
	var previous_frame: int = sprite.frame

	# -------------------------------------
	# 判斷是否正在執行雷射動作
	# -------------------------------------
	var is_laser_visual: bool = (
		_laser_sequence_active
		or sprite.animation == &"laser_end"
	)

	# 雷射期間不切換 hurt
	if not is_laser_visual:
		sprite.play("hurt")

	# -------------------------------------
	# 階段對應的受擊顏色
	# -------------------------------------
	var return_color: Color = Color.WHITE

	if current_phase == 2:

		return_color = phase_2_color
		sprite.modulate = Color.WHITE

	else:

		sprite.modulate = Color.RED

	# 受擊膨脹效果
	sprite.scale = original_sprite_scale * 1.15

	_hit_tween = create_tween().set_parallel(true)

	_hit_tween.tween_property(
		sprite,
		"modulate",
		return_color,
		0.2
	)

	_hit_tween.tween_property(
		sprite,
		"scale",
		original_sprite_scale,
		0.25
	).set_trans(Tween.TRANS_EXPO).set_ease(
		Tween.EASE_OUT
	)

	# 小幅震動
	for i in range(5):

		var offset := Vector2(
			randf_range(-15.0, 15.0),
			randf_range(-15.0, 15.0)
		)

		_hit_tween.tween_property(
			sprite,
			"position",
			original_sprite_pos + offset,
			0.02
		).set_delay(float(i) * 0.025)

	_hit_tween.tween_property(
		sprite,
		"position",
		original_sprite_pos,
		0.02
	).set_delay(0.15)

	# -------------------------------------
	# 受擊結束後恢復動畫
	#
	# 只有目前仍是 hurt 時才恢復
	# 避免將新啟動的雷射覆蓋成舊動畫
	# -------------------------------------
	_hit_tween.chain().tween_callback(
		func():

			if is_dead or is_transitioning:
				return

			if is_laser_visual:
				return

			if sprite.animation != &"hurt":
				return

			if previous_anim == &"hurt" or previous_anim == &"die":
				return

			if not sprite.sprite_frames.has_animation(previous_anim):
				return

			sprite.play(previous_anim)

			if sprite.sprite_frames.get_animation_loop(previous_anim):

				sprite.set_frame_and_progress(
					previous_frame,
					0.0
				)
	)


# ============================================================
# 42. 清除場上彈幕
# ============================================================

func _clear_boss_bullets() -> void:

	var bullets = get_tree().get_nodes_in_group(
		"boss_bullets"
	)

	for bullet in bullets:

		if is_instance_valid(bullet):
			bullet.queue_free()


# ============================================================
# 43. Boss 死亡
# ============================================================

func _die() -> void:

	if is_dead:
		return

	is_dead = true

	_stop_phase_timeline()

	# 【本次修正】
	# 死亡時徹底中斷雷射動畫排程
	_laser_sequence_active = false
	_cancel_laser_visual_tween()

	if _hit_tween:
		_hit_tween.kill()

	if _transition_color_tween:
		_transition_color_tween.kill()

	if _transition_shake_tween:
		_transition_shake_tween.kill()

	if spawners:
		spawners.stop_all()

	if laser_weapon:
		laser_weapon.stop_laser()

	_clear_boss_bullets()
	_force_retract_all_tentacles()

	# 關閉本體碰撞
	if has_node("CollisionShape2D"):

		$CollisionShape2D.set_deferred(
			"disabled",
			true
		)

	# 關閉受傷判定
	if has_node("Hurtbox/CollisionShape2D"):

		$Hurtbox/CollisionShape2D.set_deferred(
			"disabled",
			true
		)

	sprite.position = original_sprite_pos
	sprite.scale = original_sprite_scale

	sprite.play("die")

	# 死亡動畫淡出
	var death_tween = create_tween()

	death_tween.tween_property(
		sprite,
		"modulate",
		Color(0.2, 0.2, 0.2, 1.0),
		1.0
	)

	death_tween.tween_property(
		sprite,
		"modulate:a",
		0.0,
		1.5
	)

	death_tween.tween_callback(queue_free)


extends BaseEnemy
class_name Barbarian

# =====================================================
# 野蠻人專屬控制器
# 一階：慢速移動、普通揮刀
# 二階：瀕死狂暴、高速永久追擊
# 保留 BaseEnemy 的共用功能，不影響其他敵人
# =====================================================

@export_group("一階 - 基礎數值")
@export var stage1_max_hp: int = 100          # 一階最大血量
@export var stage1_walk_speed: int = 80       # 一階移動速度
@export var stage1_damage: float = 50.0       # 一階揮刀傷害
@export var stage1_contact_damage: float = 15.0 # 一階肉身碰撞傷害

@export_group("二階 - 狂暴數值")
@export var stage2_walk_speed: int = 300      # 二階奔跑速度
@export var stage2_damage: float = 75.0       # 二階揮刀傷害
@export var stage2_contact_damage: float = 25.0 # 二階肉身碰撞傷害

@export_group("鎖血變身設定")
@export_range(0.0, 100.0, 0.1)
var berserk_trigger_percent: float = 1.0      # 血量降至最大血量的 1% 時變身

const BERSERK_LOCK_HP: float = 1.0           # 變身後固定保留 1 HP

@export_group("肉身碰撞設定")
@export_range(0.1, 5.0, 0.05)
var contact_hit_cooldown: float = 0.8        # 接觸傷害的最短間隔

@export var contact_knockback: float = 1.0   # 肉身碰撞擊退倍率
@export var sword_knockback: float = 1.5     # 揮刀攻擊擊退倍率

# =====================================================
# 內部狀態
# =====================================================
var is_berserk: bool = false                 # 是否已經進入狂暴型態
var is_transforming: bool = false            # 是否正在播放無敵變身演出

var _contact_enabled: bool = false           # 肉身傷害開關
var _contact_timer: float = 0.0              # 肉身傷害冷卻倒數

var _sword_active: bool = false              # 揮刀傷害窗口
var _sword_hit_targets: Dictionary = {}       # 本次揮刀已經命中的目標
var _missing_animations: Dictionary = {}     # 避免缺少動畫時不斷印出警告

# =====================================================
# 節點參照
# 其餘節點繼續使用 BaseEnemy 已有的 @onready
# =====================================================
@onready var body_hitbox: Area2D = $BodyHitbox
@onready var detect_player_area: Area2D = $DetectPlayer

# =====================================================
# 初始化
# =====================================================
func _ready() -> void:
	max_hp = maxi(stage1_max_hp, 2)
	current_hp = max_hp
	walk_speed = stage1_walk_speed
	melee_damage = stage1_damage
	use_diagonal_anim = true                 # 野蠻人固定使用四斜方向
	is_berserk = false
	is_transforming = false

	# 複製材質，避免受擊或死亡特效影響其他共用材質的敵人
	if animated_sprite_2d.material is ShaderMaterial:
		animated_sprite_2d.material = animated_sprite_2d.material.duplicate()

	super._ready()                           # 啟動 BaseEnemy 的初始化與狀態機
	end_sword_attack()
	set_contact_enabled(true)                # 一階出生就具有肉身碰撞傷害

# =====================================================
# 物理更新
# =====================================================
func _physics_process(delta: float) -> void:
	_contact_timer = maxf(_contact_timer - delta, 0.0)
	if not is_instance_valid(player_node):
		player_node = null
	super._physics_process(delta)            # 保留原本移動、物理碰撞與共用功能

# =====================================================
# 四斜方向判定
# 動畫與攻擊碰撞共用同一套方向，避免彼此不一致
# =====================================================
func get_direction_suffix(dir: Vector2 = Vector2.ZERO) -> String:
	var target_dir: Vector2 = dir if dir != Vector2.ZERO else last_facing_vec
	var x_name: String = ""
	var y_name: String = ""

	if target_dir.x > 0.0:
		x_name = "right"
	elif target_dir.x < 0.0:
		x_name = "left"
	else:
		x_name = "left" if target_dir.y < 0.0 else "right"

	y_name = "up" if target_dir.y < 0.0 else "down"
	return x_name + "_" + y_name

# =====================================================
# 組合目前型態的動畫名稱
#
# 一階：attack_right_down
# 二階：berserk_attack_right_down
# =====================================================
func get_action_animation(action: String, dir: Vector2 = Vector2.ZERO) -> StringName:
	var prefix: String = action

	if action == "transform":
		prefix = "berserk_transform"         # 變身動畫是獨立的特殊前綴
	elif is_berserk:
		if action == "move" or action == "run":
			prefix = "berserk_run"           # 二階移動一律使用跑步動畫
		elif action == "hurt":
			prefix = "berserk_idle"          # 二階不使用普通受傷動畫
		else:
			prefix = "berserk_" + action
	elif action == "run":
		prefix = "move"                      # 一階沒有跑步動畫

	return StringName(prefix + "_" + get_direction_suffix(dir))

# =====================================================
# 動畫播放入口
# 覆寫 BaseEnemy，讓既有狀態仍可使用 play_animation()
# =====================================================
func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO) -> void:
	play_action(prefix, dir)

func play_action(
	action: String,
	dir: Vector2 = Vector2.ZERO,
	restart: bool = false,
	playback_speed: float = 1.0
) -> bool:
	if not animated_sprite_2d or not animated_sprite_2d.sprite_frames:
		return false

	if dir != Vector2.ZERO:
		last_facing_vec = dir.normalized()     # 記錄最後面向方向

	var anim_name: StringName = get_action_animation(action, dir)
	if not animated_sprite_2d.sprite_frames.has_animation(anim_name):
		if not _missing_animations.has(anim_name):
			_missing_animations[anim_name] = true
			push_warning("野蠻人缺少動畫：" + str(anim_name))
		return false

	if restart:
		animated_sprite_2d.stop()             # 攻擊、變身等一次性動畫從第 0 幀開始

	animated_sprite_2d.play(anim_name, maxf(playback_speed, 0.01))
	return true

# =====================================================
# 檢查一次性動畫是否可正常使用
# 避免 Attack / Transform 設為 Loop 後卡死
# =====================================================
func has_one_shot_animation(action: String, dir: Vector2 = Vector2.ZERO) -> bool:
	var frames: SpriteFrames = animated_sprite_2d.sprite_frames
	var anim_name: StringName = get_action_animation(action, dir)
	if not frames or not frames.has_animation(anim_name):
		return false
	return (
		frames.get_frame_count(anim_name) > 0
		and frames.get_animation_speed(anim_name) > 0.0
		and not frames.get_animation_loop(anim_name)
		and animated_sprite_2d.speed_scale > 0.0
	)

# =====================================================
# 取得有效玩家
# 一階使用 DetectPlayer 找到的玩家
# 二階直接透過 DataManager 取得玩家，不再限制偵測距離
# =====================================================
func get_combat_target() -> Player:
	var target: Player = null

	if is_berserk:
		if DataManager and is_instance_valid(DataManager.player_node):
			target = DataManager.player_node as Player
	else:
		if is_instance_valid(player_node):
			target = player_node as Player

	if not is_instance_valid(target):
		return null
	if target.is_dead or not target.is_inside_tree():
		return null

	return target

# =====================================================
# 覆寫原本的偵測區事件
# 進入狂暴後，忽略偵測區進出訊號
# =====================================================
func _on_detect_player_body_entered(body) -> void:
	if is_berserk:
		return
	super._on_detect_player_body_entered(body)

func _on_detect_player_body_exited(body) -> void:
	if is_berserk:
		return
	super._on_detect_player_body_exited(body)

# =====================================================
# 傷害處理與 1 HP 鎖血
# =====================================================
func take_damage(
	amount: float,
	attacker_pos: Vector2 = Vector2.ZERO,
	dir: Vector2 = Vector2.ZERO,
	is_melee: bool = false,
	extra_knockback: float = 1.0
) -> void:
	if is_dead or is_transforming or amount <= 0.0:
		return                              # 變身演出期間免疫傷害

	var next_hp: float = current_hp - amount
	var threshold: float = float(max_hp) * berserk_trigger_percent / 100.0

	# 一階血量抵達門檻時，攔截正常死亡流程
	if not is_berserk and next_hp <= threshold:
		current_hp = BERSERK_LOCK_HP
		is_berserk = true
		is_transforming = true
		velocity = Vector2.ZERO
		can_attack = false
		update_hp_bar()

		# 變身這一擊不算擊殺，近戰仍可獲得普通攻擊的墨水回復
		if is_melee and DataManager and is_instance_valid(DataManager.player_node):
			if DataManager.player_node.has_method("add_ammo"):
				DataManager.player_node.add_ammo(1)

		# 清除變身前可能留下的擊退力道
		knockback_force = Vector2.ZERO
		if knockback_component:
			knockback_component.knockback_force = Vector2.ZERO

		# 停止全部攻擊判定
		end_sword_attack()
		set_contact_enabled(false)

		# 正式關閉一階的偵測機制
		detect_player_area.set_deferred("monitoring", false)
		vision_ray.enabled = false
		player_node = null                   # 不再使用普通敵人的偵測目標
		can_see_player = false

		state_machine.change_state("BerserkTransition")
		return

	# 二階只剩 1 HP，下一次有效傷害直接死亡
	if is_berserk:
		amount = maxf(amount, current_hp)

	# 保留 BaseEnemy 的受擊效果、墨水回復、粒子與金幣掉落
	super.take_damage(amount, attacker_pos, dir, is_melee, extra_knockback)

# =====================================================
# 正式完成變身
# 由 BerserkTransition 在動畫播完後呼叫
# =====================================================
func finish_berserk_transition() -> void:
	if is_dead or not is_transforming:
		return

	is_transforming = false
	walk_speed = stage2_walk_speed
	melee_damage = stage2_damage
	can_attack = true
	set_contact_enabled(true)
	state_machine.change_state("BerserkCharge")

# =====================================================
# 受傷硬直與控場
# 二階只接受傷害並死亡，不進入普通 Hurt / Stun
# =====================================================
func handle_hurt() -> void:
	if is_berserk or is_transforming:
		return
	super.handle_hurt()

func apply_stun(duration: float = 1.0) -> void:
	if is_dead or is_berserk or is_transforming:
		return
	super.apply_stun(duration)

# =====================================================
# 肉身碰撞開關
# 一階、二階都有肉身傷害
# 揮刀、變身、死亡期間暫時關閉
# =====================================================
func set_contact_enabled(enabled: bool) -> void:
	_contact_enabled = enabled and not is_dead and not is_transforming
	if not body_hitbox:
		return

	body_hitbox.set_deferred("monitoring", _contact_enabled)
	for child in body_hitbox.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not _contact_enabled)

# =====================================================
# 揮刀攻擊初始化
# 每次揮刀只允許同一名玩家受到一次傷害
# =====================================================
func begin_sword_attack() -> void:
	_sword_hit_targets.clear()
	set_contact_enabled(false)               # 防止肉身傷害與揮刀傷害同時生效
	set_sword_window("", false)

# =====================================================
# 指定方向的傷害碰撞開關
#
# suffix 例如 right_down
# 只允許對應方向的 CollisionShape2D 開啟
# =====================================================
func set_sword_window(suffix: String, enabled: bool) -> void:
	_sword_active = enabled and not is_dead and not is_transforming
	if not hitbox:
		return

	var target_name: String = "CollisionShape_" + suffix
	if _sword_active and not hitbox.has_node(target_name):
		push_warning("找不到揮刀碰撞框：" + target_name)
		_sword_active = false

	hitbox.set_deferred("monitoring", _sword_active)
	for child in hitbox.get_children():
		if child is CollisionShape2D:
			var active: bool = _sword_active and child.name == target_name
			child.set_deferred("disabled", not active)

func end_sword_attack() -> void:
	set_sword_window("", false)
	_sword_hit_targets.clear()

# =====================================================
# 揮刀傷害共用入口
# 不論 Body 或 Area 訊號，都統一由此處處理
# =====================================================
func _try_sword_hit(target: Node) -> void:
	if not _sword_active or is_dead or is_transforming:
		return
	if not is_instance_valid(target):
		return

	var target_id: int = target.get_instance_id()
	if _sword_hit_targets.has(target_id):
		return                              # 這一刀已經命中過此目標

	if target is Player:
		var player: Player = target as Player
		if player.is_dead or player.is_invincible:
			return
		_sword_hit_targets[target_id] = true
		var damage: float = stage2_damage if is_berserk else stage1_damage
		var hit_dir: Vector2 = global_position.direction_to(player.global_position)
		player.take_damage(damage, global_position, hit_dir, false, sword_knockback)

	elif target is WhiteCat or target.is_in_group("white_cat"):
		# 保留原本 BaseEnemy 對白貓的攻擊支援
		if target.has_method("take_damage"):
			_sword_hit_targets[target_id] = true
			var damage: float = stage2_damage if is_berserk else stage1_damage
			target.take_damage(damage, global_position)

# =====================================================
# 覆寫 BaseEnemy 的原始 Hitbox 訊號
# 避免原本的每幀傷害與新版揮刀傷害互相重複
# =====================================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	_try_sword_hit(area.get_parent())

func _on_hitbox_body_entered(body: Node2D) -> void:
	_try_sword_hit(body)

# =====================================================
# 肉身接觸傷害
# 使用冷卻時間保護，避免玩家每個物理幀都遭受傷害
# =====================================================
func _check_contact_damage() -> void:
	if not _contact_enabled or is_dead or is_transforming:
		return
	if _contact_timer > 0.0:
		return
	if not body_hitbox or not body_hitbox.monitoring:
		return

	for body in body_hitbox.get_overlapping_bodies():
		if body is Player:
			var player: Player = body as Player
			if player.is_dead or player.is_invincible:
				continue

			var damage: float = stage2_contact_damage if is_berserk else stage1_contact_damage
			if damage <= 0.0:
				continue

			var hit_dir: Vector2 = global_position.direction_to(player.global_position)
			_contact_timer = contact_hit_cooldown
			player.take_damage(damage, global_position, hit_dir, false, contact_knockback)
			break

# =====================================================
# 覆寫 BaseEnemy 每幀碰撞檢查
# 同時處理揮刀與肉身碰撞，統一傷害來源
# =====================================================
func _check_hitbox_overlap() -> void:
	if is_dead or is_transforming:
		return

	if _sword_active and hitbox and hitbox.monitoring:
		for body in hitbox.get_overlapping_bodies():
			_try_sword_hit(body)
		for area in hitbox.get_overlapping_areas():
			_try_sword_hit(area.get_parent())

	_check_contact_damage()

# =====================================================
# 死亡
# 避免屍體仍然存在接觸傷害
# =====================================================
func die() -> void:
	if is_dead:
		return

	is_transforming = false
	end_sword_attack()
	set_contact_enabled(false)

	if fade_tween and fade_tween.is_running():
		fade_tween.kill()                     # 停止迷霧顯形的淡入淡出

	visible = true
	modulate = Color.WHITE                   # 確保死亡演出與屍體可見
	super.die()                             # 保留原本死亡狀態與金幣掉落

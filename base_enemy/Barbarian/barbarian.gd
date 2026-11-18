extends BaseEnemy
class_name Barbarian

# =====================================================
# 第一階段・基礎數值
# =====================================================
@export_group("一階・基礎數值")
## 第一階段最大血量。
@export var stage1_max_hp: int = 100
## 第一階段移動速度。
@export var stage1_walk_speed: int = 80
## 第一階段武器攻擊傷害。
@export var stage1_damage: float = 50.0
## 敵人必須接近至此距離，才允許發動攻擊。
@export_range(1.0, 500.0, 1.0, "or_greater") var stage1_attack_range: float = 100.0

# =====================================================
# 第二階段・狂暴數值
# =====================================================
@export_group("二階・狂暴數值")
## 狂暴狀態下的移動速度。
@export var stage2_walk_speed: int = 300
## 狂暴狀態下的武器攻擊傷害。
@export var stage2_damage: float = 75.0
## 狂暴狀態下發動攻擊的距離。
@export_range(1.0, 500.0, 1.0, "or_greater") var stage2_attack_range: float = 90.0
## 觸發狂暴變身的血量百分比。
@export_range(0.1, 50.0, 0.1) var berserk_trigger_percent: float = 1.0

const BERSERK_LOCK_HP: float = 1.0 # 狂暴變身時固定保留一滴血

# =====================================================
# 方向校正設定
# =====================================================
@export_group("戰鬥・方向校正")
## 敵人的地面位置基準節點。
@export_node_path("Node2D") var enemy_aim_anchor_path: NodePath = ^"CollisionShape2D"
## 玩家的地面位置基準節點。
@export var player_aim_anchor_path: NodePath = ^"CollisionShape2D"
## 敵人方向計算位置的額外偏移。
@export var enemy_aim_offset: Vector2 = Vector2.ZERO
## 玩家方向計算位置的額外偏移。
@export var player_aim_offset: Vector2 = Vector2.ZERO

# =====================================================
# 戰鬥設定
# =====================================================
@export_group("戰鬥・傷害設定")
## 武器命中時的額外擊退倍率。
@export var sword_knockback: float = 1.5
## 在輸出面板顯示攻擊距離、方向及動畫名稱。
@export var debug_attack_geometry: bool = false

# =====================================================
# 內部狀態
# =====================================================
var is_berserk: bool = false # 是否已經進入第二階段
var is_transforming: bool = false # 是否正在播放變身動畫
var _sword_engaged: bool = false # 是否正在進行完整的武器攻擊流程
var _sword_active: bool = false # 是否位於有效傷害影格
var _active_sword_suffix: String = "" # 目前開啟的攻擊方向
var _sword_hit_targets: Dictionary = {} # 記錄本次攻擊已命中的目標
var _missing_animations: Dictionary = {} # 防止重複輸出缺少動畫的警告
var _missing_shapes: Dictionary = {} # 防止重複輸出碰撞框警告

# =====================================================
# 節點引用
# =====================================================
@onready var body_hitbox: Area2D = get_node_or_null("BodyHitbox") as Area2D # 已停用的肉身判定
@onready var detect_player_area: Area2D = get_node_or_null("DetectPlayer") as Area2D # 一階偵測區域

# =====================================================
# 初始化
# =====================================================
func _ready() -> void:
	max_hp = stage1_max_hp # 將 Inspector 數值同步至父類別
	current_hp = stage1_max_hp
	walk_speed = stage1_walk_speed
	melee_damage = stage1_damage
	use_diagonal_anim = true # 使用左上、右上、左下、右下四方向動畫
	if animated_sprite_2d.material is ShaderMaterial:
		animated_sprite_2d.material = animated_sprite_2d.material.duplicate() # 避免共用材質互相影響
	super._ready() # 啟動 BaseEnemy 初始化及狀態機
	end_sword_attack() # 初始關閉所有武器碰撞框
	set_contact_enabled(false) # 永久停用肉身碰撞傷害
	update_hp_bar()

# =====================================================
# 玩家與敵人的相對位置
# 不使用圖片中心，避免新動畫素材的高度影響方向判定。
# =====================================================
func get_combat_vector(player: Player) -> Vector2:
	if not is_instance_valid(player):
		return Vector2.ZERO
	var enemy_anchor: Node2D = get_node_or_null(enemy_aim_anchor_path) as Node2D
	var player_anchor: Node2D = player.get_node_or_null(player_aim_anchor_path) as Node2D
	var origin: Vector2 = enemy_anchor.global_position if enemy_anchor else global_position
	var destination: Vector2 = player_anchor.global_position if player_anchor else player.global_position
	origin += enemy_aim_offset # 套用敵人地面位置校正
	destination += player_aim_offset # 套用玩家地面位置校正
	return destination - origin # 取得玩家相對於敵人的方向及距離

func get_attack_trigger_distance() -> float:
	return stage2_attack_range if is_berserk else stage1_attack_range # 根據目前階段取得攻擊觸發距離

# =====================================================
# 四方向判定
# Godot 中 X 負值代表左方，Y 負值代表上方。
# =====================================================
func get_direction_suffix(dir: Vector2 = Vector2.ZERO) -> String:
	var target_dir: Vector2 = dir if dir != Vector2.ZERO else last_facing_vec
	var x_name: String
	var y_name: String
	if target_dir.x > 0.0:
		x_name = "right"
	elif target_dir.x < 0.0:
		x_name = "left"
	else:
		x_name = "left" if target_dir.y < 0.0 else "right" # 正上方使用左上，正下方使用右下
	y_name = "up" if target_dir.y < 0.0 else "down"
	return x_name + "_" + y_name # 合成對角線動畫後綴

# =====================================================
# 動畫名稱管理
# =====================================================
func get_action_animation(action: String, dir: Vector2 = Vector2.ZERO) -> String:
	var prefix: String = action
	if action == "transform":
		prefix = "berserk_transform" # 一階轉換至二階的專屬動畫
	elif is_berserk and not action.begins_with("berserk_"):
		match action:
			"move", "run":
				prefix = "berserk_run" # 二階移動統一使用跑步動畫
			"hurt", "idle":
				prefix = "berserk_idle" # 二階不使用受傷硬直動畫
			_:
				prefix = "berserk_" + action
	elif not is_berserk and action == "run":
		prefix = "move" # 一階沒有跑步動畫
	return prefix + "_" + get_direction_suffix(dir)

func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO) -> void:
	play_action(prefix, dir) # 統一由專用動畫函數處理

func play_action(action: String, dir: Vector2 = Vector2.ZERO, restart: bool = false, playback_speed: float = 1.0) -> bool:
	if not animated_sprite_2d or not animated_sprite_2d.sprite_frames:
		return false
	var animation_name: String = get_action_animation(action, dir)
	if not animated_sprite_2d.sprite_frames.has_animation(animation_name):
		if not _missing_animations.has(animation_name):
			_missing_animations[animation_name] = true
			push_warning("野蠻人缺少動畫：" + animation_name)
		return false
	if restart:
		animated_sprite_2d.stop() # 攻擊、死亡及變身可強制從第 0 格重新播放
	animated_sprite_2d.play(animation_name, playback_speed)
	return true

func has_one_shot_animation(action: String, dir: Vector2 = Vector2.ZERO) -> bool:
	if not animated_sprite_2d or not animated_sprite_2d.sprite_frames:
		return false
	var frames: SpriteFrames = animated_sprite_2d.sprite_frames
	var animation_name: String = action if frames.has_animation(action) else get_action_animation(action, dir)
	if not frames.has_animation(animation_name):
		return false
	return (
		frames.get_frame_count(animation_name) > 0
		and frames.get_animation_speed(animation_name) > 0.0
		and not frames.get_animation_loop(animation_name)
		and animated_sprite_2d.speed_scale > 0.0
	) # 確保一次性動畫具備正常播放完畢的條件

# =====================================================
# 玩家目標管理
# 一階：使用 DetectPlayer。
# 二階：直接取得 DataManager 註冊的玩家。
# =====================================================
func get_combat_target() -> Player:
	var target = DataManager.player_node if is_berserk else player_node
	if not is_instance_valid(target):
		return null
	if not target is Player:
		return null
	if target.is_dead or not target.is_inside_tree():
		return null
	return target as Player

func _on_detect_player_body_entered(body) -> void:
	if is_berserk:
		return # 二階不再使用偵測範圍
	super._on_detect_player_body_entered(body)

func _on_detect_player_body_exited(body) -> void:
	if is_berserk:
		return # 玩家離開偵測區域不影響二階追擊
	super._on_detect_player_body_exited(body)

# =====================================================
# 受傷與狂暴轉換
# =====================================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if is_dead or is_transforming or amount <= 0.0:
		return # 死亡、變身無敵及無效傷害不處理
	var threshold: float = float(max_hp) * berserk_trigger_percent / 100.0
	if not is_berserk and current_hp - amount <= threshold:
		is_berserk = true
		is_transforming = true
		current_hp = BERSERK_LOCK_HP # 攔截致命傷害，保留一滴血
		velocity = Vector2.ZERO
		knockback_force = Vector2.ZERO
		if knockback_component:
			knockback_component.knockback_force = Vector2.ZERO # 清除變身前殘留擊退
		update_hp_bar()
		if is_melee and is_instance_valid(DataManager.player_node):
			DataManager.player_node.add_ammo(1) # 保留近戰墨水回充
		end_sword_attack()
		set_contact_enabled(false)
		can_attack = false
		if detect_player_area:
			detect_player_area.set_deferred("monitoring", false) # 二階停用範圍偵測
		if vision_ray:
			vision_ray.enabled = false # 二階停用視線限制
		player_node = null
		can_see_player = false
		state_machine.change_state("BerserkTransition")
		return
	if is_berserk:
		amount = maxf(amount, current_hp) # 二階受到有效傷害即死亡
	super.take_damage(amount, attacker_pos, dir, is_melee, extra_knockback)

func finish_berserk_transition() -> void:
	is_transforming = false
	walk_speed = stage2_walk_speed # 套用狂暴移動速度
	melee_damage = stage2_damage # 套用狂暴武器傷害
	can_attack = true
	set_contact_enabled(false)
	state_machine.change_state("BerserkCharge")

func handle_hurt() -> void:
	if is_berserk or is_transforming:
		return # 二階及變身期間免疫受傷硬直
	super.handle_hurt()

func apply_stun(duration: float = 1.0) -> void:
	if is_berserk or is_transforming:
		return # 狂暴期間免疫暈眩
	super.apply_stun(duration)

# =====================================================
# 肉身傷害停用
# 保留函數相容性，不需要修改原本的死亡及變身腳本。
# =====================================================
func set_contact_enabled(_enabled: bool, _force_update: bool = false) -> void:
	if not body_hitbox:
		return
	body_hitbox.set_deferred("monitoring", false)
	for child in body_hitbox.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", true) # 無論一階或二階皆不啟用肉身傷害

# =====================================================
# 四方向武器碰撞框取得
# =====================================================
func get_sword_shape(suffix: String) -> CollisionShape2D:
	if not hitbox:
		return null
	var shape_name: String = "CollisionShape_" + suffix.trim_prefix("_")
	var collision: CollisionShape2D = hitbox.get_node_or_null(shape_name) as CollisionShape2D
	if not collision or not collision.shape:
		if not _missing_shapes.has(shape_name):
			_missing_shapes[shape_name] = true
			push_warning("野蠻人缺少武器碰撞框：" + shape_name)
		return null
	return collision

# =====================================================
# 物理形狀查詢
# 使用場景中已設定好的四方向碰撞框形狀、位置與旋轉角度。
# 查詢不代表造成傷害，只負責確認重疊目標。
# =====================================================
func _query_sword_targets(suffix: String) -> Array[Dictionary]:
	var collision: CollisionShape2D = get_sword_shape(suffix)
	if not collision or not is_inside_tree():
		return []
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape # 使用原本的武器碰撞形狀
	query.transform = collision.global_transform # 使用碰撞框的實際世界位置
	query.collision_mask = hitbox.collision_mask # 沿用原本 Hitbox 的碰撞遮罩
	query.collide_with_bodies = true # 偵測 CharacterBody2D
	query.collide_with_areas = true # 偵測 Hurtbox
	var excluded: Array[RID] = [get_rid(), hitbox.get_rid()]
	query.exclude = excluded # 排除敵人自己及武器 Area
	return get_world_2d().direct_space_state.intersect_shape(query, 32)

func _resolve_sword_target(collider: Object) -> Node2D:
	if not is_instance_valid(collider):
		return null
	if collider is Area2D:
		if not collider.has_method("take_damage") and collider.name != "Hurtbox":
			return null # 排除不相關的 Area2D
		return collider.get_parent() as Node2D
	return collider as Node2D

# =====================================================
# 攻擊距離與有效範圍檢查
# 兩項條件必須同時成立，才允許播放攻擊動畫。
# =====================================================
func can_reach_with_sword(player: Player, dir: Vector2) -> bool:
	if not is_instance_valid(player) or player.is_dead:
		return false
	var distance: float = get_combat_vector(player).length()
	var trigger_distance: float = get_attack_trigger_distance()
	if distance > trigger_distance:
		return false # 條件一：必須接近至 Inspector 設定的距離
	var suffix: String = get_direction_suffix(dir)
	for result in _query_sword_targets(suffix):
		var target: Node2D = _resolve_sword_target(result.get("collider"))
		if target == player:
			if debug_attack_geometry:
				print("【野蠻人攻擊】距離：", distance, " | 限制：", trigger_distance, " | 方向：", suffix, " | 動畫：", get_action_animation("attack", dir))
			return true # 條件二：該方向的武器碰撞框確實涵蓋玩家
	return false

func can_start_sword() -> bool:
	return not is_dead and not is_transforming and can_attack and not _sword_engaged

# =====================================================
# 武器攻擊流程管理
# =====================================================
func begin_sword_attack() -> void:
	_sword_engaged = true
	_sword_hit_targets.clear() # 每次新攻擊重置命中紀錄
	set_sword_window("", false) # 前搖階段不造成傷害

func set_sword_window(suffix: String, enabled: bool) -> void:
	_sword_active = enabled and _sword_engaged and not is_dead and not is_transforming
	_active_sword_suffix = suffix.trim_prefix("_") if _sword_active else ""
	if _sword_active and not get_sword_shape(_active_sword_suffix):
		_sword_active = false
		_active_sword_suffix = ""
	if not hitbox:
		return
	hitbox.set_deferred("monitoring", _sword_active)
	for child in hitbox.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			var shape_enabled: bool = _sword_active and child.name == "CollisionShape_" + _active_sword_suffix
			child.set_deferred("disabled", not shape_enabled) # 只開啟目前攻擊方向的碰撞框

func end_sword_attack() -> void:
	_sword_engaged = false
	set_sword_window("", false) # 關閉全部武器碰撞判定
	_sword_hit_targets.clear()

# =====================================================
# 武器傷害結算
# =====================================================
func _try_sword_hit(target: Node2D) -> void:
	if not _sword_active or is_dead or is_transforming:
		return
	if not is_instance_valid(target):
		return
	var target_id: int = target.get_instance_id()
	if _sword_hit_targets.has(target_id):
		return # 同一次揮刀不得重複結算
	if target is Player:
		var player: Player = target as Player
		if player.is_dead:
			return
		_sword_hit_targets[target_id] = true
		if player.is_invincible:
			return # 保留玩家翻滾及受傷無敵機制
		var hit_dir: Vector2 = global_position.direction_to(player.global_position)
		player.take_damage(melee_damage, global_position, hit_dir, false, sword_knockback)
	elif target is WhiteCat or target.is_in_group("white_cat"):
		if target.has_method("take_damage"):
			_sword_hit_targets[target_id] = true
			target.take_damage(melee_damage, global_position)

# =====================================================
# 覆寫父類別碰撞傷害事件
# 所有武器傷害由物理幀形狀查詢統一管理，避免重複扣血。
# =====================================================
func _on_hitbox_body_entered(_body: Node2D) -> void:
	pass

func _on_hitbox_area_entered(_area: Area2D) -> void:
	pass

func _check_hitbox_overlap() -> void:
	if not _sword_active or is_dead or is_transforming:
		return
	for result in _query_sword_targets(_active_sword_suffix):
		var target: Node2D = _resolve_sword_target(result.get("collider"))
		_try_sword_hit(target) # 只有指定攻擊影格才能造成傷害

# =====================================================
# 死亡處理
# =====================================================
func die() -> void:
	if is_dead:
		return
	end_sword_attack()
	set_contact_enabled(false)
	velocity = Vector2.ZERO
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
	visible = true
	modulate = Color.WHITE # 保證死亡演出可見
	super.die() # 保留父類別死亡、狀態切換及金幣掉落流程

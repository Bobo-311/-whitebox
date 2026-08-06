extends BaseCharacter             # 繼承基礎角色類別
class_name Enemy                  # 定義為 Enemy 類別

# ==========================================
# ⚙️ 匯出參數與預載資源
# ==========================================
@export var walk_speed: int = 150                   # 野豬漫遊速度
@export var sprint_speed: int = 450                # 野豬追擊速度
@export var attack_speed_multiplier: float = 2.5  # 衝撞攻擊速度倍率
@export var attack_time: float = 0.45              # 攻擊狀態維持時間
@export var melee_damage: float = 15.0             # 肉身衝撞傷害

const COIN_SCENE = preload("res://coin/coin.tscn") # 金幣場景

# 🌟【預載受擊特效】背部貫穿粒子特效
const HIT_IMPACT_PARTICLES = preload("res://近戰/hit_impact_particles.tscn")

# ==========================================
# 🔗 節點引用
# ==========================================
@onready var state_machine: StateMachine = $StateMachine       
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D 
@onready var hp_bar: ProgressBar = $HealthBar                  
@onready var vision_ray: RayCast2D = $VisionRay                 
@onready var hitbox: Area2D = get_node_or_null("Hitbox")       

# 🌟【組件化引用】擊退力與煞車摩擦力已交由 KnockbackComponent 節點在 Inspector 統一調整
@onready var knockback_component: KnockbackComponent = get_node_or_null("KnockbackComponent")

# ==========================================
# 📊 狀態與變數
# ==========================================
var can_see_player: bool = false                
var player_node: CharacterBody2D = null           
var last_facing_vec: Vector2 = Vector2.DOWN       
var has_hit_player: bool = false                  
var can_attack: bool = true                       

var original_sprite_scale: Vector2 = Vector2.ONE
var is_illuminated_by_cat: bool = false
var fade_tween: Tween = null

# ==========================================
# 🚀 初始化與物理幀處理
# ==========================================
func _ready() -> void:
	super._ready()
	
	if animated_sprite_2d:
		original_sprite_scale = animated_sprite_2d.scale
	
	if hitbox:
		if not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
			hitbox.body_entered.connect(_on_hitbox_body_entered)

	self.visible = false
	self.modulate.a = 0.0

func _physics_process(_delta: float) -> void:
	if is_dead and (not knockback_component or knockback_component.knockback_force.length() <= 0.0):
		velocity = Vector2.ZERO

	move_and_slide()
	_check_hitbox_overlap()
	
	if player_node != null:
		vision_ray.target_position = to_local(player_node.global_position)
		vision_ray.force_raycast_update()
		can_see_player = not vision_ray.is_colliding()
	else:
		can_see_player = false

# ==========================================
# 👁️ 迷霧現形系統
# ==========================================
func update_visibility() -> void:
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
		
	fade_tween = create_tween()
	
	if is_illuminated_by_cat:
		self.visible = true
		fade_tween.tween_property(self, "modulate:a", 1.0, 0.35)
	else:
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.35)
		fade_tween.tween_callback(func():
			if not is_illuminated_by_cat:
				self.visible = false
		)

# ==========================================
# 💥 戰鬥受擊與處決邏輯
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false) -> void:
	if is_dead: return
	
	current_hp = max(current_hp - amount, 0)
	update_hp_bar()
	
	var is_kill = (current_hp <= 0)
	
	# 1️⃣ 近戰邏輯處理：彈藥回復機制
	if is_melee and DataManager and DataManager.player_node:
		var p = DataManager.player_node
		if is_kill:
			if p.has_method("refill_full_ammo"):
				p.refill_full_ammo()
		else:
			if p.has_method("add_ammo"):
				p.add_ammo(1)
	
	# 2️⃣ 🌟【擊退與背部特效】
	var knockback_dir = dir if dir != Vector2.ZERO else (global_position - attacker_pos).normalized()
	if knockback_component and knockback_dir != Vector2.ZERO:
		var extra_kb = 1.8 if (is_kill and is_melee) else 1.0
		knockback_component.apply_knockback(knockback_dir, -1.0, extra_kb)
	
	# 🌟 生成背部貫穿爆發粒子
	spawn_back_impact_particles(knockback_dir, is_kill, is_melee)
	
	# 3️⃣ 播放受擊特效與頓幀
	play_hit_effects(attacker_pos, is_kill, is_melee)
	
	if is_kill:
		die()
	else:
		handle_hurt()

# 🌟【確定能看到版】背部貫穿受擊粒子生成器
func spawn_back_impact_particles(hit_dir: Vector2, is_kill: bool = false, is_melee: bool = false) -> void:
	if not HIT_IMPACT_PARTICLES: return
	
	var final_dir = hit_dir if hit_dir != Vector2.ZERO else Vector2.RIGHT
	var particles = HIT_IMPACT_PARTICLES.instantiate()
	
	# 1️⃣ 位置推離適中（30px）：剛好在野豬背後邊緣，不會推太遠進牆
	var back_offset = final_dir.normalized() * 80.0
	particles.global_position = global_position + back_offset
	particles.rotation = final_dir.angle()
	
	# 2️⃣ 關鍵修復！層級改為比野豬高一點點 (+1)，絕對不會被 TileMap 地面蓋住
	particles.z_index = self.z_index + 1
	
	# 3️⃣ 體積維持放大
	if is_kill and is_melee:
		particles.scale = Vector2(2.5, 2.5)
	else:
		particles.scale = Vector2(1.5, 1.5)
		
	get_parent().add_child(particles)
	
	if particles.has_method("restart"):
		particles.restart()
	particles.emitting = true
	
func play_hit_effects(_attacker_pos: Vector2 = Vector2.ZERO, is_kill: bool = false, is_melee: bool = false) -> void:
	if is_kill:
		if is_melee:
			if DataManager and DataManager.has_method("trigger_execution_hitstop"):
				DataManager.trigger_execution_hitstop(0.18, 0.08)
			get_tree().call_group("main_camera", "apply_shake", 10.0)
		else:
			if DataManager and DataManager.has_method("trigger_hitstop"):
				DataManager.trigger_hitstop(0.08, 0.05)
			get_tree().call_group("main_camera", "apply_shake", 6.5)
	else:
		if DataManager and DataManager.has_method("trigger_hitstop"):
			DataManager.trigger_hitstop(0.04, 0.1)
		get_tree().call_group("main_camera", "apply_shake", 3.5)
		
	# 畫面精靈圖閃光與變形
	if animated_sprite_2d:
		var tween = create_tween().set_parallel(true)
		var flash_dur = 0.2 if (is_kill and is_melee) else 0.06
		
		if animated_sprite_2d.material is ShaderMaterial:
			var mat = animated_sprite_2d.material as ShaderMaterial
			mat.set_shader_parameter("flash_modifier", 1.0)
			tween.tween_property(mat, "shader_parameter/flash_modifier", 0.0, flash_dur)
		else:
			animated_sprite_2d.modulate = Color(5, 5, 5) if is_kill else Color(3, 3, 3)
			tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, flash_dur)
		
		var scale_x = original_sprite_scale.x * (1.4 if (is_kill and is_melee) else 1.2)
		var scale_y = original_sprite_scale.y * (0.6 if (is_kill and is_melee) else 0.8)
		animated_sprite_2d.scale = Vector2(scale_x, scale_y)
		tween.tween_property(animated_sprite_2d, "scale", original_sprite_scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func handle_hurt() -> void:
	var state_name = state_machine.current_state.name.to_lower()
	if "stun" in state_name or "pant" in state_name: return 
	state_machine.change_state("EnemyHurt")

func die() -> void:
	if is_dead: return
	is_dead = true
	state_machine.change_state("EnemyDie")
	drop_coin()

func update_hp_bar() -> void:
	if hp_bar and hp_bar.has_method("update_bar"):
		hp_bar.update_bar(current_hp, max_hp)

func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO) -> void:
	var suffix = "" 
	var target_dir = dir if dir != Vector2.ZERO else last_facing_vec
	if abs(target_dir.x) > abs(target_dir.y): 
		suffix = "_right" if target_dir.x > 0 else "_left" 
	else: 
		suffix = "_down" if target_dir.y > 0 else "_up" 
	animated_sprite_2d.play(prefix + suffix)

func drop_coin() -> void:
	if COIN_SCENE:
		for i in range(5):
			var delay = randf_range(0.01, 0.1)
			get_tree().create_timer(delay).connect("timeout", func():
				var coin = COIN_SCENE.instantiate()
				var spawn_pos = global_position
				if DataManager and DataManager.player_node:
					var dir_to_player = global_position.direction_to(DataManager.player_node.global_position)
					var safe_offset = dir_to_player * randf_range(15.0, 30.0)
					var random_jitter = Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
					spawn_pos = global_position + safe_offset + random_jitter
				else:
					spawn_pos = global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
				var local_pos = get_parent().to_local(spawn_pos)
				coin.position = local_pos
				get_parent().add_child(coin)
			)

# ==========================================
# 🛡️ 碰撞傷害機制
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void: 
	var parent = area.get_parent() 
	if parent is Player or parent.is_in_group("player") or parent.name == "player":
		_apply_damage_and_knockback(parent, area)
	elif parent is WhiteCat or parent.is_in_group("white_cat"):
		if parent.has_method("take_damage"):
			parent.take_damage(melee_damage, global_position)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player or body.is_in_group("player") or body.name == "player":
		_apply_damage_and_knockback(body, null)

func _apply_damage_and_knockback(target: Node2D, target_area: Area2D = null) -> void:
	var knockback_dir: Vector2 = (target.global_position - global_position).normalized()
	if target_area and target_area.has_method("take_damage"):
		target_area.take_damage(melee_damage, global_position)
	elif target.has_method("take_damage"):
		target.take_damage(melee_damage, global_position, knockback_dir)

func _check_hitbox_overlap() -> void:
	if not hitbox: return
	for body in hitbox.get_overlapping_bodies():
		if body is Player or body.is_in_group("player") or body.name == "player":
			_apply_damage_and_knockback(body, null)

func _on_detect_player_body_entered(body) -> void: 
	if body is Player or body.is_in_group("player") or body.name == "player": 
		player_node = body

func _on_detect_player_body_exited(body) -> void: 
	if body == player_node or body.is_in_group("player"): 
		player_node = null

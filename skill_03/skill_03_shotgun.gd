extends Area2D

@export_group("Shotgun Settings")
@export var base_damage: float = 30.0
@export var knockback_force: float = 3.5  # 🌟 散彈槍專屬的超強擊退倍率
@export var duration: float = 0.2         # 特效殘留時間

var shooter: Node2D = null
var received_buff: float = 1.0
var direction: Vector2 = Vector2.RIGHT

@onready var particles: GPUParticles2D = get_node_or_null("GPUParticles2D")

func _ready() -> void:
	# 1. 瞬間引爆黃色粒子
	if particles:
		particles.restart()
		particles.emitting = true
		
	# 2. 等待兩個物理幀，讓 Area2D 的碰撞遮罩確實覆蓋到怪物身上
	await get_tree().physics_frame
	await get_tree().physics_frame 
	
	_deal_damage()
	
	# 3. 延遲一段時間後，自動把這個隱形的判定區刪除
	await get_tree().create_timer(duration).timeout
	queue_free()

func _deal_damage() -> void:
	var bodies = get_overlapping_bodies()
	var areas = get_overlapping_areas()
	var targets = bodies + areas
	
	var has_hit_something = false
	
	for target in targets:
		# 排除發射者自己與貓咪
		if target == shooter or target.is_in_group("player") or target.is_in_group("white_cat"):
			continue
			
		var final_damage = base_damage * received_buff
		
		# ==========================================
		# 🌟 1. 處理扣血與超強擊退
		# ==========================================
		if target.has_method("take_damage"):
			target.take_damage(final_damage, global_position, direction, false, knockback_force)
			has_hit_something = true
			
		elif target.get_parent() and target.get_parent().has_method("take_damage"):
			target.get_parent().take_damage(final_damage, global_position, direction, false, knockback_force)
			has_hit_something = true
			
		# ==========================================
		# 🌟 2. 處理暈眩控場 (直接越過 Hurtbox 問老爸)
		# ==========================================
		if target.has_method("apply_stun"):
			target.apply_stun(1.0)
			
		elif target.get_parent() and target.get_parent().has_method("apply_stun"):
			target.get_parent().apply_stun(1.0)
			
	# ==========================================
	# 🌟 3. 擊中停頓 (Hitstop)
	# ==========================================
	if has_hit_something and DataManager and DataManager.has_method("hitstop"):
		DataManager.hitstop(0.12)

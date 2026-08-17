extends Area2D

@export_group("Shotgun Settings")
@export var base_damage: float = 35.0
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
		
	# 2. 等待一個物理幀，讓 Area2D 確實覆蓋到怪物身上
	await get_tree().physics_frame
	await get_tree().physics_frame # 保險起見等兩幀，絕對不會漏判
	
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
		# 排除玩家與白貓自己
		if target == shooter or target.is_in_group("player") or target.is_in_group("white_cat"):
			continue
			
		var final_damage = base_damage * received_buff
		
		# 🌟 呼叫你們寫好的傷害系統，並傳入超強的 knockback_force (第 5 個參數)
		if target.has_method("take_damage"):
			target.take_damage(final_damage, global_position, direction, false, knockback_force)
			has_hit_something = true
			
		elif target.get_parent() and target.get_parent().has_method("take_damage"):
			target.get_parent().take_damage(final_damage, global_position, direction, false, knockback_force)
			has_hit_something = true
			
	# 如果有打中任何東西，可以額外觸發更重的頓幀！
	if has_hit_something and DataManager and DataManager.has_method("hitstop"):
		DataManager.hitstop(0.12) # 散彈槍專屬的重擊頓幀

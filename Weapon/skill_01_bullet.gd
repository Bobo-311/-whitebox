extends Area2D                                # 純粹的技能攻擊判定 (Hitbox)

# 🌟 預載剛做好的粒子特效場景 (請確保路徑與你的檔名一致)
const IMPACT_EFFECT = preload("res://Bullet/ink_impact_effect.tscn")

@export var skill_01_attack_damage: float = 15.0 # 技能基礎傷害
@export var speed: float = 1200.0                # 子彈飛行速度

@export var trail_lifetime: float = 0.22         # 拖尾存活時間 (秒)
@export var min_distance: float = 6.0            # 每移動 6px 採集一個關鍵點

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 動畫節點
@onready var trail_line: Line2D = get_node_or_null("TrailLine")      # 抓取拖尾節點

var direction: Vector2 = Vector2.ZERO         # 飛行方向
var travel_dir: Vector2 = Vector2.ZERO        # 擊退/發射方向
var shooter: CharacterBody2D = null           # 記錄發射者 (Player)
var received_buff: float = 1.0                # 接收過飽和倍率 (1.0 或 1.5)

var raw_points: Array[Vector2] = []
var raw_times: Array[float] = []

func _ready() -> void:
	if animated_sprite_2d:
		animated_sprite_2d.play()
		
	if direction == Vector2.ZERO and travel_dir != Vector2.ZERO:
		direction = travel_dir
		
	if direction != Vector2.ZERO:
		rotation = direction.angle()
		
	if trail_line:
		trail_line.top_level = true
		trail_line.clear_points()

	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			destroy_bullet()
	)

func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO and travel_dir != Vector2.ZERO:
		direction = travel_dir

	if direction != Vector2.ZERO and rotation != direction.angle():
		rotation = direction.angle()

	position += direction * speed * delta
	
	_update_trail_logic()

func _update_trail_logic() -> void:
	if not is_instance_valid(trail_line):
		return
		
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if raw_points.is_empty() or global_position.distance_to(raw_points.back()) >= min_distance:
		raw_points.append(global_position)
		raw_times.append(current_time)
		
	while not raw_times.is_empty() and (current_time - raw_times.front()) > trail_lifetime:
		raw_points.pop_front()
		raw_times.pop_front()
		
	if raw_points.size() < 2:
		trail_line.clear_points()
		return
		
	var curve = Curve2D.new()
	for pt in raw_points:
		curve.add_point(pt)
		
	trail_line.points = curve.tessellate(4, 4)

# 🌟 生成命中潑墨粒子
func spawn_impact_effect() -> void:
	if IMPACT_EFFECT:
		var effect = IMPACT_EFFECT.instantiate()
		effect.global_position = global_position
		effect.rotation = rotation # 讓墨汁順著子彈飛來的反方向噴濺
		get_parent().add_child(effect)

func destroy_bullet() -> void:
	spawn_impact_effect() # 🌟 銷毀前生成墨汁爆裂
	
	if is_instance_valid(trail_line) and raw_points.size() > 0:
		var world = get_parent()
		if world:
			remove_child(trail_line)
			world.add_child(trail_line)
			
			var tween = trail_line.create_tween().set_parallel(true)
			tween.tween_property(trail_line, "modulate:a", 0.0, trail_lifetime)
			tween.chain().tween_callback(trail_line.queue_free)
			
	queue_free()

# ==========================================
# 🌟 碰撞判定
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent == shooter or (parent and (parent.is_in_group("player") or parent.is_in_group("white_cat") or parent is WhiteCat)):
		return

	if area is Hurtbox or area.name == "Hurtbox" or area.has_method("take_damage"): 
		var final_damage: float = skill_01_attack_damage * received_buff
		if area.has_method("take_damage"):
			area.take_damage(final_damage, global_position, direction) 
		if parent and parent.has_method("handle_hurt"):
			parent.handle_hurt()
		destroy_bullet()

func _on_body_entered(body: Node2D) -> void:
	if body == shooter or body.is_in_group("player") or body.is_in_group("white_cat") or body is WhiteCat:
		return

	if body is Enemy or body.is_in_group("enemies"):
		var final_damage: float = skill_01_attack_damage * received_buff
		if body.has_method("take_damage"):
			body.take_damage(final_damage, global_position, direction)
		if body.has_method("handle_hurt"):
			body.handle_hurt()
		destroy_bullet()
		return

	if body is TileMap or body is TileMapLayer or body is StaticBody2D:
		destroy_bullet()
		return

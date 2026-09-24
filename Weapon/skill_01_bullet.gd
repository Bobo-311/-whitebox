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
var is_destroying: bool = false               # 🌟 防呆：避免同一幀重複執行銷毀

func _ready() -> void:
	# ==========================================
	# 🌟 高低差特權判定 (依據 image_9bc19d.png 的圖層設定)
	# ==========================================
	set_collision_mask_value(11, true)
	set_collision_mask_value(12, true)
	set_collision_mask_value(13, true)
	
	if DataManager.player_node:
		var elev = DataManager.player_node.current_elevation
		# 👇 加入這行，看看子彈出生的時候，以為阿尼在幾樓？
		print("【系統】發射子彈！阿尼現在的高度是：", elev)
		if elev >= 1: set_collision_mask_value(11, false) # 無視 1 樓懸崖
		if elev >= 2: set_collision_mask_value(12, false) # 無視 2 樓懸崖
		if elev >= 3: set_collision_mask_value(13, false) # 無視 3 樓懸崖
	# ==========================================
	if animated_sprite_2d:
		animated_sprite_2d.play("default")
		
	if direction == Vector2.ZERO and travel_dir != Vector2.ZERO:
		direction = travel_dir
		
	if direction != Vector2.ZERO:
		rotation = direction.angle()
		
	if trail_line:
		# 🌟 就是這裡！把它刪掉或加上 # 註解
		# trail_line.top_level = true 
		trail_line.clear_points()

	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			destroy_bullet()
	)

func _physics_process(delta: float) -> void:
	if is_destroying: return

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
	
	# ==========================================
	# 🌟 關鍵修改 1：算出子彈「頭部」的絕對座標
	# direction * 35.0 代表往子彈飛行的方向往前推 35 像素。
	# 你可以微調 35.0 這個數字，直到拖尾剛好貼齊子彈的最前端！
	# ==========================================
	var tip_pos = global_position + (direction * 35.0)
	
	# 這裡原本的 global_position 全部換成 tip_pos
	if raw_points.is_empty() or tip_pos.distance_to(raw_points.back()) >= min_distance:
		raw_points.append(tip_pos)
		raw_times.append(current_time)
		
	while not raw_times.is_empty() and (current_time - raw_times.front()) > trail_lifetime:
		raw_points.pop_front()
		raw_times.pop_front()
		
	if raw_points.size() < 2:
		trail_line.clear_points()
		return
		
	# ==========================================
	# 🌟 關鍵修改 2：讓拖尾的「原點」也跟隨子彈頭部
	# ==========================================
	trail_line.global_position = global_position
		
	var curve = Curve2D.new()
	for pt in raw_points:
		# 這裡就會以子彈頭部為中心去畫線了
		curve.add_point(trail_line.to_local(pt))
		
	trail_line.points = curve.tessellate(4, 4)
	
# 🌟 生成命中潑墨粒子
func spawn_impact_effect() -> void:
	if IMPACT_EFFECT:
		var effect = IMPACT_EFFECT.instantiate()
		
		# 讓特效旋轉 (包裝盒大法)
		effect.rotation = direction.angle() + PI 
		
		# ==========================================
		# 🌟 關鍵修改：讓爆炸位置往前方推！
		# direction 是一個長度為 1 的方向向量。
		# 乘上一個數字 (例如 25.0)，就可以把特效生成點往前推 25 像素。
		# 如果還是太遠，就把 25 繼續調大 (例如 30, 40)；如果推過頭卡進牆壁裡了，就調小。
		# ==========================================
		effect.global_position = global_position + (direction * 25.0)
		
		get_tree().current_scene.add_child(effect)
		
func destroy_bullet() -> void:
	if is_destroying: return
	is_destroying = true

	spawn_impact_effect()
	
	# 🌟 觸發相機震動
	get_tree().call_group("main_camera", "apply_shake", 8.0)
	
	# 🌟 將拖尾交給場景，使其平滑淡出後銷毀
	if is_instance_valid(trail_line) and raw_points.size() > 0:
		var world = get_parent()
		if world and trail_line.get_parent() == self:
			# ==========================================
			# 🌟 關鍵修正：同時記住位置與角度！
			# ==========================================
			var prev_pos = trail_line.global_position
			var prev_rot = trail_line.global_rotation # 👈 關鍵新增 1：記住子彈摧毀前的絕對角度
			
			remove_child(trail_line)
			world.add_child(trail_line)
			
			trail_line.global_position = prev_pos
			trail_line.global_rotation = prev_rot     # 👈 關鍵新增 2：還原角度，不讓它彈回 0 度(朝右)
			# ==========================================
			
			var tween = trail_line.create_tween().set_parallel(true)
			tween.tween_property(trail_line, "modulate:a", 0.0, trail_lifetime)
			tween.chain().tween_callback(trail_line.queue_free)
			
	queue_free()

# ==========================================
# 🌟 碰撞判定
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	if is_destroying: return

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
	if is_destroying: return

	if body == shooter or body.is_in_group("player") or body.is_in_group("white_cat") or body is WhiteCat:
		return

	if body is BaseEnemy or body.is_in_group("enemies"):
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

extends CharacterBody2D
class_name WhiteCat

@export var move_speed: float = 500.0          # 白貓正常移動速度
@export var max_follow_distance: float = 700.0 # 離玩家的最遠極限距離

# 🌟【受傷與無敵時間設定】(可在右側 Inspector 面板直接微調)
@export var stun_duration: float = 2.0          # 白貓受傷變暗的持續秒數 (2秒)
@export var invincibility_duration: float = 1.5 # 白貓恢復明亮後的無敵閃耀秒數 (1.5秒)
@export var always_pass_through_enemies: bool = false # 🌟 若打勾：白貓連平時都不會卡住怪物（只會撞牆壁）

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var light_area: Area2D = $LightArea
# 🌟【關鍵升級】改為抓取 AnimatedSprite2D（相容舊名 Sprite2D 防呆）
@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") if has_node("AnimatedSprite2D") else get_node_or_null("Sprite2D")
@onready var point_light_2d: PointLight2D = get_node_or_null("PointLight2D") # 燈光節點

var player_node: Node2D = null
var is_stunned: bool = false                   # 受傷/暈眩狀態開關
var is_invincible: bool = false                # 恢復後的無敵狀態開關
var stun_tween: Tween = null                   # 紀錄動畫物件
var flash_tween: Tween = null                  # 紀錄馬力歐閃耀特效的 Tween

# 🌟 記憶白貓本體與子節點 (Hurtbox 等) 的原始碰撞 Layer 與 Mask，供無敵結束後還原
var original_collision_layer: int = 1
var original_collision_mask: int = 1
var child_area_layers: Dictionary = {}         # 紀錄底下 Area2D 的原始 layer/mask
var ignored_enemies: Array[PhysicsBody2D] = [] # 紀錄目前被設為穿透例外的怪物

# 🌟 紀錄白貓最後面對的 4 方位，供停下來時播放對應的 idle 動畫
var facing_direction: String = "down"

# 🌟 召回狀態開關 (加速衝回玩家身邊)
var is_recalling: bool = false

# 🌟 自動記憶編輯器中設定的原始數值
var original_light_scale: Vector2 = Vector2.ONE # 預設圈圈大小
var original_light_energy: float = 2.0          # 預設燈光亮度

# 白貓主動監控的敵人動態清單
var detected_enemies: Array[Node2D] = []

func _ready() -> void:
	add_to_group("white_cat")
	
	# 1. 記憶開局原始的物理碰撞層設定
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	
	# 2. 🌟 關鍵防呆：LightArea 只負責偵測敵人(Mask)，本身絕對不能有 Layer，否則怪物會把光圈當成實體卡住！
	if light_area:
		light_area.collision_layer = 0
		
	# 3. 記憶白貓底下其他 Area2D (例如 Hurtbox) 的原始 Layer 與 Mask
	for child in get_children():
		if child is Area2D and child != light_area:
			child_area_layers[child] = {
				"layer": child.collision_layer,
				"mask": child.collision_mask
			}
	
	# 自動抓取場景中的玩家
	player_node = get_tree().get_first_node_in_group("player")
	if not player_node and DataManager:
		player_node = DataManager.player_node
		
	# 🌟【關鍵一行】將玩家設定為物理例外，貓與玩家絕對不會互相推擠/擋路！
	if player_node:
		add_collision_exception_with(player_node)	
		
	# 開局自動存下 Inspector 面板設定的亮度與縮放大小
	if light_area:
		original_light_scale = light_area.scale
	if point_light_2d:
		original_light_energy = point_light_2d.energy

	# 設定 NavigationAgent 尋路參數
	nav_agent.path_desired_distance = 12.0
	nav_agent.target_desired_distance = 12.0

	# 自動連接感應訊號
	if light_area:
		if not light_area.body_entered.is_connected(_on_light_area_body_entered):
			light_area.body_entered.connect(_on_light_area_body_entered)
		if not light_area.body_exited.is_connected(_on_light_area_body_exited):
			light_area.body_exited.connect(_on_light_area_body_exited)

	# 開局先播待機動畫
	play_animation("idle")

	# 開局主動掃描一開場就在光圈內的野豬
	await get_tree().process_frame
	_check_initial_overlapping_enemies()
	
	if always_pass_through_enemies:
		_set_cat_collision_enabled(false)

# 掃描開局就在光圈裡的敵人
func _check_initial_overlapping_enemies() -> void:
	if not light_area: return
	var bodies = light_area.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemies") or body is BaseEnemy:
			_on_light_area_body_entered(body)

# ==========================================
# 🌟 白貓受傷處置 (變暗 2 秒 + 徹底清空所有 Layer + 轉移怪物仇恨)
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	# 已經在虛弱變暗狀態、或正處於 1.5 秒無敵閃耀期間，皆免疫傷害！
	if is_stunned or is_invincible: 
		return
		
	is_stunned = true
	is_recalling = false # 受傷時解除召回狀態
	velocity = Vector2.ZERO # 立刻停在原地
	play_animation("idle") # 停下時切回待機動畫
	
	# 🌟 關鍵修正：徹底把白貓本體與 Hurtbox 的 Layer 和 Mask 全部歸零，並強制怪物放棄鎖定白貓！
	_set_cat_collision_enabled(false)
	_clear_cat_from_enemy_targets()
	
	print("😿【白貓受傷】受到了來自敵人的傷害！進入虛弱狀態 ", stun_duration, " 秒（已清空所有碰撞 Layer）！")

	if stun_tween and stun_tween.is_running():
		stun_tween.kill()

	stun_tween = create_tween().set_parallel(true)

	if point_light_2d:
		stun_tween.tween_property(point_light_2d, "energy", original_light_energy * 0.25, 0.25)

	if light_area:
		stun_tween.tween_property(light_area, "scale", original_light_scale * 0.4, 0.25)

	stun_tween.tween_property(self, "modulate", Color(0.6, 0.6, 0.6, 0.7), 0.25)

	# 等待 2 秒 (stun_duration) 後恢復明亮
	get_tree().create_timer(stun_duration).timeout.connect(_recover_from_damage)

# 🌟 復原狀態 (恢復明亮 + 啟動 1.5 秒馬力歐無敵閃耀，期間維持穿怪能力！)
func _recover_from_damage() -> void:
	if not is_stunned: return

	print("🐱【白貓復原】狀態恢復！燈光展開並獲得 ", invincibility_duration, " 秒無敵閃耀狀態！")

	if stun_tween and stun_tween.is_running():
		stun_tween.kill()

	# 解除虛弱鎖定（可以開始移動），並開啟 1.5 秒馬力歐無敵閃耀
	is_stunned = false
	_start_invincibility_flash()

	stun_tween = create_tween().set_parallel(true)

	if point_light_2d:
		stun_tween.tween_property(point_light_2d, "energy", original_light_energy, 0.4)

	if light_area:
		stun_tween.tween_property(light_area, "scale", original_light_scale, 0.4)

	stun_tween.tween_property(self, "modulate", Color.WHITE, 0.2)

	stun_tween.chain().tween_callback(func():
		_check_initial_overlapping_enemies()
	)

# 🌟 徹底控制白貓與底下所有 Area2D 的 Layer / Mask 與物理碰撞開關
func _set_cat_collision_enabled(enabled: bool) -> void:
	# 1. 切換白貓本體的 CollisionShape2D
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)
			
	# 2. 切換 NavigationAgent2D 的 RVO 避障 (防止尋路系統把停下的白貓當成障礙物互卡)
	if nav_agent:
		nav_agent.set_deferred("avoidance_enabled", enabled)
			
	# 3. 🌟 關鍵：將白貓底下除了 LightArea 以外的所有 Area2D (如 Hurtbox) 的 Layer 與 Mask 同步歸零/還原！
	for area in child_area_layers.keys():
		if is_instance_valid(area):
			area.set_deferred("monitoring", enabled)
			area.set_deferred("monitorable", enabled)
			if enabled:
				area.set_deferred("collision_layer", child_area_layers[area]["layer"])
				area.set_deferred("collision_mask", child_area_layers[area]["mask"])
			else:
				area.set_deferred("collision_layer", 0)
				area.set_deferred("collision_mask", 0)
			for shape in area.get_children():
				if shape is CollisionShape2D or shape is CollisionPolygon2D:
					shape.set_deferred("disabled", not enabled)

	# 4. 🌟 關鍵：同時切換白貓本體的 collision_layer 與 collision_mask，並對全場怪物加入雙向穿透例外！
	if enabled:
		set_deferred("collision_layer", original_collision_layer)
		set_deferred("collision_mask", original_collision_mask)
		for enemy in ignored_enemies:
			if is_instance_valid(enemy):
				remove_collision_exception_with(enemy)
				enemy.remove_collision_exception_with(self)
		ignored_enemies.clear()
	else:
		# Godot 4 雙向碰撞規則：必須把 Layer 跟 Mask 同時設為 0，怪物才不會撞上白貓！
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 0)
		
		var scene_root = get_tree().current_scene
		if scene_root:
			var all_bodies = scene_root.find_children("*", "PhysicsBody2D", true, false)
			for body in all_bodies:
				if body != self and body != player_node and (body is BaseEnemy or body.is_in_group("enemies") or body is CharacterBody2D):
					if not ignored_enemies.has(body):
						add_collision_exception_with(body)
						body.add_collision_exception_with(self)
						ignored_enemies.append(body)

# 🌟 強制讓正在追擊/卡在白貓身上的怪物轉移目標（改追玩家或解除鎖定）
func _clear_cat_from_enemy_targets() -> void:
	var scene_root = get_tree().current_scene
	if not scene_root: return
	
	var all_nodes = scene_root.find_children("*", "Node2D", true, false)
	for node in all_nodes:
		if node is BaseEnemy or node.is_in_group("enemies"):
			# 檢查怪物常見的追擊目標變數名稱，若正鎖定白貓則立刻改為玩家！
			for prop_name in ["target", "current_target", "chase_target", "target_node", "aggro_target"]:
				if prop_name in node and node.get(prop_name) == self:
					node.set(prop_name, player_node)

# 🌟 馬力歐式受傷恢復無敵閃耀特效 (持續 1.5 秒，結束後才恢復物理碰撞)
func _start_invincibility_flash() -> void:
	is_invincible = true
	
	if flash_tween and flash_tween.is_running():
		flash_tween.kill()
		
	var target_visual: CanvasItem = anim_sprite if anim_sprite else self
	# 計算閃爍次數：每 0.12 秒完成一次「亮白閃耀 ➔ 半透明」循環
	var loop_count: int = max(1, int(invincibility_duration / 0.12))
	
	flash_tween = create_tween().set_loops(loop_count)
	# 高亮閃耀 (HDR 微發光感)
	flash_tween.tween_property(target_visual, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.06)
	# 瞬間半透明殘影 (經典馬力歐無敵閃爍感)
	flash_tween.tween_property(target_visual, "modulate", Color(1.0, 1.0, 1.0, 0.2), 0.06)
	
	# 等待 1.5 秒無敵時間結束後，自動關閉無敵、還原正常顏色，並重新開啟物理碰撞！
	await get_tree().create_timer(invincibility_duration).timeout
	if flash_tween and flash_tween.is_running():
		flash_tween.kill()
	if is_instance_valid(target_visual):
		target_visual.modulate = Color.WHITE
	is_invincible = false
	
	# 🌟 無敵閃爍徹底結束後，才恢復白貓的物理碰撞與 Layer
	if not is_stunned and not always_pass_through_enemies:
		_set_cat_collision_enabled(true)
	print("🛡️【白貓無敵結束】1.5 秒無敵閃耀時間結束，已恢復物理碰撞與 Layer。")

# ==========================================
# 白貓探測敵人的主動邏輯
# ==========================================
func _on_light_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") or body is BaseEnemy:
		if not detected_enemies.has(body):
			detected_enemies.append(body)
			
		# 如果新走進來的怪物遇到正在受傷或無敵的白貓，立刻將牠加入穿透名單！
		if (is_stunned or is_invincible or always_pass_through_enemies) and body is PhysicsBody2D:
			if not ignored_enemies.has(body):
				add_collision_exception_with(body)
				body.add_collision_exception_with(self)
				ignored_enemies.append(body)
			
		if "is_illuminated_by_cat" in body:
			body.is_illuminated_by_cat = true
			
		if body.has_method("update_visibility"):
			body.update_visibility()
			
		print("👁️【白貓探測】光圈照亮敵人：", body.name)

func _on_light_area_body_exited(body: Node2D) -> void:
	if detected_enemies.has(body):
		detected_enemies.erase(body)
		
		if "is_illuminated_by_cat" in body:
			body.is_illuminated_by_cat = false
			
		if body.has_method("update_visibility"):
			body.update_visibility()
			
		print("🙈【白貓探測】敵人離開光圈：", body.name)

# ==========================================
# 操作與移動邏輯 (受傷時禁止移動)
# ==========================================
func _input(event: InputEvent) -> void:
	# 🌟 改為判斷阿尼(主人)的狀態，主人在看劇情時，貓咪不接收操作指令
	if DataManager.player_node and DataManager.player_node.is_in_dialogue:
		return
		
	# 🌟 虛弱期間直接屏蔽玩家操作指令
	if is_stunned: return
	
	# 按下 Space 瞬間觸發一次召回通知
	if (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE) or event.is_action_pressed("cat_recall"):
		if player_node:
			is_recalling = true
			nav_agent.target_position = player_node.global_position
			print("🐱⚡【白貓召回】啟動 1.5 倍速衝回主角身邊！")

func _physics_process(_delta: float) -> void:
	# 🌟 改為判斷阿尼(主人)的狀態：跑劇情時不准亂動，並且「踩煞車」避免滑行！
	if DataManager.player_node and DataManager.player_node.is_in_dialogue:
		is_recalling = false
		velocity = Vector2.ZERO
		play_animation("idle") # 劇情停下時播待機動畫
		move_and_slide()
		return
		
	# 🌟 虛弱期間停在原地：不呼叫 move_and_slide()，並且持續清除怪物對白貓的鎖定！
	if is_stunned:
		velocity = Vector2.ZERO
		play_animation("idle")
		_clear_cat_from_enemy_targets()
		return

	# 1️⃣ 檢查是否正按著右鍵指派移動 (cat_move)
	var is_holding_move: bool = Input.is_action_pressed("cat_move")
	
	# 2️⃣ 檢查是否正按著空白鍵召回 (cat_recall)
	var is_holding_space: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("cat_recall")

	# 🌟【長按右鍵邏輯】：每一幀即時追蹤滑鼠位置 (限制在主角範圍內)
	if is_holding_move:
		is_recalling = false
		var target_pos = get_global_mouse_position()
		
		# 限制離玩家的極限距離
		if player_node:
			var dist_to_player = player_node.global_position.distance_to(target_pos)
			if dist_to_player > max_follow_distance:
				var dir = (target_pos - player_node.global_position).normalized()
				target_pos = player_node.global_position + dir * max_follow_distance
		
		nav_agent.target_position = target_pos

	# 🌟【召回邏輯】：長按或單次觸發時，即時更新玩家座標
	elif is_holding_space and player_node:
		is_recalling = true
		nav_agent.target_position = player_node.global_position
	elif is_recalling and player_node:
		nav_agent.target_position = player_node.global_position

	# 抵達目的地（回到身邊或指派點）
	if nav_agent.is_navigation_finished():
		if not is_holding_space:
			is_recalling = false
		velocity = Vector2.ZERO
		play_animation("idle") # 🌟 抵達終點時，自動播對應方向的 4 方位待機動畫
		move_and_slide()
		return

	var next_path_pos: Vector2 = nav_agent.get_next_path_position()
	var move_dir: Vector2 = global_position.direction_to(next_path_pos)
	
	# 計算實際移動速度：召回/跟隨狀態下為 1.5 倍速，平時為原速
	var current_speed: float = move_speed * 1.5 if is_recalling else move_speed
	velocity = move_dir * current_speed
	
	# 🌟 播放 8 方位移動動畫
	play_animation("move", move_dir)
		
	move_and_slide()

# ==========================================
# 🌟 白貓專屬：尋路 8 方向移動與 4 方向待機動畫系統
# ==========================================
func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO) -> void:
	if not anim_sprite or not (anim_sprite is AnimatedSprite2D) or not anim_sprite.sprite_frames:
		return

	var target_suffix: String = facing_direction

	# 當有傳入移動方向向量時，計算 8 方位與更新 4 方位記憶
	if dir != Vector2.ZERO:
		var y_str: String = ""
		var x_str: String = ""
		
		# 尋路向量為 360 度連續角度，使用 sin(22.5度) ≈ 0.38 作為八方位切分標準
		if dir.y < -0.38: y_str = "up"
		elif dir.y > 0.38: y_str = "down"
		
		if dir.x < -0.38: x_str = "left"
		elif dir.x > 0.38: x_str = "right"
		
		var eight_way_dir: String = ""
		if y_str != "" and x_str != "":
			eight_way_dir = y_str + "_" + x_str # 例如 down_right, up_left
		else:
			eight_way_dir = y_str if y_str != "" else x_str

		# 更新 4 方位核心記憶（供停下來時的 idle 使用）
		if abs(dir.x) > abs(dir.y):
			facing_direction = "right" if dir.x > 0 else "left"
		else:
			facing_direction = "down" if dir.y > 0 else "up"

		if eight_way_dir != "":
			target_suffix = eight_way_dir
		else:
			target_suffix = facing_direction

	var anim_name: String = prefix + "_" + target_suffix

	# 【自動降級防呆 1】：如果找不到 8 方位（例如 idle_down_right），自動退回 4 方位（idle_down 或 idle_right）
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		anim_name = prefix + "_" + facing_direction

	# 【自動降級防呆 2】：如果你在編輯器裡把移動動畫命名為 walk_ 而不是 move_，系統也會自動幫你找 walk_
	if not anim_sprite.sprite_frames.has_animation(anim_name) and prefix == "move":
		var walk_8 = "walk_" + target_suffix
		var walk_4 = "walk_" + facing_direction
		if anim_sprite.sprite_frames.has_animation(walk_8):
			anim_name = walk_8
		elif anim_sprite.sprite_frames.has_animation(walk_4):
			anim_name = walk_4

	if not anim_sprite.sprite_frames.has_animation(anim_name):
		return

	# 避免每一幀重複從第 0 格重頭播放同一個動畫
	if anim_sprite.animation != anim_name or not anim_sprite.is_playing():
		anim_sprite.play(anim_name)

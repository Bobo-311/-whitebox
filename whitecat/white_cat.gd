extends CharacterBody2D
class_name WhiteCat

@export var move_speed: float = 300.0          # 白貓移動速度
@export var max_follow_distance: float = 500.0   # 離玩家的最遠極限距離

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var light_area: Area2D = $LightArea
@onready var sprite: Sprite2D = $Sprite2D
@onready var point_light_2d: PointLight2D = get_node_or_null("PointLight2D") # 燈光節點

var player_node: Node2D = null
var is_stunned: bool = false                     # 受傷/暈眩狀態開關
var stun_tween: Tween = null                    # 紀錄動畫物件

# 🌟 自動記憶編輯器中設定的原始數值 (避免程式碼硬寫死 1.0)
var original_light_scale: Vector2 = Vector2.ONE # 預設圈圈大小
var original_light_energy: float = 2.0          # 預設燈光亮度 (對齊 Inspector 2.0)

# 白貓主動監控的敵人動態清單
var detected_enemies: Array[Node2D] = []

func _ready() -> void:
	add_to_group("white_cat")
	
	# 自動抓取場景中的玩家
	player_node = get_tree().get_first_node_in_group("player")
	if not player_node and DataManager:
		player_node = DataManager.player_node
	# 🌟【關鍵一行】將玩家設定為物理例外，貓與玩家絕對不會互相推擠/擋路！
	if player_node:
		add_collision_exception_with(player_node)	
		
	# 🌟【自動防呆】開局自動存下你在 Inspector 面板設定的亮度與縮放大小
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

	# 開局主動掃描一開場就在光圈內的野豬
	await get_tree().process_frame
	_check_initial_overlapping_enemies()

# 掃描開局就在光圈裡的敵人
func _check_initial_overlapping_enemies() -> void:
	if not light_area: return
	var bodies = light_area.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("enemies") or body is Enemy:
			_on_light_area_body_entered(body)

# ==========================================
# 🌟 白貓受傷處置 (支援 1~3 個傳入參數防呆)
# ==========================================
func take_damage(damage_amount: float = 0.0, _attacker_pos: Vector2 = Vector2.ZERO, _dir: Vector2 = Vector2.ZERO) -> void:
	if is_stunned: 
		return # 已經在虛弱狀態中不重複觸發
		
	is_stunned = true
	velocity = Vector2.ZERO # 立刻停在原地
	print("😿【白貓受傷】受到了來自敵人的傷害！進入虛弱狀態 3 秒！")

	# 如果有舊的動畫正在跑，先中斷
	if stun_tween and stun_tween.is_running():
		stun_tween.kill()

	# 創建並行動畫 (set_parallel 讓燈光、感應圈、角色本體同時變動)
	stun_tween = create_tween().set_parallel(true)

	# 1. 燈光變暗：降為原亮度的 25% (約 0.5)
	if point_light_2d:
		stun_tween.tween_property(point_light_2d, "energy", original_light_energy * 0.25, 0.25)

	# 2. 偵測範圍縮小：縮小為編輯器原始設定大小的 40%
	if light_area:
		stun_tween.tween_property(light_area, "scale", original_light_scale * 0.4, 0.25)

	# 3. 白貓本體半透明 + 變暗發灰 (視覺受傷特效)
	stun_tween.tween_property(self, "modulate", Color(0.6, 0.6, 0.6, 0.7), 0.25)

	# 4. 啟動 3 秒計時器，時間到恢復原狀
	get_tree().create_timer(3.0).timeout.connect(_recover_from_damage)

# 🌟 復原狀態
func _recover_from_damage() -> void:
	if not is_stunned: return

	print("🐱【白貓復原】狀態恢復！燈光與偵測圈重新展開。")

	if stun_tween and stun_tween.is_running():
		stun_tween.kill()

	stun_tween = create_tween().set_parallel(true)

	# 1. 燈光能量恢復：精準彈回 Inspector 設定的 2.0 全亮
	if point_light_2d:
		stun_tween.tween_property(point_light_2d, "energy", original_light_energy, 0.4)

	# 2. 偵測範圍恢復：精準彈回 Inspector 設定的 100% 大小
	if light_area:
		stun_tween.tween_property(light_area, "scale", original_light_scale, 0.4)

	# 3. 顏色恢復全亮白色
	stun_tween.tween_property(self, "modulate", Color.WHITE, 0.4)

	# 動畫播完後解鎖行動並重新掃描周圍敵人
	stun_tween.chain().tween_callback(func():
		is_stunned = false
		_check_initial_overlapping_enemies() # 恢復大圈圈後，重新照亮範圍內的敵人
	)

# ==========================================
# 白貓探測敵人的主動邏輯
# ==========================================
func _on_light_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") or body is Enemy:
		if not detected_enemies.has(body):
			detected_enemies.append(body)
			
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
	# 🌟 虛弱期間直接屏蔽玩家操作指令
	if is_stunned: return
	
	# 按 Space 召回白貓
	if (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE) or event.is_action_pressed("cat_recall") or event.is_action_pressed("ui_select"):
		if player_node:
			nav_agent.target_position = player_node.global_position
		return

	# 滑鼠右鍵指揮白貓移動
	if event.is_action_pressed("cat_move"):
		var target_pos = get_global_mouse_position()
		
		if player_node:
			var dist_to_player = player_node.global_position.distance_to(target_pos)
			if dist_to_player > max_follow_distance:
				var dir = (target_pos - player_node.global_position).normalized()
				target_pos = player_node.global_position + dir * max_follow_distance
		
		nav_agent.target_position = target_pos

func _physics_process(_delta: float) -> void:
	# 🌟 虛弱期間停在原地，不執行尋路位移
	if is_stunned:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var next_path_pos: Vector2 = nav_agent.get_next_path_position()
	var move_dir: Vector2 = global_position.direction_to(next_path_pos)
	
	velocity = move_dir * move_speed
	
	if sprite and move_dir.x != 0:
		sprite.flip_h = move_dir.x < 0
		
	move_and_slide()

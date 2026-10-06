extends Node2D

# 🌟 發光與變暗週期參數 (可在 Inspector 介面直接微調)
@export var min_energy: float = 0.2       # 變暗時的亮度 (若想全黑可設為 0.0)
@export var max_energy: float = 2.0       # 發光時的亮度
@export var lit_duration: float = 3.0     # 維持發光的秒數 (3秒)
@export var dark_duration: float = 2.0    # 維持變暗的秒數 (2秒)
@export var fade_duration: float = 1.5    # 明暗切換時的過渡秒數

# 🌟 預設改為 true：花朵開始變暗時，自動暫時關閉顯形機制
@export var disable_sight_when_dark: bool = true

# 🌟 新增：錯開每朵花發光時間的設定（頻率相同，但起跑時間不同）
@export_group("時間錯開設定 (同頻率不同步)")
@export var random_start_offset: bool = true   # 打勾：每朵花自動隨機錯開時間！
@export var custom_start_delay: float = 0.0    # 若上面不打勾，可手動指定這朵花延遲幾秒才開始循環（適合做波浪機關）

@onready var light_area: Area2D = $LightArea
@onready var point_light_2d: PointLight2D = $PointLight2D

var detected_enemies: Array[Node2D] = []
var is_flower_lit: bool = true            # 紀錄花朵目前是否處於「有效照明」狀態

func _ready() -> void:
	# 1. 自動連接感應訊號
	if light_area:
		if not light_area.body_entered.is_connected(_on_light_area_body_entered):
			light_area.body_entered.connect(_on_light_area_body_entered)
		if not light_area.body_exited.is_connected(_on_light_area_body_exited):
			light_area.body_exited.connect(_on_light_area_body_exited)
		
	# 2. 開局先固定在最亮狀態，並主動掃描一開場就在光圈內的敵人
	if point_light_2d:
		point_light_2d.energy = max_energy
	is_flower_lit = true
	
	await get_tree().process_frame
	_check_initial_overlapping_enemies()
	
	# 3. 啟動「同頻率、不同步」的循環動畫
	_start_light_cycle()

# ==========================================
# 🌟 發光 3 秒 / 變暗 2 秒 循環與顯形開關
# ==========================================
func _start_light_cycle() -> void:
	if not point_light_2d: return
	
	# 🌟 計算一整輪的總週期時間 (3 + 1.5 + 2 + 1.5 = 8 秒)
	var total_cycle_time: float = lit_duration + dark_duration + (fade_duration * 2.0)
	var start_delay: float = custom_start_delay
	
	if random_start_offset:
		# 在 0 秒 ～ 總週期時間之間隨機抽一個起跑點，讓每朵花完美錯開！
		start_delay = randf_range(0.0, total_cycle_time)
		
	# 先等待錯開的秒數，再進入無限固定頻率循環
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
		
	if not is_inside_tree() or not point_light_2d: return
	
	var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 1️⃣ 維持發光狀態 3 秒
	tween.tween_interval(lit_duration)
	
	# 2️⃣ 【開始變暗】：瞬間暫時關閉顯形機制，並將燈光漸暗
	tween.tween_callback(func():
		if disable_sight_when_dark:
			_set_flower_sight_active(false)
	)
	tween.tween_property(point_light_2d, "energy", min_energy, fade_duration)
	
	# 3️⃣ 維持變暗狀態 2 秒
	tween.tween_interval(dark_duration)
	
	# 4️⃣ 【開始發光】：瞬間重新啟動顯形機制，並將燈光漸亮
	tween.tween_callback(func():
		if disable_sight_when_dark:
			_set_flower_sight_active(true)
	)
	tween.tween_property(point_light_2d, "energy", max_energy, fade_duration)

# 🌟 切換花朵的照妖鏡顯形狀態
func _set_flower_sight_active(active: bool) -> void:
	is_flower_lit = active
	
	if active:
		# 花朵亮起：重新掃描光圈內的所有怪物並讓牠們現形
		_check_initial_overlapping_enemies()
	else:
		# 花朵開始變暗：把目前光圈內的所有怪物變回隱形
		for enemy in detected_enemies:
			if is_instance_valid(enemy):
				_hide_enemy_safely(enemy)
		detected_enemies.clear()

# ==========================================
# 🌟 敵人偵測與顯形邏輯
# ==========================================
func _check_initial_overlapping_enemies() -> void:
	if not light_area or not is_flower_lit: return
	var bodies = light_area.get_overlapping_bodies()
	for body in bodies:
		_on_light_area_body_entered(body)

func _on_light_area_body_entered(body: Node2D) -> void:
	# 如果花朵現在是暗的，就算怪物走進來也不會現形！
	if not is_flower_lit: return
	
	if body.is_in_group("enemies") or body is BaseEnemy:
		if not detected_enemies.has(body):
			detected_enemies.append(body)
			
		if "is_illuminated_by_cat" in body:
			body.is_illuminated_by_cat = true
			
		if body.has_method("update_visibility"):
			body.update_visibility()

func _on_light_area_body_exited(body: Node2D) -> void:
	if detected_enemies.has(body):
		detected_enemies.erase(body)
		_hide_enemy_safely(body)

# 🌟 安全隱形檢查：確認白貓沒有同時照著這隻怪，才把牠變回隱形
func _hide_enemy_safely(enemy: Node2D) -> void:
	var white_cat = get_tree().get_first_node_in_group("white_cat")
	if white_cat and "detected_enemies" in white_cat:
		if white_cat.detected_enemies.has(enemy):
			return # 白貓正在旁邊照著牠，保持現形！
			
	if "is_illuminated_by_cat" in enemy:
		enemy.is_illuminated_by_cat = false
		
	if enemy.has_method("update_visibility"):
		enemy.update_visibility()

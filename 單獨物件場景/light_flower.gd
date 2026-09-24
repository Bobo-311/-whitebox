extends Node2D

# 🌟 呼吸燈參數 (可以在 Inspector 介面直接微調)
@export var min_energy: float = 0.5   # 呼吸燈最暗的亮度
@export var max_energy: float = 2.0   # 呼吸燈最亮的亮度
@export var breath_duration: float = 2.0 # 呼吸一次需要的秒數

@onready var light_area: Area2D = $LightArea
@onready var point_light_2d: PointLight2D = $PointLight2D

var detected_enemies: Array[Node2D] = []

func _ready() -> void:
	# 1. 自動連接感應訊號
	if light_area:
		light_area.body_entered.connect(_on_light_area_body_entered)
		light_area.body_exited.connect(_on_light_area_body_exited)
		
	# 2. 啟動呼吸燈動畫
	_start_breathing_effect()
	
	# 3. 開局主動掃描一開場就在光圈內的敵人
	await get_tree().process_frame
	_check_initial_overlapping_enemies()

# ==========================================
# 🌟 呼吸燈動畫邏輯
# ==========================================
func _start_breathing_effect() -> void:
	if not point_light_2d: return
	
	# 建立無限循環的 Tween，使用 SINE 曲線讓呼吸感更滑順
	var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 先變暗，再變亮，形成呼吸循環
	tween.tween_property(point_light_2d, "energy", min_energy, breath_duration)
	tween.tween_property(point_light_2d, "energy", max_energy, breath_duration)

# ==========================================
# 🌟 敵人偵測與顯形邏輯 (沿用白貓系統)
# ==========================================
func _check_initial_overlapping_enemies() -> void:
	if not light_area: return
	var bodies = light_area.get_overlapping_bodies()
	for body in bodies:
		_on_light_area_body_entered(body)

func _on_light_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") or body is BaseEnemy:
		if not detected_enemies.has(body):
			detected_enemies.append(body)
			
		# 沿用白貓的變數來讓敵人現形
		if "is_illuminated_by_cat" in body:
			body.is_illuminated_by_cat = true
			
		if body.has_method("update_visibility"):
			body.update_visibility()

func _on_light_area_body_exited(body: Node2D) -> void:
	if detected_enemies.has(body):
		detected_enemies.erase(body)
		
		# 離開光圈，取消現形
		if "is_illuminated_by_cat" in body:
			body.is_illuminated_by_cat = false
			
		if body.has_method("update_visibility"):
			body.update_visibility()

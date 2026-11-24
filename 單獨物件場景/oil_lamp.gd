extends Node2D

@export var light_color: Color = Color("#ffb84d")
@export_range(0.0, 8.0, 0.1, "or_greater") var light_energy: float = 2.0

@onready var light_area: Area2D = $LightArea
@onready var point_light: PointLight2D = $PointLight2D

# 油燈自動加入此群組。會與油燈交疊的發光花也可以加入。
const LIGHT_GROUP := &"enemy_reveal_lights"
var detected_enemies: Array[Node2D] = []

func _ready() -> void:
	point_light.color = light_color
	point_light.energy = light_energy
	point_light.enabled = true
	add_to_group(LIGHT_GROUP)

	if not light_area.body_entered.is_connected(_on_light_area_body_entered):
		light_area.body_entered.connect(_on_light_area_body_entered)
	if not light_area.body_exited.is_connected(_on_light_area_body_exited):
		light_area.body_exited.connect(_on_light_area_body_exited)
	for body in light_area.get_overlapping_bodies():
		_on_light_area_body_entered(body)
	set_physics_process(not detected_enemies.is_empty())

func _on_light_area_body_entered(body: Node2D) -> void:
	if not (body.is_in_group("enemies") or body is BaseEnemy):
		return
	if "is_illuminated_by_cat" in body and not detected_enemies.has(body):
		detected_enemies.append(body)
		_set_illuminated(body, true)
		set_physics_process(true)

func _on_light_area_body_exited(body: Node2D) -> void:
	if detected_enemies.has(body):
		detected_enemies.erase(body)
		_release_enemy(body)
		set_physics_process(not detected_enemies.is_empty())

func _physics_process(_delta: float) -> void:
	# 白貓離開或花朵熄滅時可能清除共用旗標；仍在油燈裡的敵人要保持顯形。
	for enemy in detected_enemies:
		if is_instance_valid(enemy):
			_set_illuminated(enemy, true)

func _set_illuminated(enemy: Node2D, active: bool) -> void:
	if enemy.get("is_illuminated_by_cat") != active:
		enemy.set("is_illuminated_by_cat", active)
		if enemy.has_method("update_visibility"):
			enemy.call("update_visibility")

func _release_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	for group in [LIGHT_GROUP, &"white_cat"]:
		for source in get_tree().get_nodes_in_group(group):
			if source != self and "detected_enemies" in source and source.detected_enemies.has(enemy):
				return
	_set_illuminated(enemy, false)

func _exit_tree() -> void:
	for enemy in detected_enemies:
		_release_enemy(enemy)
	detected_enemies.clear()

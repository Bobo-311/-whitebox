extends Area2D

@export var zone_elevation: int = 1 # 在編輯器面板設定這塊區域是幾樓

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.current_elevation = zone_elevation

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		body.current_elevation = 0 # 離開區域預設回到 0 樓

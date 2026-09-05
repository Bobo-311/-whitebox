extends StaticBody2D

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var fade_area: Area2D = $FadeArea

func _ready() -> void:
	fade_area.body_entered.connect(_on_fade_area_body_entered)
	fade_area.body_exited.connect(_on_fade_area_body_exited)

func _on_fade_area_body_entered(body: Node2D) -> void:
	# 🌟 測試行 1：看看有沒有任何東西踩進感應區？
	print("有東西碰到樹葉了！他是：", body.name) 
	
	if body.is_in_group("player"):
		# 🌟 測試行 2：看看系統有沒有成功認出他是阿尼？
		print("確認是阿尼！變透明！") 
		var tween = create_tween()
		tween.tween_property(sprite_2d, "modulate:a", 0.4, 0.2)

func _on_fade_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		var tween = create_tween()
		tween.tween_property(sprite_2d, "modulate:a", 1.0, 0.2)

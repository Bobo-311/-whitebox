extends Area2D

func _ready() -> void:
	# 用程式碼自動連接訊號，這樣你以後複製貼上就不怕忘記去右邊勾選訊號了！
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	# 判斷踩進來的是不是玩家 (依賴你 player.gd 裡的 class_name Player)
	if body is Player:
		var camera = body.get_node_or_null("Camera2D")
		if camera:
			camera.is_look_ahead_disabled = true # 踩進去，關閉探頭功能！

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		var camera = body.get_node_or_null("Camera2D")
		if camera:
			camera.is_look_ahead_disabled = false # 離開後，恢復探頭功能！

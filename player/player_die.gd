# --- PlayerDie.gd ---
extends State

func enter():
	character.play_animation("dead") 
	character.remove_from_group("player") # 從玩家群組移除，避免野豬瘋狂鞭屍
	
	var col = character.get_node_or_null("CollisionShape2D")
	if col: col.set_deferred("disabled", true) # 關閉肉體碰撞
	
	character.velocity = character.knockback_force # 接管最後擊退力
	_restart_game()

func state_physics_update(delta: float):
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15) # 摩擦停下

func _restart_game():
	await character.get_tree().create_timer(3.0).timeout # 死後 3 秒
	# character.get_tree().reload_current_scene() # 重新載入關卡 (暫時註解)

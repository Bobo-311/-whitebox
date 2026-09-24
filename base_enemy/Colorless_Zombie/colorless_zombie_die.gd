extends State

# 🌟 魔法的核心：在右邊 Inspector 面板把未來的「怨靈場景」拖進這裡！
@export var wraith_scene: PackedScene 
@export var spawn_delay: float = 1.0 # 🌟 新增：延遲幾秒後才召喚怨靈 (預設 1 秒)

func enter():
	character.velocity = Vector2.ZERO
	
	# 1. 結算玩家擊殺獎勵 (沿用你 base_die.gd 的寫法)
	if DataManager and DataManager.player_node and DataManager.player_node.has_method("on_enemy_killed"):
		DataManager.player_node.on_enemy_killed()
	
	# 🌟 2. 安全關閉碰撞與受擊框 (避免殭屍「屍體」這 1 秒內還會擋路或被打)
	_disable_physics_boxes()
	
	# 🌟 3. 播放本體死亡動畫 (如果有的話)，或是讓屍體留在原地
	character.play_animation("die", character.last_facing_vec)
	
	# 🌟 4. 啟動「延遲召喚」的計時器
	_start_delayed_spawn()
	
func _disable_physics_boxes():
	# 關閉物理碰撞牆 (讓玩家可以穿過屍體)
	var collision = character.get_node_or_null("CollisionShape2D")
	if collision: collision.set_deferred("disabled", true)
		
	# 關閉攻擊框
	var hitbox = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox: hitbox.set_deferred("disabled", true)
	
	# 關閉受傷框
	var hurtbox = character.get_node_or_null("Hurtbox/CollisionShape2D")
	if hurtbox: hurtbox.set_deferred("disabled", true)



func _start_delayed_spawn():
	# 等待 spawn_delay 的秒數 (1秒)
	await character.get_tree().create_timer(spawn_delay).timeout
	
	# 🌟 5. 時間到！召喚儀式開始 🌟
	if wraith_scene:
		# 產生一個怨靈實體
		var wraith = wraith_scene.instantiate()
		# 把怨靈的位置放在殭屍本體最後死掉的位置
		wraith.global_position = character.global_position 
		# 把怨靈加入到遊戲世界中
		character.get_parent().add_child(wraith)
		
	# 6. 殭屍本體功成身退，瞬間消失
	character.queue_free()

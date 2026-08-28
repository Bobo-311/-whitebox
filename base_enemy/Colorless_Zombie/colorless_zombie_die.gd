extends State

# 🌟 魔法的核心：在右邊 Inspector 面板把未來的「怨靈場景」拖進這裡！
@export var wraith_scene: PackedScene 

func enter():
	character.velocity = Vector2.ZERO
	
	# 1. 結算玩家擊殺獎勵 (沿用你 base_die.gd 的寫法)
	if DataManager and DataManager.player_node and DataManager.player_node.has_method("on_enemy_killed"):
		DataManager.player_node.on_enemy_killed()
		
	# 2. 🌟 召喚儀式 🌟
	if wraith_scene:
		# 產生一個怨靈實體
		var wraith = wraith_scene.instantiate()
		# 把怨靈的位置放在殭屍本體最後死掉的位置
		wraith.global_position = character.global_position 
		# 把怨靈加入到遊戲世界中
		character.get_parent().add_child(wraith)
		
	# 3. 殭屍本體瞬間消失
	character.queue_free()

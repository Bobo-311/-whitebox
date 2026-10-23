extends State

# ==========================================
# ⚙️ 亡語召喚設定 (可在右側 Inspector 面板調整)
# ==========================================
@export var wraith_scene: PackedScene        # 拖入自爆蝌蚪場景 (colorless_zombie_dead_body.tscn)
@export var spit_start_delay: float = 0.4    # 倒下後停頓幾秒，才開始肚子膨脹？
@export var spawn_frame: int = 8             # 🌟 肚子消風吐出蝌蚪的關鍵影格 (對應素材第 8 格，即第3排第1格)

# 內部狀態防呆鎖
var is_spitting: bool = false                # 記錄是否已經進入「肚子膨脹吐蝌蚪」階段
var has_spawned_tadpole: bool = false        # 防呆鎖：確保只會吐出一隻自爆蝌蚪

# ==========================================
# 🎬 進入死亡狀態
# ==========================================
func enter():
	character.velocity = Vector2.ZERO
	is_spitting = false
	has_spawned_tadpole = false
	
	# 1. 結算玩家擊殺獎勵
	if DataManager and DataManager.player_node and DataManager.player_node.has_method("on_enemy_killed"):
		DataManager.player_node.on_enemy_killed()
	
	# 2. 安全關閉所有碰撞與受擊框 (避免屍體擋路或鞭屍)
	_disable_physics_boxes()
	
	# 3. 先播放第一階段：倒地死亡動畫 (die_left_up 等)
	character.play_animation("die", character.last_facing_vec)
	
	# 4. 啟動二段式演出：倒地後銜接「肚子膨脹吐蝌蚪」
	_start_spit_sequence()

# ==========================================
# 🔄 物理更新：嚴密監控「肚子膨脹」的影格進度
# ==========================================
func state_physics_update(_delta: float):
	if not is_spitting or not character.animated_sprite_2d:
		return
		
	var anim = character.animated_sprite_2d
	
	# 確認目前正在播放 die_spit 系列的動畫
	if "die_spit" in anim.animation:
		var current_frame = anim.frame
		
		# 🌟【關鍵同步】：當動畫播到第 8 格 (肚子瞬間消風的那一格)，立刻吐出自爆蝌蚪！
		if current_frame >= spawn_frame and not has_spawned_tadpole:
			has_spawned_tadpole = true
			_spawn_suicide_tadpole()
			
		# 🌟【完美退場】：等 12 格動畫全部播完 (最後一格是 index 11)，才讓屍體消失
		var max_frame = anim.sprite_frames.get_frame_count(anim.animation) - 1
		if current_frame >= max_frame:
			is_spitting = false
			character.queue_free()

# ==========================================
# ⏳ 二段式亡語流程控制
# ==========================================
func _start_spit_sequence():
	# 等待倒地動作稍微停頓 (spit_start_delay 秒)
	await character.get_tree().create_timer(spit_start_delay).timeout
	
	if not is_instance_valid(character):
		return
		
	# 🌟 進入第二階段：呼叫老爸播放四向「死後吐蝌蚪」動畫 (die_spit_...)
	is_spitting = true
	character.play_animation("die_spit", character.last_facing_vec)

func _spawn_suicide_tadpole():
	if wraith_scene:
		var tadpole = wraith_scene.instantiate()
		tadpole.global_position = character.global_position
		character.get_parent().add_child(tadpole)

func _disable_physics_boxes():
	var collision = character.get_node_or_null("CollisionShape2D")
	if collision: collision.set_deferred("disabled", true)
		
	var hitbox = character.get_node_or_null("Hitbox/CollisionShape2D")
	if hitbox: hitbox.set_deferred("disabled", true)
	
	var hurtbox = character.get_node_or_null("Hurtbox/CollisionShape2D")
	if hurtbox: hurtbox.set_deferred("disabled", true)

# --- PlayerAttack.gd ---
extends State # 繼承自狀態模板

const INK_SLASH_PARTICLES = preload("res://近戰/ink_slash_particles.tscn")

# 🌟【影格驅動設定】
@export var hit_start_frame: int = 2 # 第 3 幀開啟傷害判定
@export var hit_end_frame: int = 5   # 第 6 幀關閉傷害判定

var has_slashed: bool = false        # 防重複播放特效的開關
var is_hitbox_active: bool = false   # 記錄目前刀光是否有傷害
var hit_targets: Array = []          # 記錄這一刀已經砍過誰，防重複扣血

func enter(): # 進入攻擊狀態的第 0 幀執行
	# 劇情中不准揮刀
	if Dialogic.current_timeline != null or character.is_in_dialogue:
		state_machine.change_state("PlayerIdle") 
		return
	
	# 揮刀前重置所有判定開關
	has_slashed = false
	is_hitbox_active = false
	hit_targets.clear()
	
	# ==========================================
	# 🌟【動作遊戲核心 1：硬直定桿 (Rooting)】🌟
	# 只要進入攻擊狀態，物理速度「絕對強制歸零」！
	# 就算玩家死死按著 WASD，阿尼也必須乖乖在原地站著不動揮完這刀。
	# ==========================================
	character.velocity = Vector2.ZERO 
	
	# ==========================================
	# 🌟【動作遊戲核心 2：滑鼠鎖定轉向 (Mouse Aiming)】🌟
	# 解決痛點：不管阿尼剛才是往哪裡走，出刀的瞬間，必須精準面向滑鼠的位置！
	# ==========================================
	# 1. 取得「滑鼠相對於阿尼」的方向向量
	var mouse_dir = (character.get_global_mouse_position() - character.global_position).normalized()
	
	# 2. 把 360 度的滑鼠向量，翻譯成上下左右，並「強行洗掉」阿尼原本的面向記憶
	if mouse_dir != Vector2.ZERO:
		if abs(mouse_dir.x) > abs(mouse_dir.y):
			# X 偏移比較大，判斷左右
			character.facing_direction = "right" if mouse_dir.x > 0 else "left"
		else:
			# Y 偏移比較大，判斷上下
			character.facing_direction = "down" if mouse_dir.y > 0 else "up"
	# ==========================================
	
	# 揮刀前先確保判定框是關閉的
	_disable_all_hitboxes()
	
	var sword_hitbox: Area2D = character.get_node_or_null("Hitbox")
	if sword_hitbox and not sword_hitbox.area_entered.is_connected(_on_hitbox_area_entered):
		sword_hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# 🌟 播放攻擊動畫 
	# (因為上面已經用滑鼠強制轉向了，這裡揮出去的絕對是朝向滑鼠的那一刀)
	character.play_animation("attack") 
	
	# 處理動畫等待與影格判定
	var anim: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D")
	if anim and anim.sprite_frames:
		if anim.animation != "" and anim.sprite_frames.has_animation(anim.animation):
			anim.sprite_frames.set_animation_loop(anim.animation, false)
			
		if not anim.frame_changed.is_connected(_on_attack_frame_changed):
			anim.frame_changed.connect(_on_attack_frame_changed)
			
		var total_frames = anim.sprite_frames.get_frame_count(anim.animation)
		if total_frames <= hit_start_frame:
			_activate_slash_hitbox()
			
		# 程式在這裡暫停，讓阿尼在原地把這套揮刀動畫徹底播完
		await anim.animation_finished
	else:
		_activate_slash_hitbox()
		await character.get_tree().create_timer(0.4).timeout 

	# 揮完刀，關閉傷害判定
	_disable_all_hitboxes()

	# ==========================================
	# 🌟【動作遊戲核心 3：流暢銜接 (Action Buffer)】🌟
	# 揮完這刀後，去問大腦：玩家現在的手指還有沒有按著 WASD？
	# 如果有按著 ➡️ 直接切回 PlayerMove 讓他繼續跑 (不用重新按鍵盤)
	# 如果沒按了 ➡️ 切回 PlayerIdle 乖乖待機
	# ==========================================
	if state_machine.current_state == self:
		if character.input_direction != Vector2.ZERO:
			state_machine.change_state("PlayerMove")
		else:
			state_machine.change_state("PlayerIdle")


# ==========================================
# 🌟 物理幀更新
# (這裡面絕對不寫任何移動邏輯，確保阿尼揮刀時乖乖罰站！)
# ==========================================
func state_physics_update(_delta: float) -> void:
	# 每一幀只專心做一件事：掃描刀光有沒有砍到怪
	if is_hitbox_active:
		_check_overlapping_hurtboxes()


# 🌟 當動畫跳到下一幀時，自動檢查開關刀光
func _on_attack_frame_changed() -> void:
	if state_machine.current_state != self:
		return
		
	var anim: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D")
	if not anim: return
	
	if anim.frame >= hit_start_frame and not has_slashed:
		_activate_slash_hitbox()
	elif anim.frame >= hit_end_frame and is_hitbox_active:
		_disable_all_hitboxes()


# 🌟 啟動刀光與音效
func _activate_slash_hitbox() -> void:
	if has_slashed: return
	has_slashed = true
	is_hitbox_active = true
	
	var sfx_sword = character.get_node_or_null("SFXSword") 
	if sfx_sword: 
		sfx_sword.play() 
	
	spawn_slash_particles() 

	var sword_hitbox: Area2D = character.get_node_or_null("Hitbox") 
	if sword_hitbox:
		var target_coll: CollisionShape2D = sword_hitbox.get_node_or_null("CollisionShape_" + character.facing_direction) 
		sword_hitbox.monitoring = true 
		if target_coll:
			target_coll.disabled = false 
			
	await character.get_tree().physics_frame
	await character.get_tree().physics_frame
	if is_hitbox_active and state_machine.current_state == self:
		_check_overlapping_hurtboxes()


# 🌟 主動掃描重疊怪物
func _check_overlapping_hurtboxes() -> void:
	var sword_hitbox: Area2D = character.get_node_or_null("Hitbox")
	if not sword_hitbox or not sword_hitbox.monitoring: return
	var targets = sword_hitbox.get_overlapping_areas()
	for t in targets:
		_try_damage_target(t)


# 🌟 怪物自己撞上來刀光時觸發
func _on_hitbox_area_entered(area: Area2D) -> void:
	if is_hitbox_active and state_machine.current_state == self:
		_try_damage_target(area)


# 🌟 結算傷害與防重複扣血
func _try_damage_target(t: Area2D) -> void:
	if t is Hurtbox and t.get_parent() != character: 
		if hit_targets.has(t):
			return 
		hit_targets.append(t)
		var final_damage: float = character.get_current_basic_attack_damage()
		var attack_dir: Vector2 = (t.global_position - character.global_position).normalized()
		t.take_damage(final_damage, character.global_position, attack_dir, true)


# 🛡️ 離開狀態時安全清理
func exit():
	var anim: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D")
	if anim and anim.frame_changed.is_connected(_on_attack_frame_changed):
		anim.frame_changed.disconnect(_on_attack_frame_changed)
	_disable_all_hitboxes()


# 安全關閉所有判定框
func _disable_all_hitboxes() -> void:
	is_hitbox_active = false
	var sword_hitbox = character.get_node_or_null("Hitbox")
	if not sword_hitbox: return
	sword_hitbox.set_deferred("monitoring", false)
	for dir_name in ["up", "down", "left", "right"]:
		var coll = sword_hitbox.get_node_or_null("CollisionShape_" + dir_name)
		if coll:
			coll.set_deferred("disabled", true)


# 墨水殘影生成
func spawn_slash_particles() -> void:
	if not INK_SLASH_PARTICLES: return
	var particles = INK_SLASH_PARTICLES.instantiate()
	var spawn_offset = Vector2.ZERO 
	var attack_dir = Vector2.RIGHT  
	
	# 因為阿尼的面向已經在開頭被滑鼠強行改寫了，
	# 這裡讀到的 facing_direction 絕對是朝向滑鼠的方向，殘影也會精準出現在對應位置！
	match character.facing_direction:
		"right":
			spawn_offset = Vector2(25, -5)
			attack_dir = Vector2.RIGHT
		"left":
			spawn_offset = Vector2(-25, -5)
			attack_dir = Vector2.LEFT
		"up":
			spawn_offset = Vector2(0, -30)
			attack_dir = Vector2.UP
		"down":
			spawn_offset = Vector2(0, 20)
			attack_dir = Vector2.DOWN
			
	particles.global_position = character.global_position + spawn_offset
	particles.rotation = attack_dir.angle()
	character.get_parent().add_child(particles)

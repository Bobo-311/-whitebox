extends State # 繼承自狀態模板

# 預載粒子特效 (避免揮刀時卡頓)
const INK_SLASH_PARTICLES = preload("res://近戰/ink_slash_particles.tscn")

# 🌟【專業影格驅動設定】：Godot 影格從 0 開始算 (0=第1幀, 1=第2幀, 2=第3幀)
@export var hit_start_frame: int = 2 # 第 3 幀 (index 2) 開啟 Hitbox 與刀光特效
@export var hit_end_frame: int = 5   # 第 6 幀 (index 5) 關閉 Hitbox (讓刀光揮動期間都有判定！)

var has_slashed: bool = false        # 確保單次揮刀只播一次音效與特效
var is_hitbox_active: bool = false   # 記錄目前刀光判定是否開啟中
var hit_targets: Array = []          # 記錄這一刀已經砍過的目標，防止同一刀重複扣血

func enter(): # 當大腦切換到「攻擊狀態」時，立刻執行此函數
	# 🌟 終極防線：如果正在跑劇情，這份腳本底下所有關於攻擊跟移動的程式直接跳過！
	if Dialogic.current_timeline != null or character.is_in_dialogue:
		state_machine.change_state("PlayerIdle") # 確保狀態退回待機
		return
	
	# 🌟【改動】：徹底拔除 use_sp 審查，玩家可無限制普攻輸出
	
	has_slashed = false
	is_hitbox_active = false
	hit_targets.clear()
	character.velocity = Vector2.ZERO # 強制煞車，避免揮刀滑步
	
	# 起手前 2 幀：確保判定框一開始是關閉的
	_disable_all_hitboxes()
	
	# 綁定 Hitbox 碰撞訊號 (雙重保障：只要刀光期間擦到怪就立刻結算傷害)
	var sword_hitbox: Area2D = character.get_node_or_null("Hitbox")
	if sword_hitbox and not sword_hitbox.area_entered.is_connected(_on_hitbox_area_entered):
		sword_hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	character.play_animation("attack") 
	
	var anim: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D")
	if anim and anim.sprite_frames:
		# 防呆保護：強制關閉攻擊動畫的循環播放 (Loop)，避免卡死
		if anim.animation != "" and anim.sprite_frames.has_animation(anim.animation):
			anim.sprite_frames.set_animation_loop(anim.animation, false)
			
		# 綁定影格切換訊號，監聽何時播到「第 3 幀」
		if not anim.frame_changed.is_connected(_on_attack_frame_changed):
			anim.frame_changed.connect(_on_attack_frame_changed)
			
		# 防呆：如果某個方向的動畫總幀數不到 3 幀，直接開啟判定避免沒傷害
		var total_frames = anim.sprite_frames.get_frame_count(anim.animation)
		if total_frames <= hit_start_frame:
			_activate_slash_hitbox()
			
		# 等待整段攻擊動畫播完，才切回待機狀態
		await anim.animation_finished
	else:
		# 備用防呆
		_activate_slash_hitbox()
		await character.get_tree().create_timer(0.4).timeout 

	# 收刀關閉判定框
	_disable_all_hitboxes()

	# 確保玩家沒有在揮刀中途因為受傷被切去 PlayerHurt，才切回待機
	if state_machine.current_state == self:
		state_machine.change_state("PlayerIdle")

# 🌟 每個物理幀主動掃描重疊目標（徹底解決 Godot 渲染幀與物理幀不同步的問題！）
func physics_update(_delta: float) -> void:
	if is_hitbox_active:
		_check_overlapping_hurtboxes()

# 🌟 當動畫跳格時自動檢查：第 3 幀開刀光，第 6 幀關刀光
func _on_attack_frame_changed() -> void:
	if state_machine.current_state != self:
		return
		
	var anim: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D")
	if not anim: return
	
	# 播到第 3 幀 (index == 2)：開啟音效、特效與 Hitbox！
	if anim.frame >= hit_start_frame and not has_slashed:
		_activate_slash_hitbox()
	# 播到收刀幀 (index >= 5)：關閉 Hitbox
	elif anim.frame >= hit_end_frame and is_hitbox_active:
		_disable_all_hitboxes()

# 🌟 開啟揮刀音效、特效與 Hitbox 判定框
func _activate_slash_hitbox() -> void:
	if has_slashed: return
	has_slashed = true
	is_hitbox_active = true
	
	# 播放揮劍音效
	var sfx_sword = character.get_node_or_null("SFXSword") 
	if sfx_sword: 
		sfx_sword.play() 
	
	spawn_slash_particles() # 生成墨水殘影

	# 抓取對應方向的判定框並開啟
	var sword_hitbox: Area2D = character.get_node_or_null("Hitbox") 
	if sword_hitbox:
		var target_coll: CollisionShape2D = sword_hitbox.get_node_or_null("CollisionShape_" + character.facing_direction) 
		sword_hitbox.monitoring = true 
		if target_coll:
			target_coll.disabled = false   
			
	# 連續等待 2 個物理幀讓 Godot 物理伺服器完成碰撞刷新，再立刻掃描一次
	await character.get_tree().physics_frame
	await character.get_tree().physics_frame
	if is_hitbox_active and state_machine.current_state == self:
		_check_overlapping_hurtboxes()

# 🌟 掃描目前在刀光範圍內的所有 Hurtbox
func _check_overlapping_hurtboxes() -> void:
	var sword_hitbox: Area2D = character.get_node_or_null("Hitbox")
	if not sword_hitbox or not sword_hitbox.monitoring: return
	
	var targets = sword_hitbox.get_overlapping_areas()
	for t in targets:
		_try_damage_target(t)

# 🌟 當刀光揮出去擦到怪物時也會即時觸發
func _on_hitbox_area_entered(area: Area2D) -> void:
	if is_hitbox_active and state_machine.current_state == self:
		_try_damage_target(area)

# 🌟 單一目標傷害結算（含防重複扣血保護）
func _try_damage_target(t: Area2D) -> void:
	if t is Hurtbox and t.get_parent() != character: # 確保砍到的不是自己
		if hit_targets.has(t):
			return # 這一刀已經砍過這隻怪了，跳過不重複扣血！
			
		hit_targets.append(t)
		var final_damage: float = character.get_current_basic_attack_damage()
		var attack_dir: Vector2 = (t.global_position - character.global_position).normalized()
		# 傳入 true 觸發近戰專屬處決/補彈機制
		t.take_damage(final_damage, character.global_position, attack_dir, true)

# 🛡️ 離開攻擊狀態時的強制清理（防止前 2 幀起手被打斷時殘留訊號或判定框）
func exit():
	var anim: AnimatedSprite2D = character.get_node_or_null("AnimatedSprite2D")
	if anim and anim.frame_changed.is_connected(_on_attack_frame_changed):
		anim.frame_changed.disconnect(_on_attack_frame_changed)
	_disable_all_hitboxes()

# 確保四個方向的判定框全部安全關閉 (使用 set_deferred 防止揮刀途中被打斷時報錯)
func _disable_all_hitboxes() -> void:
	is_hitbox_active = false
	var sword_hitbox = character.get_node_or_null("Hitbox")
	if not sword_hitbox: return
	sword_hitbox.set_deferred("monitoring", false)
	for dir_name in ["up", "down", "left", "right"]:
		var coll = sword_hitbox.get_node_or_null("CollisionShape_" + dir_name)
		if coll:
			coll.set_deferred("disabled", true)

# 生成墨水殘影方向控制
func spawn_slash_particles() -> void:
	if not INK_SLASH_PARTICLES: return
	
	var particles = INK_SLASH_PARTICLES.instantiate()
	var spawn_offset = Vector2.ZERO
	var attack_dir = Vector2.RIGHT
	
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
	# 加到地圖層級，避免玩家走動帶著粒子走
	character.get_parent().add_child(particles)

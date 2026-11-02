extends StaticBody2D
class_name Tentacle

# =====================================================
# 📊 1. [企劃數值設定 - Design Parameters]
# =====================================================
@export_group("觸手方向設定")
@export var facing_dir: String = "right_up" # 決定要播放哪個方向的動畫 

@export_group("觸手生命屬性")
@export var max_hp: int = 30
var current_hp: int = 30
@export var lifespan: float = 11.0 # 觸手的最大存活壽命

@export_group("觸手攻擊屬性")
@export var smash_damage: int = 20           
# 🌟【打擊關鍵幀】：第 6 幀剛好碰觸地板
@export var attack_hit_frame: int = 6        
@export var hitbox_active_time: float = 0.15 
# 🌟【預警時間】：觸手出土後，在地板顯示「純紅剪影」的警告時間
@export var telegraph_time: float = 1.0      

@export_group("資源獎勵")
@export var ink_reward: float = 30.0         

# =====================================================
# 🔒 2. [內部狀態鎖 - State Locks]
# =====================================================
var original_sprite_scale: Vector2 = Vector2.ONE 

var is_active: bool = false       
var is_dead: bool = false         
var can_deal_damage: bool = false 
var attack_hit_done: bool = false 

var warning_indicator: Sprite2D = null # 🌟 專門裝載「純紅剪影」的精靈圖層
var breathing_tween: Tween        

# =====================================================
# 🔌 3. [節點綁定 - Node References]
# =====================================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var wall_shape: CollisionShape2D = $CollisionShape2D          
@onready var hitbox: Area2D = $Hitbox                                  
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var hurtbox: Hurtbox = $Hurtbox                               
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D

var hitbox_timer: Timer 

# =====================================================
# 💡 4. [初始化與防呆重置 - Initialization]
# =====================================================
func _ready() -> void:
	current_hp = max_hp
	if sprite:
		original_sprite_scale = sprite.scale
	
	wall_shape.set_deferred("disabled", true)
	hitbox_shape.set_deferred("disabled", true)
	hurtbox_shape.set_deferred("disabled", true)
	hitbox.monitoring = false
	hurtbox.monitoring = false
	hurtbox.monitorable = true

	if not sprite.frame_changed.is_connected(_on_sprite_frame_changed):
		sprite.frame_changed.connect(_on_sprite_frame_changed)
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)

	hitbox_timer = Timer.new()
	hitbox_timer.one_shot = true
	hitbox_timer.timeout.connect(_on_hitbox_timeout)
	add_child(hitbox_timer)

	if not hitbox.area_entered.is_connected(_on_hitbox_area_entered):
		hitbox.area_entered.connect(_on_hitbox_area_entered)

	_play_anim("spawn") # 播放出土動畫，此時完全沒有傷害與碰撞

# =====================================================
# 📡 5. [戰鬥機制：🌟 終極無細節純紅剪影預警 - Solid Red Silhouette Telegraph]
# =====================================================
func execute_smash() -> void:
	if is_dead or is_active: return

	# 🌟【動作 1：立刻印出預警】：
	# 呼叫純紅剪影，讓玩家清楚知道「即將砸下的形狀」與「絕對範圍」。
	_create_red_silhouette_phantom()

	# 🌟【動作 2：等待玩家反應】：(企劃設定的 1 秒鐘)
	# 觸手待命，地上的紅影會高頻閃爍警告玩家。
	await get_tree().create_timer(telegraph_time).timeout

	if not is_inside_tree() or is_dead: return
	_perform_actual_smash()

func _perform_actual_smash() -> void:
	if is_dead: return
	attack_hit_done = false 
	
	# 🌟【動作 3：完美無縫打擊】：
	# 預警時間結束，立刻把地上的紅影刪除，同時觸手開始往下揮動！
	if warning_indicator:
		warning_indicator.queue_free()
		warning_indicator = null
		
	_play_anim("attack") # 觸手本體開始播放用力砸地的動畫

# 🌟【3A 級圖形 Shader：不要長相，只要紅色形狀】
func _create_red_silhouette_phantom() -> void:
	# 1. 取得對應方向的動畫名稱
	var anim_name = "attack_" + facing_dir
	if not sprite.sprite_frames.has_animation(anim_name):
		# 🌟【修復三元運算子當機報錯】：改用標準 if-else
		var fallback_dir: String = "right"
		if facing_dir.begins_with("left"):
			fallback_dir = "left"
		anim_name = "attack_" + fallback_dir
	
	# 2. 提取「第 6 幀 (砸中地板那一幀)」的圖片作為預警的基礎形狀
	var hit_texture = sprite.sprite_frames.get_frame_texture(anim_name, attack_hit_frame)
	
	if hit_texture:
		warning_indicator = Sprite2D.new()
		warning_indicator.texture = hit_texture
		warning_indicator.scale = original_sprite_scale
		
		# 3. 🌟【正規修復 Shader - 無細節純紅】：
		# 徹底丟棄圖片原本的色彩細節 (RGB)，只保留形狀邊緣 (Alpha)，並塗滿純紅。
		var mat = ShaderMaterial.new()
		var shader = Shader.new()
		shader.code = """
		shader_type canvas_item;
		void fragment() {
			vec4 tex_color = texture(TEXTURE, UV);
			// RGB 強制設為純紅 (1.0, 0.0, 0.0)
			// Alpha 讀取圖片原來的形狀透明度，並乘上外部的 modulate 控制
			COLOR = vec4(1.0, 0.0, 0.0, tex_color.a * COLOR.a); 
		}
		"""
		mat.shader = shader
		warning_indicator.material = mat
		
		# 4. 【圖層設定】：強制壓在最底層 (Z-Index 0)，看起來就像印在地板上的影子
		add_child(warning_indicator)
		move_child(warning_indicator, 0)
		
		# 5. 🌟【視覺打磨 - 心跳閃爍】：
		# 【修復無限迴圈黃字報錯】：用精準數學計算閃爍次數，不使用無限 set_loops()！
		var blink_duration = 0.1
		var blink_count = int(telegraph_time / (blink_duration * 2)) + 1 # 計算總共需要閃幾次
		
		var t = create_tween().set_loops(blink_count)
		warning_indicator.modulate.a = 0.2 # 初始為 20% 透明
		t.tween_property(warning_indicator, "modulate:a", 0.7, blink_duration).set_trans(Tween.TRANS_SINE)
		t.tween_property(warning_indicator, "modulate:a", 0.2, blink_duration).set_trans(Tween.TRANS_SINE)

# 🌟【防掉幀機制：精準打擊系統】
func _on_sprite_frame_changed() -> void:
	if is_dead: return
	if not sprite.animation.begins_with("attack"): return
	
	# 當動畫播放剛好到達或越過第 6 幀 (砸下瞬間)
	if sprite.frame >= attack_hit_frame and not attack_hit_done:
		attack_hit_done = true 
		_activate_barricade_and_damage()

# =====================================================
# 🧱 6. [實體化與傷害判定 - Physics Activation]
# =====================================================
func _activate_barricade_and_damage() -> void:
	if is_dead or is_active: return
	is_active = true

	# 砸落瞬間，開啟三種碰撞實體
	wall_shape.set_deferred("disabled", false)   
	hurtbox_shape.set_deferred("disabled", false)
	hitbox_shape.set_deferred("disabled", false) 
	
	hitbox.monitoring = true
	can_deal_damage = true
	
	hitbox_timer.start(hitbox_active_time)

	# 砸地鏡頭震動，強化重量感
	var camera = get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"): camera.apply_shake(15.0)

	_start_breathing_effect()

func _on_hitbox_timeout() -> void:
	# 0.15 秒打擊幀結束，關閉傷害判定，轉為純物理路障
	hitbox_shape.set_deferred("disabled", true)
	hitbox.monitoring = false
	can_deal_damage = false

func _on_hitbox_area_entered(area: Area2D) -> void:
	if is_dead or not can_deal_damage: return
	if area.has_method("take_damage"): area.take_damage(smash_damage) 

# =====================================================
# ⚔️ 7. [觸手受傷與死亡縮回 - Combat & Death]
# =====================================================
func take_damage(amount: float, _hit_position: Vector2 = Vector2.ZERO, _hit_direction: Vector2 = Vector2.ZERO, _is_melee: bool = false, _extra_knockback: float = 1.0) -> void:
	if is_dead or not is_active: return
	current_hp -= int(amount)
	_play_hit_flash()

	if current_hp <= 0:
		_restore_player_ink() 
		_die()

func _restore_player_ink() -> void:
	var players = get_tree().get_nodes_in_group("Player")
	if players.is_empty(): return
	var player = players[0]
	if player.has_method("restore_ink"): player.restore_ink(ink_reward) 

func _die() -> void:
	if is_dead: return
	is_dead = true
	is_active = false
	can_deal_damage = false
	
	if breathing_tween: breathing_tween.kill() 
	hitbox_timer.stop()

	# 死亡瞬間立刻撤銷所有物理障礙，讓空間還給玩家
	wall_shape.set_deferred("disabled", true)
	hitbox_shape.set_deferred("disabled", true)
	hurtbox_shape.set_deferred("disabled", true)
	hitbox.monitoring = false
	hurtbox.monitoring = false

	if warning_indicator:
		warning_indicator.queue_free()
		warning_indicator = null

	_play_anim("die") 

func _on_animation_finished() -> void:
	if is_dead and sprite.animation.begins_with("die"):
		queue_free() # 縮回地下播完才刪除
	elif not is_dead and sprite.animation.begins_with("attack"):
		if not attack_hit_done:
			attack_hit_done = true
			_activate_barricade_and_damage()

# =====================================================
# ✨ 8. [工具區：視覺打磨特效 - Juice & Polish]
# =====================================================
func _play_hit_flash() -> void:
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.5, 0.5), 0.08)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)

func _play_anim(action: String) -> void:
	var animation_name = action + "_" + facing_dir
	if sprite.sprite_frames.has_animation(animation_name):
		sprite.play(animation_name)
		return
		
	# 🌟【修復三元運算子當機報錯】：改用標準 if-else
	var fallback_dir: String = "right"
	if facing_dir.begins_with("left"):
		fallback_dir = "left"
		
	var fallback_animation = action + "_" + fallback_dir
	if sprite.sprite_frames.has_animation(fallback_animation):
		sprite.play(fallback_animation)

# 🌟【活體呼吸效果】：
func _start_breathing_effect() -> void:
	if breathing_tween and breathing_tween.is_running(): breathing_tween.kill()
	
	# 🌟【修復無限迴圈黃字報錯】：
	# 觸手最長壽命 11 秒，呼吸一次 2.4 秒，給它跑 10 次(24秒)絕對夠用且安全！
	breathing_tween = create_tween().set_loops(10) 
	
	breathing_tween.tween_property(sprite, "scale", original_sprite_scale * Vector2(0.97, 1.03), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathing_tween.tween_property(sprite, "scale", original_sprite_scale, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

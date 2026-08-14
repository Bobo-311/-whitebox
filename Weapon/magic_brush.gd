extends Node2D
class_name MagicBrush

enum Mode { BLUE, RED, YELLOW }
var current_mode: Mode = Mode.BLUE

# ==========================================
# 🌟 載入子彈藍圖
# ==========================================
@export var blue_bullet_scene: PackedScene
@export var red_laser_scene: PackedScene
@export var yellow_shotgun_scene: PackedScene

const MAGIC_RING = preload("res://Bullet/magic_ring_effect.tscn")

@onready var bullet_spawn: Marker2D = $BulletSpawn
@onready var audio_player: AudioStreamPlayer2D = $AudioStreamPlayer2D

# 🌟 往上抓取玩家本體的節點 (使用 ../ 代表尋找父節點底下的東西)
@onready var player_sprite: AnimatedSprite2D = get_node_or_null("../AnimatedSprite2D")
@onready var charge_particles: GPUParticles2D = get_node_or_null("../ChargeParticles")
@onready var player_node = get_parent() # 抓取玩家大腦，用來取得原始縮放比例

# 🔴 紅色雷射專用變數
var is_charging: bool = false
var charge_timer: float = 0.0
var charge_stage: int = 1         
var last_stage: int = 0           
var max_allowed_stages: int = 3   
@export var max_charge_time: float = 2.0 

func _process(delta: float) -> void:
	look_at(get_global_mouse_position())
	
	# 🔴 蓄力段數計算
	if is_charging and current_mode == Mode.RED:
		charge_timer += delta
		charge_timer = clamp(charge_timer, 0.0, max_charge_time)
		
		# 每 1.0 秒升級一段
		charge_stage = min(floor(charge_timer / 1.0) + 1, max_allowed_stages, 3)
		
		# 當段數突破時，觸發「玩家本體」的升級特效！
		if charge_stage > last_stage:
			_play_stage_up_effect(charge_stage)
			last_stage = charge_stage

# ==========================================
# 🎮 給 Player 呼叫的外部 API
# ==========================================
func press_shoot(buff: float, allowed_stages: int = 3) -> void:
	match current_mode:
		Mode.BLUE:
			_shoot_blue(buff)
		Mode.RED:
			is_charging = true
			charge_timer = 0.0
			charge_stage = 1
			last_stage = 0 
			max_allowed_stages = clamp(allowed_stages, 1, 3)
			
			# 🌟 開始蓄力：瞬間顯示，並強制重置清除舊殘影！
			if charge_particles: 
				charge_particles.show()        # 把隱藏的節點叫出來
				charge_particles.restart()     # 清除所有舊粒子，從零開始完美聚氣
				charge_particles.emitting = true
			
		Mode.YELLOW:
			_shoot_yellow(buff)

func release_shoot(buff: float) -> void:
	if current_mode == Mode.RED and is_charging:
		is_charging = false
		
		# 🌟 停止蓄力：關閉發射，並瞬間隱藏所有粒子！
		if charge_particles: 
			charge_particles.emitting = false
			charge_particles.hide()  # 瞬間把整個特效藏起來，毫不拖泥帶水！
			
		_shoot_red_laser(buff)
		
func set_mode(new_mode: Mode) -> void:
	current_mode = new_mode
	is_charging = false 
	
	# 🌟 切換武器也要瞬間隱藏
	if charge_particles: 
		charge_particles.emitting = false
		charge_particles.hide()

func get_current_stage() -> int:
	return charge_stage

# ==========================================
# 🌟 蓄力「升段」特效 (作用於玩家身上)
# ==========================================
func _play_stage_up_effect(stage: int) -> void:
	if stage <= 1: return
	print("🔥 蓄力達到第 ", stage, " 段！")
	
	# 1. 🌟 玩家身體閃爍超亮白光，並稍微膨脹
	if player_sprite:
		var tween = create_tween()
		var original_scale = Vector2.ONE
		if player_node and "original_sprite_scale" in player_node:
			original_scale = player_node.original_sprite_scale
			
		player_sprite.modulate = Color(3.0, 3.0, 3.0, 1.0) 
		tween.tween_property(player_sprite, "modulate", Color.WHITE, 0.15)
		
		player_sprite.scale = original_scale * 1.15
		tween.parallel().tween_property(player_sprite, "scale", original_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 2. 🌟 鏡頭晃動 (段數越高，晃得越大力)
	var shake_str = 3.0 + (stage * 2.0) # 2段=7.0, 3段=9.0
	get_tree().call_group("main_camera", "apply_shake", shake_str)

	# 3. 生成能量擴散光環 (從玩家中心往外擴散)
	if MAGIC_RING:
		var ring = MAGIC_RING.instantiate()
		get_tree().current_scene.add_child(ring)
		ring.global_position = player_node.global_position # 從玩家身體發出
		var ring_scale = 0.5 * stage 
		ring.scale = Vector2(ring_scale, ring_scale)
		ring.modulate = Color(2.0, 1.0, 1.0, 1.0)

	# 4. 播放音效
	if audio_player:
		audio_player.pitch_scale = 1.0 + (stage * 0.2) 
		audio_player.play()

# ==========================================
# 🔫 武器發射邏輯 
# ==========================================
func _shoot_blue(buff: float) -> void:
	if not blue_bullet_scene: return
	var bullet = blue_bullet_scene.instantiate()
	_spawn_projectile(bullet)
	bullet.direction = (get_global_mouse_position() - bullet_spawn.global_position).normalized()
	bullet.shooter = player_node
	bullet.received_buff = buff
	_play_shoot_effects(1.0) 

func _shoot_red_laser(buff: float) -> void:
	if not red_laser_scene: return
	var laser = red_laser_scene.instantiate()
	_spawn_projectile(laser)
	laser.direction = (get_global_mouse_position() - bullet_spawn.global_position).normalized()
	laser.shooter = player_node
	laser.received_buff = buff
	laser.charge_stage = charge_stage
	laser.fire_laser() 
	
	var effect_intensity = 0.5 + ((charge_stage - 1) * 0.75)
	_play_shoot_effects(effect_intensity) 

func _shoot_yellow(buff: float) -> void:
	pass

# ==========================================
# 🎨 發射瞬間的共用特效
# ==========================================
func _spawn_projectile(proj: Node) -> void:
	get_tree().current_scene.add_child(proj)
	proj.global_position = bullet_spawn.global_position

func _play_shoot_effects(intensity: float) -> void:
	# 這裡保留了射擊時原本的後座力音效與頓幀，但把槍管縮放拿掉了，以免干擾玩家本體的動畫
	if audio_player:
		if current_mode == Mode.RED:
			audio_player.pitch_scale = lerp(1.2, 0.6, intensity / 2.0)
		else:
			audio_player.pitch_scale = randf_range(0.9, 1.1)
		audio_player.play()

	if DataManager and DataManager.has_method("hitstop"):
		DataManager.hitstop(0.03 * intensity)

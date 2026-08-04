extends BaseCharacter             # 繼承基礎角色類別，獲得扣血、死亡等功能
class_name Enemy                  # 定義為 Enemy 類別

# ==========================================
# ⚙️ 匯出參數與預載資源
# ==========================================
@export var walk_speed: int = 150                   # 野豬的漫遊走路速度
@export var sprint_speed: int = 450                # 野豬追擊玩家時的衝刺速度
@export var attack_speed_multiplier: float = 2.5  # 野豬發動衝撞攻擊時的速度倍率
@export var attack_time: float = 0.45              # 攻擊狀態維持的時間長度
@export var melee_damage: float = 15.0             # 野豬肉身衝撞造成的近戰傷害量

# 🌟【本次新增】受傷微擊退力道 (可在 Inspector 自由調整)
@export var knockback_strength: float = 220.0       # 🌟 擊退力道 (220 剛好是稍稍往後退一小步)

const COIN_SCENE = preload("res://coin/coin.tscn") # 預載入金幣場景

# ==========================================
# 🔗 節點引用
# ==========================================
@onready var state_machine: StateMachine = $StateMachine       # 狀態機節點
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 動畫播放器
@onready var hp_bar: ProgressBar = $HealthBar                  # 血條 UI 節點
@onready var vision_ray: RayCast2D = $VisionRay                 # 視線雷射
@onready var hitbox: Area2D = get_node_or_null("Hitbox")       # 🌟 抓取原有的 Hitbox

# ==========================================
# 📊 狀態與變數
# ==========================================
var can_see_player: bool = false                # 野豬自身 AI 追擊判定：到底有沒有看見玩家？
var player_node: CharacterBody2D = null           # 記憶目前鎖定的玩家實體
var last_facing_vec: Vector2 = Vector2.DOWN       # 記憶野豬最後面朝的方向
var has_hit_player: bool = false                  # 標記開關：衝刺狀態使用的傷害開關
var can_attack: bool = true                       # 攻擊冷卻開關

# 🌟【防縮水修復】自動記憶 Inspector 設定的原始精靈圖大小
var original_sprite_scale: Vector2 = Vector2.ONE

# 🌟【整合白貓視覺】是否被白貓燈光照到與漸變控制
var is_illuminated_by_cat: bool = false
var fade_tween: Tween = null

# ==========================================
# 🚀 初始化與物理幀處理
# ==========================================
func _ready() -> void:
	super._ready()                               # 呼叫父類別 BaseCharacter 的 _ready，確保血量補滿
	
	# 自動記錄編輯器中設定的精靈圖縮放比例
	if animated_sprite_2d:
		original_sprite_scale = animated_sprite_2d.scale
	
	if hitbox:
		if not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
			hitbox.body_entered.connect(_on_hitbox_body_entered)

	# 預設藏在迷霧/黑暗中
	self.visible = false
	self.modulate.a = 0.0

func _physics_process(_delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		
	move_and_slide()
	
	_check_hitbox_overlap()
	
	# --- 真實視野雷射掃描系統 (供野豬 AI 追擊玩家使用) ---
	if player_node != null:                      # 玩家在藍色感知圈圈內
		vision_ray.target_position = to_local(player_node.global_position)
		vision_ray.force_raycast_update()        # 強制雷射在一幀內更新結果
		
		if vision_ray.is_colliding():
			can_see_player = false               # 雷射被擋住 ＝ 視線被遮擋
		else:
			can_see_player = true                # 雷射一路暢通 ＝ 野豬看到玩家，準備鎖定追擊！
	else:
		can_see_player = false                   # 不在圈圈內

# ==========================================
# 👁️ 迷霧與白貓照亮現形系統 (Tween 動畫)
# ==========================================
func update_visibility() -> void:
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
		
	fade_tween = create_tween()
	
	if is_illuminated_by_cat:
		self.visible = true
		fade_tween.tween_property(self, "modulate:a", 1.0, 0.35)
	else:
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.35)
		fade_tween.tween_callback(func():
			if not is_illuminated_by_cat:
				self.visible = false
		)

# ==========================================
# 💥 戰鬥、受擊擊退與死亡邏輯
# ==========================================

# 🌟【本次新增】受擊傷害與擊退處理
func take_damage(amount: float = 0.0, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead: return
	
	current_hp = max(current_hp - amount, 0)
	update_hp_bar()
	
	# 1️⃣ 計算受擊微擊退方向與滑行煞車
	var knockback_dir = dir
	if knockback_dir == Vector2.ZERO and attacker_pos != Vector2.ZERO:
		knockback_dir = (global_position - attacker_pos).normalized()
		
	if knockback_dir != Vector2.ZERO:
		velocity = knockback_dir * knockback_strength
		# 使用 Tween 在 0.15 秒內將擊退速度平滑衰減至 0 (滑行停下的受擊感)
		var kb_tween = create_tween()
		kb_tween.tween_property(self, "velocity", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2️⃣ 播放打擊視覺與手感特效 (頓幀、閃白、擠壓)
	play_hit_effects(attacker_pos)
	
	if current_hp <= 0:
		die()
	else:
		handle_hurt()

# 🌟 打擊感核心反饋：頓幀 + 閃白 + 擠壓 + 震動
func play_hit_effects(_attacker_pos: Vector2 = Vector2.ZERO) -> void:
	# 1️⃣ 觸發全域頓幀 (卡肉感 0.06 秒)
	if DataManager and DataManager.has_method("trigger_hitstop"):
		DataManager.trigger_hitstop(0.06, 0.05)
		
	# 2️⃣ 觸發鏡頭微震
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(8.0)
		
	# 3️⃣ 畫面精靈圖：高亮閃白 + 彈性擠壓變形
	if animated_sprite_2d:
		var tween = create_tween().set_parallel(true)
		
		# 瞬間變白高亮
		animated_sprite_2d.modulate = Color(4, 4, 4)
		tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.12)
		
		# 依據原始比例做 1.25 / 0.75 擠壓，最後平滑彈回原始大小
		animated_sprite_2d.scale = Vector2(original_sprite_scale.x * 1.25, original_sprite_scale.y * 0.75)
		tween.tween_property(animated_sprite_2d, "scale", original_sprite_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func handle_hurt() -> void:
	var state_name = state_machine.current_state.name.to_lower()
	
	if "stun" in state_name or "pant" in state_name: 
		return 
		
	state_machine.change_state("EnemyHurt")

func die() -> void:
	if is_dead: return                            # 防呆：死過就不再執行
	is_dead = true
	velocity = Vector2.ZERO                       # 死掉瞬間將物理速度踩死
	state_machine.change_state("EnemyDie")        # 狀態機切換至 EnemyDie
	drop_coin()                                   # 在野豬消失前噴錢！

func update_hp_bar() -> void:
	if hp_bar and hp_bar.has_method("update_bar"):
		hp_bar.update_bar(current_hp, max_hp)

func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO) -> void:
	var suffix = "" 
	var target_dir = dir if dir != Vector2.ZERO else last_facing_vec
	
	if abs(target_dir.x) > abs(target_dir.y): 
		suffix = "_right" if target_dir.x > 0 else "_left" 
	else: 
		suffix = "_down" if target_dir.y > 0 else "_up" 
	
	animated_sprite_2d.play(prefix + suffix)

# ==========================================
# 💰 掉落物品系統
# ==========================================
func drop_coin() -> void:
	if COIN_SCENE:
		for i in range(5):
			var delay = randf_range(0.01, 0.1)
			get_tree().create_timer(delay).connect("timeout", func():
				var coin = COIN_SCENE.instantiate()
				var spawn_pos = global_position
				
				if DataManager and DataManager.player_node:
					var dir_to_player = global_position.direction_to(DataManager.player_node.global_position)
					var safe_offset = dir_to_player * randf_range(15.0, 30.0)
					var random_jitter = Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
					spawn_pos = global_position + safe_offset + random_jitter
				else:
					spawn_pos = global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
				
				var local_pos = get_parent().to_local(spawn_pos)
				coin.position = local_pos
				get_parent().add_child(coin)
			)

# ==========================================
# 🛡️ 利用原有的 Hitbox 處理肉身碰撞傷害
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void: 
	var parent = area.get_parent() 

	if parent is Player or parent.is_in_group("player") or parent.name == "player":
		_apply_damage_and_knockback(parent, area)

	elif parent is WhiteCat or parent.is_in_group("white_cat"):
		if parent.has_method("take_damage"):
			parent.take_damage(melee_damage, global_position)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player or body.is_in_group("player") or body.name == "player":
		_apply_damage_and_knockback(body, null)

func _apply_damage_and_knockback(target: Node2D, target_area: Area2D = null) -> void:
	var knockback_dir: Vector2 = (target.global_position - global_position).normalized()
	
	if target_area and target_area.has_method("take_damage"):
		target_area.take_damage(melee_damage, global_position)
	elif target.has_method("take_damage"):
		target.take_damage(melee_damage, global_position, knockback_dir)

func _check_hitbox_overlap() -> void:
	if not hitbox: return
	
	for body in hitbox.get_overlapping_bodies():
		if body is Player or body.is_in_group("player") or body.name == "player":
			_apply_damage_and_knockback(body, null)

# ==========================================
# 📡 視野與感知訊號
# ==========================================
func _on_detect_player_body_entered(body) -> void: 
	if body is Player or body.is_in_group("player") or body.name == "player": 
		player_node = body

func _on_detect_player_body_exited(body) -> void: 
	if body == player_node or body.is_in_group("player"): 
		player_node = null

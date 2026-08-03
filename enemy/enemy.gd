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

# 🌟【整合白貓視覺】是否被白貓燈光照到與漸變控制
var is_illuminated_by_cat: bool = false
var fade_tween: Tween = null

# ==========================================
# 🚀 初始化與物理幀處理
# ==========================================
func _ready() -> void:
	super._ready()                               # 呼叫父類別 BaseCharacter 的 _ready，確保血量補滿
	
	# 不再禁用 Hitbox，保持常開隨時檢測受傷與彈開
	if hitbox:
		if not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
			hitbox.body_entered.connect(_on_hitbox_body_entered)

	# 預設藏在迷霧/黑暗中
	self.visible = false
	self.modulate.a = 0.0

func _physics_process(_delta: float) -> void:
	# 🌟【本次新增：防推擠核心防呆】死掉時速度立刻清零，防範物理重疊推擠
	if is_dead:
		velocity = Vector2.ZERO
		
	move_and_slide()
	
	# 🌟 持續碰撞檢查：如果玩家一直貼著 Hitbox 擠壓，無敵時間過後繼續彈開
	_check_hitbox_overlap()
	
	# --- 真實視野雷射掃描系統 (供野豬 AI 追擊玩家使用) ---
	if player_node != null:                      # 玩家在藍色感知圈圈內
		vision_ray.target_position = to_local(player_node.global_position)
		vision_ray.force_raycast_update()        # 強制雷射在一幀內更新結果
		
		# 檢查雷射光有沒有撞到障礙物（牆壁/柱子）
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
		# 0.35 秒內平滑漸變現形
		fade_tween.tween_property(self, "modulate:a", 1.0, 0.35)
	else:
		# 0.35 秒內平滑漸變隱形
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.35)
		fade_tween.tween_callback(func():
			if not is_illuminated_by_cat:
				self.visible = false
		)

# ==========================================
# 💥 戰鬥、受傷與死亡邏輯
# ==========================================
func handle_hurt() -> void:
	var state_name = state_machine.current_state.name.to_lower()
	
	# 破綻鎖定：如果正在暈眩 (stun) 或喘氣 (pant) 期間
	if "stun" in state_name or "pant" in state_name: 
		velocity = knockback_force 
		
		# 瞬間變白打擊高亮特效
		var hit_tween = get_tree().create_tween()
		animated_sprite_2d.modulate = Color(3, 3, 3)
		hit_tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.1)
		
		return 
		
	# 平常走路或站立被打時，切換到受傷狀態
	state_machine.change_state("EnemyHurt")

func die() -> void:
	if is_dead: return                            # 防呆：死過就不再執行
	is_dead = true
	velocity = Vector2.ZERO                       # 🌟【防推擠】死掉瞬間將物理速度踩死
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
# 🛡️ 🌟 利用原有的 Hitbox 處理肉身碰撞傷害
# ==========================================
# 1. 檢測 Area2D (例如 Player 的 Hurtbox)
func _on_hitbox_area_entered(area: Area2D) -> void: 
	var parent = area.get_parent() 

	# 🎯 打中玩家的 Hurtbox
	if parent is Player or parent.is_in_group("player") or parent.name == "player":
		_apply_damage_and_knockback(parent, area)

	# 🐱 打中白貓
	elif parent is WhiteCat or parent.is_in_group("white_cat"):
		if parent.has_method("take_damage"):
			parent.take_damage(melee_damage, global_position)

# 2. 檢測 CharacterBody2D (當玩家實體撞上野豬 Hitbox)
func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player or body.is_in_group("player") or body.name == "player":
		_apply_damage_and_knockback(body, null)

# 3. 執行傷害與彈開的統一核心邏輯
func _apply_damage_and_knockback(target: Node2D, target_area: Area2D = null) -> void:
	var knockback_dir: Vector2 = (target.global_position - global_position).normalized()
	
	if target_area and target_area.has_method("take_damage"):
		target_area.take_damage(melee_damage, global_position)
	elif target.has_method("take_damage"):
		target.take_damage(melee_damage, global_position, knockback_dir)

# 4. 物理幀持續檢查 (防止玩家死貼著野豬)
func _check_hitbox_overlap() -> void:
	if not hitbox: return
	
	# 檢查被 Hitbox 疊加的所有實體
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

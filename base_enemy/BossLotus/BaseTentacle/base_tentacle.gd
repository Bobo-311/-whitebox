extends StaticBody2D

# ==========================================
# 📊 [觸手數值設定]
# ==========================================
@export_group("觸手生命屬性")
@export var max_hp: int = 30
var current_hp: int = 30
@export var lifespan: float = 11.0 # 觸手在地上的存活時間

@export_group("觸手攻擊屬性")
@export var smash_damage: float = 20.0 
# 🌟【關鍵數值】砸下瞬間的「活躍幀 (Active Frames)」
# 強烈建議設為 0.1 ~ 0.15 秒，避免玩家走過去撞到靜止觸手還扣血
@export var hitbox_active_time: float = 0.15 

@export_group("資源獎勵")
@export var ink_reward: float = 30.0 

# ==========================================
# ⚙️ [系統狀態與節點綁定]
# ==========================================
var life_timer: float = 0.0
var is_active: bool = false # 是否已砸下 (成為實體路障)
var can_deal_damage: bool = false # 🌟【鐵門開關】防護機制，決定當下是否能對玩家扣血

@onready var anim_player = $AnimationPlayer
@onready var sprite = $Sprite2D
@onready var hitbox_collision = $Hitbox/CollisionShape2D 

# ==========================================
# 🌱 [階段 1：生成與預警 (Telegraph)]
# ==========================================
func _ready() -> void:
	current_hp = max_hp
	is_active = false
	can_deal_damage = false # 預警期間，鐵門死鎖
	
	sprite.modulate.a = 0.0 # 隱藏觸手實體
	hitbox_collision.set_deferred("disabled", true) # 關閉傷害框
	
	# 【正規作法】：一出生只播放 Warning (紅圈閃爍)，等待 Boss 下令
	if anim_player.has_animation("Warning"):
		anim_player.play("Warning")

# ==========================================
# 📡 [公共 API] 供 Boss 的大腦呼叫，正式砸下
# ==========================================
func execute_smash() -> void:
	# 播放剛才設定好的 Smash 動畫。
	# 注意：這個動畫的 0.0 秒處，有一條綠色軌道會去戳下面的 _on_spawn_finished()
	if anim_player.has_animation("Smash"):
		anim_player.play("Smash")
	else:
		_on_spawn_finished() # 防呆，以防動畫沒設定好

# ==========================================
# 💥 [階段 2：砸下瞬間 (Active Frames)]
# ==========================================
# 由 Smash 動畫的綠色軌道精準呼叫
func _on_spawn_finished() -> void:
	is_active = true
	can_deal_damage = true # 💡 打開鐵門：允許扣血
	print("🌿 觸手實體化砸下！啟動瞬時致命傷害！")
	
	hitbox_collision.set_deferred("disabled", false)
	
	# 啟動極短計時器 (例如 0.15s 後)，把傷害拔除
	get_tree().create_timer(hitbox_active_time).timeout.connect(func():
		can_deal_damage = false # 💡 關閉鐵門：即使物理碰撞晚了幾幀關閉，邏輯上也絕對不扣血
		print("🛡️ 瞬時傷害結束，轉為無害路障。")
		if is_instance_valid(hitbox_collision):
			hitbox_collision.set_deferred("disabled", true)
	)

# ==========================================
# ⚔️ [攻擊邏輯] 碰到玩家時
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	# 🌟【雙重保險】如果鐵門關著 (非致命期)，直接無視碰撞，防止殘留傷害！
	if not can_deal_damage: 
		return 
	
	if area.has_method("take_damage"):
		print("💥 觸手精準命中玩家！扣血：", smash_damage)
		area.take_damage(smash_damage)

# ==========================================
# ⏳ [壽命與受擊邏輯] (維持原樣)
# ==========================================
func _process(delta: float) -> void:
	if not is_active: return # 預警期間不扣壽命
	
	life_timer += delta
	if life_timer >= lifespan:
		_die()

func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if not is_active: return # 預警期間無敵
	
	current_hp -= int(amount)
	
	if current_hp > 0:
		if anim_player.has_animation("HitFlash"):
			anim_player.play("HitFlash")
	else:
		_die()

func _die() -> void:
	is_active = false
	
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	hitbox_collision.set_deferred("disabled", true)
	
	# 回饋墨水給玩家
	var player = get_tree().get_first_node_in_group("Player")
	if player and player.has_method("restore_ink"):
		player.restore_ink(ink_reward)
	
	if anim_player.has_animation("Die"):
		anim_player.play("Die")
	else:
		queue_free()

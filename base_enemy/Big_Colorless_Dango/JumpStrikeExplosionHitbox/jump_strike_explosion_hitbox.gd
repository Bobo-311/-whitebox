extends Area2D

# ==========================================
# ⚙️ 王a燈：落地核爆判定區 (獨立特效碰撞體)
# ==========================================
@export_category("💥 爆炸數值設定")
@export var damage: float = 50.0               # 極高傷害，懲罰貪刀玩家
@export var extra_knockback_multiplier: float = 3.5 # 極致擊退！把玩家炸飛超遠
@export var active_frames_duration: float = 0.2     # 傷害有效時間 (只有爆炸前0.2秒會扣血)

@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

var has_dealt_damage: bool = false # 確保每個玩家只會受到一次傷害

# ==========================================
# 🎬 爆炸生命週期
# ==========================================
func _ready():
	# 1. 確保一出生，動畫就從第一幀開始播
	animated_sprite.play("explode")
	
	# 2. 綁定打到玩家的訊號 (Area2D 或 Body)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# 3. 🧠【遊戲思考：判定幀控制 (Active Frames)】
	# 真正的傷害只有瞬間爆開那一下。煙霧散去時踩進去是不會扣血的。
	# 所以 0.2 秒後，我們強制關閉碰撞箱！
	var timer = get_tree().create_timer(active_frames_duration)
	timer.timeout.connect(func():
		collision_shape.set_deferred("disabled", true)
	)
	
	# 4. 綁定動畫結束的訊號：播完就自我刪除，不留垃圾
	animated_sprite.animation_finished.connect(func():
		queue_free()
	)

# ==========================================
# ⚔️ 傷害與物理推擠結算
# ==========================================
func _on_area_entered(area: Area2D):
	_apply_explosion(area)

func _on_body_entered(body: Node2D):
	_apply_explosion(body)

func _apply_explosion(target) -> void:
	# 🛡️ 防呆：如果已經炸過，或者時間過了碰撞箱關閉，就不做事
	if has_dealt_damage or collision_shape.disabled: return
	
	# 檢查目標是不是玩家 (或者玩家的 Hurtbox)
	if target.is_in_group("player") or target.name == "player" or target is Hurtbox:
		# 確定炸到人了，鎖定標記避免重複扣血
		has_dealt_damage = true
		
		# 📐 計算核爆衝擊波方向 (從爆炸中心往外推)
		var knockback_dir = (target.global_position - global_position).normalized()
		
		# 💥 呼叫受擊函數 (把極致的傷害與 3.5 倍擊退傳遞出去)
		if target.has_method("take_damage"):
			target.take_damage(damage, global_position, knockback_dir, false, extra_knockback_multiplier)
		elif target.get_parent() and target.get_parent().has_method("take_damage"):
			target.get_parent().take_damage(damage, global_position, knockback_dir, false, extra_knockback_multiplier)
			
		# 🎥 打中玩家時，額外加上極度強烈的死亡震屏
		var camera = get_tree().get_first_node_in_group("camera")
		if camera and camera.has_method("apply_shake"):
			camera.apply_shake(35.0)

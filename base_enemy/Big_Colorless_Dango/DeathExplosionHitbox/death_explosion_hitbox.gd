extends Area2D

# ==========================================
# 💀 死亡終極核爆判定區 (Boss Death Explosion Hitbox)
# ==========================================
# 【類似遊戲思考】：這是 Boss 臨死前的最後反撲，數值必須極度不講理。
# 用超高傷害和誇張的擊退，懲罰那些看到 Boss 沒血就貪刀貼上去的玩家。
@export_category("💥 死亡核爆數值")
@export var damage: float = 50.0                    # 致命傷害
@export var extra_knockback_multiplier: float = 5.0 # 5倍擊退力！強行把周圍清空
@export var active_frames_duration: float = 0.3     # 【正規作法】判定幀：只有前0.3秒有傷害

@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

# 防呆機制：確保同一個實體（玩家）在這個爆炸中只會受到一次傷害
var has_dealt_damage: bool = false

func _ready():
	# 1. 確保一出生，橘紅色核爆動畫就從第一幀開始播
	animated_sprite.play("explode")
	
	# 2. 綁定打到玩家的訊號
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# 3. 🧠【正規作法：Active Frames (攻擊判定幀) 控制】
	# 煙霧消散時踩進去不該扣血。0.3 秒後，強制關閉物理碰撞箱 (CollisionShape2D)。
	var timer = get_tree().create_timer(active_frames_duration)
	timer.timeout.connect(func():
		collision_shape.set_deferred("disabled", true)
	)
	
	# 4. 🧠【正規作法：自動垃圾回收 (Garbage Collection)】
	# 動畫播完後，這個特效物件就沒有用了。
	# 讓它呼叫 queue_free 自我毀滅，保持 Scene Tree 乾淨，避免遊戲越玩越卡。
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
	# 🛡️ 雙重防呆：如果已經炸過，或者碰撞箱已經關閉 (變成無害煙霧了)，直接退出不做事
	if has_dealt_damage or collision_shape.disabled: return
	
	# 鎖定目標：只對玩家或玩家的受擊區有反應
	if target.is_in_group("player") or target.name == "player" or target is Hurtbox:
		has_dealt_damage = true # 標記為已造成傷害
		
		# 📐 向量數學：計算從「爆炸中心」往「玩家位置」推出去的方向
		var knockback_dir = (target.global_position - global_position).normalized()
		
		# 💥 呼叫玩家的受擊函數，並把 5 倍擊退的參數傳遞過去
		if target.has_method("take_damage"):
			target.take_damage(damage, global_position, knockback_dir, false, extra_knockback_multiplier)
		elif target.get_parent() and target.get_parent().has_method("take_damage"):
			target.get_parent().take_damage(damage, global_position, knockback_dir, false, extra_knockback_multiplier)
			
		# 🎥 【類似遊戲思考：極致的打擊回饋 (Juice)】
		# 打中玩家的瞬間，給予全遊戲最強烈的震屏 (數值設為 50.0)，營造出真正的毀滅感。
		var camera = get_tree().get_first_node_in_group("camera")
		if camera and camera.has_method("apply_shake"):
			camera.apply_shake(50.0)

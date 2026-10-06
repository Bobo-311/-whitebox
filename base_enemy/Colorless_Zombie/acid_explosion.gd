extends Area2D
class_name AcidExplosion

# ==========================================
# ⚙️ 炸藥設定面板 (改由爆炸來控制傷害！)
# ==========================================
@export_group("爆炸傷害設定")
@export var damage: float = 20.0             # 爆炸傷害
@export var extra_knockback: float = 1.0     # 爆炸擊退力道

@onready var anim = $AnimatedSprite2D
var hit_targets = [] # 🌟【防呆名單】記錄這次爆炸已經炸過誰，防止重複扣血

func _ready() -> void:
	# 動畫播完，自我銷毀
	anim.animation_finished.connect(queue_free)
	anim.play("explode")
	
	# 圓形爆炸可以給個隨機角度，讓視覺不單調
	rotation_degrees = randf_range(0, 360)

	# 🌟 爆炸出現的瞬間，開啟雷達偵測！
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# 如果這個人已經在「炸過的名單」裡，就直接忽略
	if body in hit_targets: return 
	
	if body.is_in_group("player") or body.name == "player":
		hit_targets.append(body) # 把玩家加入已炸名單
		
		# 執行真實的傷害與擊退
		if body.has_method("take_damage"):
			var knockback_dir = global_position.direction_to(body.global_position)
			body.take_damage(damage, global_position, knockback_dir, false, extra_knockback)

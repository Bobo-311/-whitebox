extends Area2D
class_name AcidExplosion

# -------------------------------------------------------------------------
# ⚙️ 炸藥傷害面板
# -------------------------------------------------------------------------
@export_group("爆炸傷害設定")
@export var damage: float = 20.0             # 爆炸基礎傷害
@export var extra_knockback: float = 1.0     # 擊退倍率

@onready var anim = $AnimatedSprite2D

# 🌟【防呆名單】記錄這次爆炸已經炸過誰，防止同一次爆炸重複扣血
var hit_targets = [] 

# -------------------------------------------------------------------------
# 🎬 生命週期初始化
# -------------------------------------------------------------------------
func _ready() -> void:
	# 動畫播完後，立刻刪除自己釋放記憶體
	anim.animation_finished.connect(queue_free)
	anim.play("explode")
	
	# 給爆炸一點隨機旋轉，增加視覺豐富度
	rotation_degrees = randf_range(0, 360)

	# 🌟【關鍵修改：改用 area_entered】
	# 因為我們要撞的是玩家的 Hurtbox (Area2D 節點)，所以必須聽取 area_entered 訊號
	area_entered.connect(_on_area_entered)

# -------------------------------------------------------------------------
# 💥 傷害觸發邏輯
# -------------------------------------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	# 確認撞到的是不是玩家的受傷區 (Hurtbox)
	if area.is_in_group("player_hurtbox") or area.name == "Hurtbox":
		
		# 🌟【溯源機制】Hurtbox 只是判定區，真正的血量函數在玩家本體 (老爸) 身上
		var player_body = area.get_parent()
		
		# 如果這個玩家已經被這次爆炸炸過了，就忽略
		if player_body in hit_targets: return 
		
		# 把玩家加進已炸名單
		hit_targets.append(player_body) 
		
		# 呼叫玩家的扣血函數
		if player_body.has_method("take_damage"):
			var knockback_dir = global_position.direction_to(player_body.global_position)
			player_body.take_damage(damage, global_position, knockback_dir, false, extra_knockback)

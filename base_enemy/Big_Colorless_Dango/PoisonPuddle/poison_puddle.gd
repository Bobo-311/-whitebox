extends Area2D

@export_category("☠️ 毒沼危害設定")
@export var duration: float = 5.0            # 企劃：毒沼存在 5 秒
@export var tick_damage: float = 5.0         # 企劃：每次扣 5 滴血
@export var tick_rate: float = 0.5           # 每 0.5 秒扣一次血
@export var speed_debuff_ratio: float = 0.5  # 企劃：緩速 50% (乘以 0.5)

var victims_inside: Array = [] # 記錄有誰踩在毒沼裡
var damage_timer: Timer

func _ready() -> void:
	# 1. 建立扣血計時器 (每 0.5 秒觸發一次)
	damage_timer = Timer.new()
	add_child(damage_timer)
	damage_timer.wait_time = tick_rate
	damage_timer.timeout.connect(_on_damage_tick)
	damage_timer.start()
	
	# 2. 綁定玩家踩進來、離開的訊號
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# 3. 🌟 啟動漸隱與壽命週期 (取代原本生硬的瞬間消失)
	_start_lifecycle()

# ==========================================
# ⏳ 漸隱消失動畫與壽命管理
# ==========================================
func _start_lifecycle() -> void:
	# 1. 計算存在時間 (總時長減去 1 秒的漸隱時間)
	var fade_time = 1.0
	var exist_time = max(0.1, duration - fade_time) 
	
	# 等待主要存在時間
	await get_tree().create_timer(exist_time).timeout
	
	# 2. 時間到了，先停止扣血計時器 (快消失的毒沼沒有傷害，給玩家視覺提示)
	if damage_timer:
		damage_timer.stop()
	
	# 3. 建立 Tween 動畫，把 Sprite2D 的透明度在 1 秒內降到 0
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, fade_time)
		await tween.finished # 等待這 1 秒的漸隱動畫播完
		
	# 4. 動畫播完後，徹底刪除毒沼
	queue_free()

# ==========================================
# 🐌 緩速機制
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	# 如果是玩家踩進來
	if body.is_in_group("player") or body.name == "player":
		victims_inside.append(body) # 抓進受害者名單
		
		# 🌟【緩速 50%】
		if "walk_speed" in body: 
			body.walk_speed *= speed_debuff_ratio 

func _on_body_exited(body: Node2D) -> void:
	# 如果玩家離開毒沼
	if body in victims_inside:
		victims_inside.erase(body) # 從受害者名單剔除
		
		# 🌟【解除緩速】速度除以 0.5，等於恢復 100% 的速度
		if "walk_speed" in body:
			body.walk_speed /= speed_debuff_ratio

# ==========================================
# 🩸 持續傷害 (Tick Damage)
# ==========================================
func _on_damage_tick() -> void:
	# 每隔 0.5 秒，對所有還踩在裡面的受害者扣血
	for victim in victims_inside:
		if victim.has_method("take_damage"):
			# 傳入傷害 5，且不帶有任何擊退方向 (Vector2.ZERO)，避免玩家在毒沼裡被推來推去
			victim.take_damage(tick_damage, global_position, Vector2.ZERO)

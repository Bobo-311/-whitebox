extends Area2D
class_name DarkOrb # 暗影迴旋球

@export_group("迴旋鏢設定")
@export var flight_distance: float = 350.0   # 球最遠可以飛多遠？
@export var flight_duration: float = 0.8     # 飛過去要多久？(時間越短飛越快)
@export var explosion_scene: PackedScene     # 把你剛改好的小爆炸場景拖進來！

# 🌟【系統防呆】穿透冷卻鎖：記錄 [玩家物件 : 倒數計時]
# 防止球穿過身體時，每幀都瘋狂產生爆炸
var hit_cooldowns: Dictionary = {} 

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# ==========================================
# 🔄 物理更新 (負責倒數冷卻時間)
# ==========================================
func _physics_process(delta: float) -> void:
	var targets = hit_cooldowns.keys()
	for t in targets:
		hit_cooldowns[t] -= delta
		# 如果 0.5 秒過去了，就把玩家從鎖定名單移除，球飛回來時就可以「再次引爆」！
		if hit_cooldowns[t] <= 0:
			hit_cooldowns.erase(t)

# ==========================================
# 🚀 發射邏輯：迴旋鏢軌跡 (去程與回程)
# ==========================================
func fire(start_pos: Vector2, target_pos: Vector2) -> void:
	self.global_position = start_pos
	
	# 算出發射方向
	var dir = start_pos.direction_to(target_pos)
	
	# 🌟 計算極限折返點 (去程的終點)
	var end_pos = start_pos + (dir * flight_distance)
	
	# 利用 Tween 輕鬆做出完美的溜溜球手感
	var tween = create_tween()
	
	# 動畫 A【去程】：飛向極限距離 (使用 QUAD 與 EASE_OUT，讓球在最遠處會有「減速滯空」的感覺)
	tween.tween_property(self, "global_position", end_pos, flight_duration)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	# 動畫 B【回程】：飛回殭屍嘴巴 (使用 QUAD 與 EASE_IN，讓球飛回來時「越吸越快」)
	tween.tween_property(self, "global_position", start_pos, flight_duration)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
	# 去回兩趟都跑完後，球自動銷毀
	tween.chain().tween_callback(queue_free)

# ==========================================
# 💥 引信觸發：碰到玩家就生成爆炸！
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "player":
		
		# 🌟【穿透冷卻鎖】：如果這顆球在 0.5 秒內已經在玩家身上炸過了，就忽略
		if hit_cooldowns.has(body): return 
		
		# 上鎖 0.5 秒
		hit_cooldowns[body] = 0.5 
		
		# 觸發爆炸！(但不銷毀球，讓球繼續飛)
		trigger_explosion()

func trigger_explosion() -> void:
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = self.global_position
		# 把爆炸丟給世界地圖，這樣球飛走後，爆炸火花還會留在原地！
		get_tree().current_scene.call_deferred("add_child", explosion)

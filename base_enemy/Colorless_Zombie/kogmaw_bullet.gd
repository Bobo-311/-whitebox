extends Area2D
class_name DarkOrb 

# -------------------------------------------------------------------------
# ⚙️ 迴旋鏢飛行面板
# -------------------------------------------------------------------------
@export_group("迴旋鏢設定")
@export var flight_distance: float = 350.0   # 球最遠可以飛多遠
@export var flight_duration: float = 0.8     # 去程/回程各需要幾秒
@export var explosion_scene: PackedScene     # 裝填剛剛改好的小爆炸場景 (acid_explosion.tscn)

# 🌟【系統防呆】穿透冷卻鎖：記錄 [玩家物件 : 倒數計時]
# 防止球穿過身體時，每幀瘋狂產生爆炸秒殺玩家。
var hit_cooldowns: Dictionary = {} 

func _ready() -> void:
	# 🌟【關鍵修改：改用 area_entered 偵測 Hurtbox】
	area_entered.connect(_on_area_entered)

# -------------------------------------------------------------------------
# 🔄 物理更新 (負責管理冷卻時間)
# -------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var targets = hit_cooldowns.keys()
	for t in targets:
		hit_cooldowns[t] -= delta
		
		# 如果 0.5 秒過去了，把玩家從鎖定名單移除，球飛回來時就可以再次引爆！
		if hit_cooldowns[t] <= 0:
			hit_cooldowns.erase(t)

# -------------------------------------------------------------------------
# 🚀 飛行邏輯：迴旋鏢軌跡 (去程與回程)
# -------------------------------------------------------------------------
func fire(start_pos: Vector2, target_pos: Vector2) -> void:
	self.global_position = start_pos
	
	var dir = start_pos.direction_to(target_pos)
	var end_pos = start_pos + (dir * flight_distance) # 計算極限折返點
	
	var tween = create_tween()
	
	# 動畫 A【去程】：飛向極限距離 (EASE_OUT 讓球在最遠處有減速滯空感)
	tween.tween_property(self, "global_position", end_pos, flight_duration)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	# 動畫 B【回程】：飛回發射起點 (EASE_IN 讓球飛回來時越吸越快)
	tween.tween_property(self, "global_position", start_pos, flight_duration)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
	# 飛完兩趟後自我銷毀
	tween.chain().tween_callback(queue_free)

# -------------------------------------------------------------------------
# 💥 引信觸發：碰到玩家受傷區就生成爆炸！
# -------------------------------------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_hurtbox") or area.name == "Hurtbox":
		
		# 溯源找到玩家本體
		var player_body = area.get_parent()
		
		# 🌟【穿透冷卻鎖】：如果這顆球在 0.5 秒內已經炸過該玩家，就先忽略
		if hit_cooldowns.has(player_body): return 
		
		# 上鎖 0.5 秒
		hit_cooldowns[player_body] = 0.5 
		
		# 觸發爆炸！(球不會消失，會繼續飛)
		trigger_explosion()

func trigger_explosion() -> void:
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = self.global_position
		
		# 獨立加進主場景，確保球飛走後，爆炸火花還會留在原地
		get_tree().current_scene.call_deferred("add_child", explosion)

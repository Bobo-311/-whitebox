extends Area2D
class_name DarkOrb # 迴旋暗影球

# -------------------------------------------------------------------------
# ⚙️ 序列化設定面板 (企劃專用參數，可在 Inspector 自由調整)
# -------------------------------------------------------------------------
@export_group("迴旋鏢設定")
@export var flight_distance: float = 350.0   # 射程：球最遠可以飛多遠
@export var flight_duration: float = 0.8     # 速度：單趟飛行需要的時間
@export var explosion_scene: PackedScene     # 彈藥庫：裝填爆炸特效場景 (acid_explosion.tscn)

# -------------------------------------------------------------------------
# 🔒 狀態內部的暫存變數與防呆鎖
# -------------------------------------------------------------------------
var hit_cooldowns: Dictionary = {} # 防呆：穿透冷卻鎖，防止同一次接觸連續觸發爆炸
var movement_tween: Tween          # 動畫控制器：存成變數，才能在撞牆時隨時打斷它
var home_pos: Vector2              # 記憶體：老家座標 (發射點)
var is_returning: bool = false     # 狀態鎖：紀錄現在是不是已經在回程路上？

# -------------------------------------------------------------------------
# 🎬 生命週期初始化 (掛載雙雷達)
# -------------------------------------------------------------------------
func _ready() -> void:
	area_entered.connect(_on_area_entered) # 雷達 A：掃描玩家 Hurtbox (觸發傷害)
	body_entered.connect(_on_body_entered) # 雷達 B：掃描實體牆壁 (觸發碎裂)

# -------------------------------------------------------------------------
# 🔄 物理更新迴圈 (管理冷卻時間)
# -------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var targets = hit_cooldowns.keys()
	for t in targets:
		hit_cooldowns[t] -= delta
		# 時間到，解除該玩家的防呆鎖定，允許再次引爆
		if hit_cooldowns[t] <= 0:
			hit_cooldowns.erase(t)

# -------------------------------------------------------------------------
# 🚀 飛行邏輯 1：起飛與去程
# -------------------------------------------------------------------------
func fire(start_pos: Vector2, target_pos: Vector2) -> void:
	self.global_position = start_pos
	home_pos = start_pos  # 拍照記住老家的位置
	is_returning = false  # 初始化狀態為「去程」
	
	# 計算極限折返點
	var dir = start_pos.direction_to(target_pos)
	var end_pos = start_pos + (dir * flight_distance)
	
	_start_forward_flight(end_pos)

func _start_forward_flight(end_pos: Vector2) -> void:
	if movement_tween: movement_tween.kill() # 防呆：清除殘留的動畫
	movement_tween = create_tween()
	
	# 【去程動畫】：使用 EASE_OUT 產生在最遠處減速滯空的手感
	movement_tween.tween_property(self, "global_position", end_pos, flight_duration)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	# 正常情況下：在空中飛到極限距離都沒撞到牆，就會自動無縫接軌呼叫「回程」
	movement_tween.chain().tween_callback(_start_return_flight)

# -------------------------------------------------------------------------
# 🔙 飛行邏輯 2：正常回程 (幽靈狀態)
# -------------------------------------------------------------------------
func _start_return_flight() -> void:
	is_returning = true # 狀態改變：正在回家，開啟幽靈穿透模式
	
	if movement_tween: movement_tween.kill() 
	movement_tween = create_tween()
	
	# 【回程動畫】：使用 EASE_IN 產生飛回來時越吸越快的手感
	movement_tween.tween_property(self, "global_position", home_pos, flight_duration)\
		 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
	# 飛回老家後自我刪除
	movement_tween.chain().tween_callback(queue_free)

# -------------------------------------------------------------------------
# 💥 雷達 A：撞到玩家 (穿透並產生傷害)
# -------------------------------------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	# 確認撞到的是玩家受傷區
	if area.is_in_group("player_hurtbox") or area.name == "Hurtbox":
		var player_body = area.get_parent()
		
		# 穿透冷卻鎖：0.5 秒內已經炸過就不再炸
		if hit_cooldowns.has(player_body): return 
		hit_cooldowns[player_body] = 0.5 
		
		# 觸發爆炸，但球本身不會消失，會繼續飛！
		trigger_explosion()

# -------------------------------------------------------------------------
# 🧱 雷達 B：撞到牆壁 (碎裂消失，不再折返)
# -------------------------------------------------------------------------
func _on_body_entered(_body: Node2D) -> void:
	# 幽靈防呆：如果在正常回程途中穿過牆壁，就不理會地形，避免卡死
	if is_returning: return 
	
	# 撞牆瞬間：立刻在原地產生範圍爆炸特效
	trigger_explosion() 
	
	# 🌟 中斷機制：殺死目前的飛行路線，並把暗影球刪除 (沒收迴力鏢！)
	if movement_tween: movement_tween.kill()
	queue_free()

# -------------------------------------------------------------------------
# 🎇 共用方法：生成爆炸實體
# -------------------------------------------------------------------------
func trigger_explosion() -> void:
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = self.global_position
		# 獨立加進世界層，確保暗影球消失後，爆炸火花還能留在原地
		get_tree().current_scene.call_deferred("add_child", explosion)

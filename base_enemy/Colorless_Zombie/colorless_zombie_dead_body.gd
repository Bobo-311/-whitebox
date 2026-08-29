extends CharacterBody2D

@export_category("💣 怨靈炸彈設定")
@export var chase_speed: float = 250.0       
@export var explosion_damage: float = 40.0   
@export var trigger_distance: float = 40.0   

@onready var anim = $AnimatedSprite2D
@onready var hitbox = $Hitbox
@onready var timer = $Timer

var player_node: Node2D = null

# 🌟 狀態鎖機制
var is_exploding: bool = false       # 記錄是否已經點燃引信
var has_damaged_player: bool = false # 🌟【階段 4：單次傷害鎖】確保一場爆炸只扣一次血

func _ready():
	if DataManager and DataManager.player_node:
		player_node = DataManager.player_node
	
	# 設定倒數 5 秒強制自爆 (怕他一直追不到玩家卡死)
	timer.wait_time = 5.0
	timer.timeout.connect(_on_timer_timeout)
	timer.start()
	
	anim.animation_finished.connect(_on_animation_finished)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# 🌟【階段 1：無害的追跡者】
	# 一出生就先徹底封印 Hitbox，保證黑影碰到玩家絕對不會受傷
	_set_hitbox_active(false)
	
	anim.play("move") # 播放黑影飄浮

func _physics_process(_delta: float):
	
	# 🌟【階段 3：傷害綻放 (影格監視)】
	# 如果已經進入爆炸狀態，就讓程式當裁判，死盯著圖片播到哪一格
	if is_exploding:
		if anim.animation == "explode":
			var current_frame = anim.frame
			
			# 假設第 2~5 幀是紫色火光最大的時候 (你可以根據你的圖片自己改數字)
			# 只有這幾幀，才會解除封印，打開傷害判定框！
			if current_frame >= 2 and current_frame <= 5:
				_set_hitbox_active(true)
			else:
				# 🌟【階段 5：煙消雲散】火光變小了，就把傷害關掉
				_set_hitbox_active(false)
				
		return # 爆炸期間原地不動，不執行下面的追蹤邏輯
		
	# --- 以下是還沒爆炸時的追蹤邏輯 ---
	
	if not player_node:
		return
		
	# 瘋狂追蹤玩家
	var dir = global_position.direction_to(player_node.global_position)
	velocity = dir * chase_speed
	move_and_slide()
	
	# 🌟 距離判定：雷達探測到玩家進入引爆範圍
	if global_position.distance_to(player_node.global_position) <= trigger_distance:
		_trigger_explosion()

func _on_timer_timeout():
	_trigger_explosion()

# 🌟【階段 2：引信點燃】
func _trigger_explosion():
	if is_exploding: return
	is_exploding = true
	velocity = Vector2.ZERO # 瞬間煞車，停在原地
	anim.play("explode")    # 播放爆炸動畫 (此時 Hitbox 還是關的，交給 physics_process 去開)

# ==========================================
# 🛠️ 傷害判定與封印工具區
# ==========================================

# 封印/解除封印 Hitbox 的工具函數 (用 deferred 確保物理引擎不會報錯)
func _set_hitbox_active(is_active: bool):
	hitbox.set_deferred("monitoring", is_active)
	hitbox.set_deferred("monitorable", is_active)
	var shape = hitbox.get_node_or_null("CollisionShape2D")
	if shape: 
		shape.set_deferred("disabled", not is_active)

func _on_hitbox_body_entered(body):
	if body.is_in_group("player") or body.name == "player":
		_apply_explosion_damage(body, null)

func _on_hitbox_area_entered(area):
	var parent = area.get_parent()
	if parent and (parent.is_in_group("player") or parent.name == "player"):
		_apply_explosion_damage(parent, area)

# 結算爆炸傷害
func _apply_explosion_damage(target: Node2D, target_area: Area2D = null):
	# 🌟【階段 4：單次傷害鎖】最關鍵的防呆！
	# 如果這顆炸彈已經炸過玩家，直接 return 阻擋第二次傷害！
	if has_damaged_player: return 
	
	# 翻轉牌子：標記這顆炸彈已經造成過傷害了
	has_damaged_player = true
	
	var knockback_dir = global_position.direction_to(target.global_position)
	if target_area and target_area.has_method("take_damage"):
		target_area.take_damage(explosion_damage, global_position, knockback_dir, false, 3.0) 
	elif target.has_method("take_damage"):
		target.take_damage(explosion_damage, global_position, knockback_dir, false, 3.0)

# 動畫播完就刪除自己
func _on_animation_finished():
	if anim.animation == "explode":
		queue_free()

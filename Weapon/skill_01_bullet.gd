extends Area2D                                # 純粹的技能攻擊判定 (Hitbox)

@export var skill_01_attack_damage: float = 15.0 # 技能基礎傷害
@export var speed: float = 1000.0               # 子彈飛行速度

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 動畫節點

var direction: Vector2 = Vector2.ZERO         # 飛行方向
var travel_dir: Vector2 = Vector2.ZERO        # 擊退方向
var shooter: CharacterBody2D = null           # 記錄發射者 (Player)

var received_buff: float = 1.0                # 接收從槍管遞過來的過飽和倍率 (1.0 或 1.5)

func _ready() -> void:
	if animated_sprite_2d:
		animated_sprite_2d.play()             # 播放飛行動畫
		
	# 啟動 3 秒倒數計時，時間到自動銷毀清理記憶體
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

# ==========================================
# 🌟 狀況 A：撞到 Area2D (例如野豬的 Hurtbox)
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	
	# 🛡️【過濾友方】無視發射者自己、玩家肉身、以及友方白貓，絕不誤傷或自爆
	if parent == shooter or (parent and (parent.is_in_group("player") or parent.is_in_group("white_cat") or parent is WhiteCat)):
		return

	# 🎯 核心驗證：撞到的是不是 Hurtbox？
	if area is Hurtbox or area.name == "Hurtbox" or area.has_method("take_damage"): 
		var final_damage: float = skill_01_attack_damage * received_buff
		
		# 1. 呼叫 Hurtbox 的 take_damage 扣血 (傳入傷害、子彈位置、飛行方向)
		if area.has_method("take_damage"):
			area.take_damage(final_damage, global_position, direction) 
			
		# 2. 雙重保險：通知野豬/敵人本體切換受傷狀態與觸發硬直
		if parent and parent.has_method("handle_hurt"):
			parent.handle_hurt()
			
		print("🎯【Q技能】命中 Hurtbox！造成 ", final_damage, " 點傷害。")
		queue_free() # 命中敵方，子彈銷毀

# ==========================================
# 🌟 狀況 B：撞到 Node2D / Physical Body (例如牆壁或野豬本體)
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	# 🛡️ 1.【關鍵過濾】如果是玩家或白貓，直接無視，絕不自爆！
	if body == shooter or body.is_in_group("player") or body.is_in_group("white_cat") or body is WhiteCat:
		return

	# 🎯 2. 如果撞到的是野豬/敵人本體 (CharacterBody2D)
	if body is Enemy or body.is_in_group("enemies"):
		var final_damage: float = skill_01_attack_damage * received_buff
		
		if body.has_method("take_damage"):
			body.take_damage(final_damage, global_position, direction)
			
		if body.has_method("handle_hurt"):
			body.handle_hurt()
			
		print("🎯【Q技能】直接擊中敵人本體！造成 ", final_damage, " 點傷害。")
		queue_free()
		return

	# 🧱 3. 如果撞到的是牆壁 / 地形 (TileMap、TileMapLayer 或靜態障礙物)
	if body is TileMap or body is TileMapLayer or body is StaticBody2D:
		print("🧱 子彈擊中牆壁銷毀：", body.name)
		queue_free()
		return

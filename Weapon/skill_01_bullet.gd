extends Area2D                   # 繼承自 Area2D，因為它是純粹的攻擊判定(Hitbox)

@export var skill_01_attack_damage: float = 15.0 # 技能的基礎傷害
@export var speed: float = 1000  # 子彈飛行速度

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 動畫節點

var direction: Vector2 = Vector2.ZERO    # 飛行方向
var travel_dir: Vector2 = Vector2.ZERO   # 擊退方向
var shooter: Player = null               # 記錄發射者是誰

var received_buff: float = 1.0           # 🌟 準備用來接收從槍管遞過來的過飽和倍率

func _ready():                   # 出生時執行
	animated_sprite_2d.play()    # 播放飛行動畫
	await get_tree().create_timer(3.0).timeout # 啟動 3 秒倒數計時
	queue_free()                 # 時間到自動銷毀，清理記憶體

func _physics_process(delta):    # 每一幀物理位移
	position += direction * speed * delta

func _on_area_entered(area: Area2D) -> void: # 🌟 撞到東西時觸發
	# 核心驗證：撞到的是不是 Hurtbox？而且主人不是玩家自己？
	if area is Hurtbox and area.get_parent() != shooter: 
		
		# 🌟 計算最終傷害：基礎傷害 (15.0) * 隨身攜帶的倍率包裹 (1.0或1.5)
		var final_damage: float = skill_01_attack_damage * received_buff
		
		# 呼叫敵人的 Hurtbox 扣血
		area.take_damage(final_damage, global_position, direction) 
		print("Q 技能命中！造成了 ", final_damage, " 點傷害。") # 後台印出
		
		queue_free()             # 命中目標，子彈立即銷毀

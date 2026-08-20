extends Area2D # 繼承自 Area2D，子彈只需感應區不需實體碰撞推擠

@export var speed: float = 600.0          # 子彈飛行速度
@export var ranged_damage: float = 8.0    # 企劃設定：每發傷害 8.0

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D 
@onready var pop_sound: AudioStreamPlayer2D = get_node_or_null("PopSound") #之後在加

var direction: Vector2 = Vector2.ZERO     # 飛行方向
var travel_dir: Vector2 = Vector2.ZERO    # 擊退方向 (通常跟方向一致)

func _ready():                    
	if animated_sprite_2d:
		animated_sprite_2d.play("default") # 如果有動畫就播
		
	if pop_sound:
		pop_sound.play() # 🌟 開槍瞬間播放 Popcat 聲音！

	# 🌟 終極防線：如果子彈飛了 3 秒都沒撞到任何東西 (萬一飛出地圖外)，強制自我銷毀
	await get_tree().create_timer(3.0).timeout 
	queue_free()                 

func _physics_process(delta):    
	# 每一幀進行位移計算
	position += direction * speed * delta 

# ==========================================
# 🌟 訊號區 (去右邊節點面板連接！)
# ==========================================

# 1️⃣ 當子彈的 Area 雷達，掃到其他 Area 時 (專門用來打玩家的 Hurtbox)
func _on_area_entered(area: Area2D) -> void: 
	if area is Hurtbox:          
		# 呼叫目標的 Hurtbox 扣血
		# 參數：(傷害量, 來源位置, 擊退方向, 是否近戰, 擊退倍率)
		# 🌟 擊退倍率給 0.2，讓玩家不會被連射推飛
		area.take_damage(ranged_damage, global_position, direction, false, 0.2)
		
		# 掃到 Hurtbox 扣完血後，子彈立刻銷毀
		queue_free()                 

# 2️⃣ 當子彈撞到實體 Body 時 (專門用來撞牆壁/靜態障礙物)
func _on_body_entered(body: Node2D) -> void:
	# 因為你的 Mask 有勾選 1，所以撞到牆壁(Layer 1)會觸發這裡。
	# 只要撞到實體，子彈直接自我銷毀。
	queue_free()

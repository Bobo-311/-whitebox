extends Area2D                   # 繼承自 Area2D，子彈只需感應區不需實體碰撞推擠

@export var speed: float = 600.0          # 子彈飛行速度
@export var ranged_damage: float = 15.0   # 遠程波導彈的專屬傷害量

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 抓取子彈動畫播放器

var direction: Vector2 = Vector2.ZERO     # 用來儲存飛行方向
var travel_dir: Vector2 = Vector2.ZERO    # 用來儲存擊退方向

func _ready():                   # 遊戲一開始執行
	if animated_sprite_2d:
		animated_sprite_2d.play() # 播放子彈飛旋的動畫

	await get_tree().create_timer(3.0).timeout # 飛了 3 秒如果都沒撞到東西
	queue_free()                 # 自動銷毀，避免遊戲卡頓或記憶體爆炸

func _physics_process(delta):    # 每一幀執行位移
	position += direction * speed * delta # 子彈位移公式：目前位置 + (方向 * 速度 * 一幀時間)

func _on_area_entered(area: Area2D) -> void: # 🌟 雷達掃到東西時觸發
	print("🔥【子彈】撞到：", area, " 類型：", area.get_class()) # 後台除錯

	if area is Hurtbox:          # 核心驗證：如果撞到的是受傷區 (Hurtbox)
		print("✅ 子彈打到 Hurtbox")
		var parent = area.get_parent() # 找出這個 Hurtbox 的主人
		print("👉 父節點：", parent)

		# 呼叫目標的 Hurtbox 扣血，並傳入波導彈傷害、位置與擊退方向
		area.take_damage(ranged_damage, global_position, direction)

	queue_free()                 # 不管有沒有扣血，只要子彈雷達掃到東西，立刻自我銷毀


extends Area2D
class_name BossBullet

# ============================================================
# 淵獄蓮華 - Boss 彈目
#
# 負責：
# 1. 新版 8 幀彈目動畫
# 2. 子彈直線移動
# 3. 玩家命中傷害
# 4. 子彈壽命管理
# 5. Boss 彈幕群組管理
# ============================================================


# ============================================================
# 1. 子彈數值
# ============================================================

@export_group("彈目 - 戰鬥數值")

@export var speed: float = 500.0

@export var damage: float = 10.0

@export var lifespan: float = 6.0


# ============================================================
# 2. 彈目外觀
# ============================================================

@export_group("彈目 - 外觀設定")

# 新素材每格 64 × 64
# 實際光球約 22 × 22
# 放大 4 倍後約為 88 × 88

@export_range(0.1, 10.0, 0.1)
var visual_scale: float = 4.0

@export_range(0.1, 10.0, 0.1)
var animation_speed: float = 1.0

@export_range(1.0, 100.0, 1.0)
var collision_radius: float = 44.0


# ============================================================
# 3. 節點參照
# ============================================================

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# ============================================================
# 4. 內部狀態
# ============================================================

var _has_hit: bool = false


# ============================================================
# 5. 初始化
# ============================================================

func _ready() -> void:

	# 加入 Boss 彈幕群組
	# 供 Boss 轉階與死亡時統一清場

	add_to_group("boss_bullets")

	# 綁定命中事件

	if not area_entered.is_connected(_on_area_entered):

		area_entered.connect(_on_area_entered)

	# 設定動畫外觀

	_setup_visual()

	# 設定碰撞尺寸

	_setup_collision()

	# 啟動壽命計時

	var timer := get_tree().create_timer(
		maxf(lifespan, 0.1)
	)

	timer.timeout.connect(_on_lifespan_timeout)


# ============================================================
# 6. 動畫設定
# ============================================================

func _setup_visual() -> void:

	if anim_sprite.sprite_frames == null:

		push_error("BossBullet 缺少 SpriteFrames！")

		return

	if not anim_sprite.sprite_frames.has_animation(&"fly"):

		push_error("BossBullet 缺少 fly 動畫！")

		return

	# 新素材顯示尺寸

	anim_sprite.scale = Vector2.ONE * visual_scale

	# 動畫速度

	anim_sprite.speed_scale = animation_speed

	# 播放新彈目動畫

	anim_sprite.play(&"fly")


# ============================================================
# 7. 碰撞設定
# ============================================================

func _setup_collision() -> void:

	var circle := CircleShape2D.new()

	circle.radius = collision_radius

	collision_shape.shape = circle


# ============================================================
# 8. 子彈移動
#
# 沿著自身全域 X 軸前進
# 不受到生成器後續旋轉影響
# ============================================================

func _physics_process(delta: float) -> void:

	var direction: Vector2 = Vector2.RIGHT.rotated(
		global_rotation
	)

	global_position += direction * speed * delta


# ============================================================
# 9. 命中判定
# ============================================================

func _on_area_entered(area: Area2D) -> void:

	if _has_hit:
		return

	if not is_instance_valid(area):
		return

	# 確認目標具有受傷介面

	if not area.has_method("take_damage"):
		return

	_has_hit = true

	# 傳遞傷害

	area.take_damage(damage)

	# 命中後回收

	queue_free()


# ============================================================
# 10. 壽命結束
# ============================================================

func _on_lifespan_timeout() -> void:

	if not is_inside_tree():
		return

	if not is_queued_for_deletion():

		queue_free()

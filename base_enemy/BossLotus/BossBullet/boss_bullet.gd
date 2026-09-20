extends Area2D
class_name BossBullet

# ==========================================
# 📊 [子彈數值設定]
# ==========================================
@export var speed: float = 500.0       # 飛行推力 (px/s)
@export var damage: float = 10.0       # 命中基礎傷害
@export var lifespan: float = 6.0      # 實體存活極限，防止飛出邊界造成的記憶體洩漏 (Memory Leak)

@onready var anim_sprite = $AnimatedSprite2D

# ==========================================
# 🌱 [生命週期與初始化]
# ==========================================
func _ready() -> void:
	# 綁定命中偵測
	area_entered.connect(_on_area_entered)
	
	# 設定物件回收機制 (Object Cleanup)
	get_tree().create_timer(lifespan).timeout.connect(queue_free)
	
	# 啟用動態視覺特效
	if anim_sprite:
		anim_sprite.play("fly")

# ==========================================
# 🚀 [物理位移]
# ==========================================
func _process(delta: float) -> void:
	# 【正規推進邏輯】
	# 忽略絕對座標系，強制子彈沿著自身的局部 X 軸 (transform.x) 推進。
	# 這確保發射器只需決定「出生角度」，子彈就能正確朝該角度直線飛行。
	position += transform.x * speed * delta

# ==========================================
# 💥 [命中判定]
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	# 介面檢測 (Interface Check)：確認目標具備受擊方法
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free() # 命中後立即回收實體

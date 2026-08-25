extends BaseEnemy 
class_name BigShieldBrother 

@export_category("🛡️ 鐵門防禦設定")
@export var shield_direction: Vector2 = Vector2.DOWN 

@export_group("🎨 盾牌視覺設定")
@export var tex_down: Texture2D
@export var tex_up: Texture2D
@export var tex_left: Texture2D
@export var tex_right: Texture2D

@export var shield_image_scale: Vector2 = Vector2(1.0, 1.0)

# 🌟【新增】定義不同方向時，盾牌距離身體中心的「位移距離」(你可以根據像素大小微調這個數值)
@export var offset_distance: float = 25.0 

const BLOCK_TOLERANCE: float = 0.2

func _ready() -> void:
	super._ready()
	
	var shield_wall = get_node_or_null("ShieldPivot/ShieldWallBody")
	if shield_wall:
		add_collision_exception_with(shield_wall)

	_setup_shield_system()

# ==========================================
# 🌟 正規 4 方向解耦：物理轉向、換圖、加座標位移
# ==========================================
func _setup_shield_system() -> void:
	var pivot = get_node_or_null("ShieldPivot")
	var sprite = get_node_or_null("ShieldSprite")
	
	if not pivot or not sprite: return

	# 1. 物理轉向
	pivot.rotation = shield_direction.angle() - (PI / 2.0)
	
	# 2. 視覺設定與縮放
	sprite.scale = shield_image_scale
	
	# 3. 根據方向：換圖 ＋ 算座標位移 (把盾牌真正「戴」在對應的方位)
	var target_pos = Vector2.ZERO
	
	match shield_direction:
		Vector2.DOWN:
			if tex_down: sprite.texture = tex_down
			target_pos = Vector2(0, offset_distance)       # 戴在下方
		Vector2.UP:
			if tex_up: sprite.texture = tex_up
			target_pos = Vector2(0, -offset_distance)     # 戴在上方
		Vector2.LEFT:
			if tex_left: sprite.texture = tex_left
			target_pos = Vector2(-offset_distance, 0)     # 戴在左側
		Vector2.RIGHT:
			if tex_right: sprite.texture = tex_right
			target_pos = Vector2(offset_distance, 0)      # 戴在右側

	# 同步把「圖片」跟「物理轉軸(包含碰撞框)」一起移動到正確的方位！
	sprite.position = target_pos
	pivot.position = target_pos

# ==========================================
# 🛡️ 防禦與受傷邏輯 (保持不變)
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if is_dead: return 
	
	var attack_dir = dir
	if attack_dir == Vector2.ZERO and attacker_pos != Vector2.ZERO:
		attack_dir = (global_position - attacker_pos).normalized()
		
	if attack_dir.dot(shield_direction) > BLOCK_TOLERANCE:
		print("🛡️ 鐵門格擋！傷害無效！(正面絕對防禦)")
		return 
		
	print("🩸 玩家成功繞背！大盾兄弟受傷！")
	super.take_damage(amount, attacker_pos, dir, is_melee, extra_knockback)

func apply_stun(duration: float = 1.0) -> void:
	if is_dead: return 
	
	if player_node:
		var attack_dir = (global_position - player_node.global_position).normalized()
		
		if attack_dir.dot(shield_direction) > BLOCK_TOLERANCE:
			print("🛡️ 鐵門免疫了暈眩！")
			return 
			
	super.apply_stun(duration)

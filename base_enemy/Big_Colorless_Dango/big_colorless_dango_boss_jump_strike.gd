extends State

# ==========================================
# ⚙️ 技能三：王a燈 (牆角突圍大跳)
# ==========================================
@export_category("🔴 突圍大跳設定")
@export var explosion_scene: PackedScene   # 🌟 裝填：你剛剛做好的 jump_strike_explosion_hitbox.tscn
@export var telegraph_time: float = 1.5    # 蓄力發呆時間 (給玩家的反應時間)
@export var jump_time: float = 0.8         # 飛在空中的時間 (越短越有爆發力)
@export var jump_distance: float = 350.0   # 跨欄距離 (要飛多遠來脫離牆角)
@export var jump_height: float = 200.0     # 假 3D 視覺高度
@export var flash_color: Color = Color(1.0, 0.2, 0.2, 1.0) # 危險的紅光

var timer: float = 0.0
var has_jumped: bool = false
var original_collision_mask: int = 1

func enter():
	timer = telegraph_time
	has_jumped = false
	character.velocity = Vector2.ZERO # 煞車停死
	
	# 面向玩家，準備起跳
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
	character.play_animation("idle", character.last_facing_vec)
	
	# 🔴 階段一：視覺預警 (爆閃紅光)
	_play_red_flash()
	
func state_physics_update(delta: float):
	if has_jumped: return # 正在空中飛的時候，不要管計時器了，交給 Tween 處理
	
	timer -= delta
	if timer <= 0:
		_execute_jump() # 🔴 階段二：蓄力完畢，起跳！

# ==========================================
# 🚀 核心演出：跨欄大跳與落地核爆
# ==========================================
func _execute_jump() -> void:
	has_jumped = true
	
	# 🛡️【正規作法：關閉物理碰撞】
	# 記錄原本的層級，然後暫時關閉碰撞 (例如關閉 Layer 1 或 2，視你的設定而定)
	# 這裡假設你的 Boss 肉體 CollisionShape 叫做 "CollisionShape2D"
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", true)
	
	# 📐 計算落點 (Target Position)
	# 我們不依賴玩家目前位置，而是強制往玩家方向「飛躍 350 像素」，強行拉開距離
	var target_pos = character.global_position + (character.last_facing_vec * jump_distance)
	
	# 🚀 雙軌 Tween 動畫 (平面滑行 + 假 3D 高度)
	var move_tween = create_tween()
	move_tween.tween_property(character, "global_position", target_pos, jump_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	var sprite = character.animated_sprite_2d
	if sprite:
		var arc_tween = create_tween()
		# 往上飛 (Ease Out)
		arc_tween.tween_property(sprite, "position:y", -jump_height, jump_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# 往下砸 (Ease In 加速墜落)
		arc_tween.tween_property(sprite, "position:y", 0.0, jump_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# 💥 階段三：落地結算
	move_tween.finished.connect(_on_landing)

func _on_landing() -> void:
	# 1. 恢復物理碰撞
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", false)
	
	# 2. 💣 生成你剛做好的核爆武器
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		character.get_parent().add_child(explosion)
		# 爆炸生成在大胖呆腳下
		explosion.global_position = character.global_position 
	
	# 3. 完美銜接：落地後繼續風箏玩家
	state_machine.change_state("move")

func _play_red_flash() -> void:
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if not mat: return
	var tween = create_tween()
	# 快速閃紅光警告，直到起跳前慢慢褪去
	tween.tween_property(mat, "shader_parameter/state_color", flash_color, 0.1)
	tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, telegraph_time - 0.1)

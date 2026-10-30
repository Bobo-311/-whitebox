extends State # 繼承基礎狀態類別，納入狀態機統一管理

# ==========================================
# ⚙️ 技能三：王之大跳 (牆角突圍與範圍核爆)
# ==========================================
@export_category("🔴 突圍大跳設定")
@export var explosion_scene: PackedScene   # 🌟 裝填：核爆判定框場景 (jump_strike_explosion_hitbox.tscn)
@export var telegraph_time: float = 1.5    # 蓄力發呆時間 (起跳前的預警時間)
@export var jump_time: float = 0.8         # 飛在空中的時間 (配合美術動畫的飛行長度)
@export var jump_distance: float = 350.0   # 跨欄距離 (要飛多遠來脫離牆角)
@export var flash_color: Color = Color(1.0, 0.2, 0.2, 1.0) # 蓄力時本體的危險紅光

# 🔒 內部狀態計時與防呆記憶變數
var timer: float = 0.0
var has_jumped: bool = false
var warning_shadow: AnimatedSprite2D = null # 🌟 儲存「落點紅影預警」的實體，方便落地時刪除

# ==========================================
# 🎬 階段一：進入狀態 (蓄力停頓 ＋ 爆閃紅光)
# ==========================================
func enter():
	timer = telegraph_time
	has_jumped = false
	character.velocity = Vector2.ZERO # 瞬間煞車停死
	
	# 面向玩家，準備起跳
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
		
	# 播放美術畫好的「壓扁蓄力＋飛出畫面」 jump_up 動畫
	character.play_animation("jump_up", character.last_facing_vec)
	
	# 啟動起跳前視覺預警 (爆閃紅光)
	_play_red_flash()
	
func state_physics_update(delta: float):
	if has_jumped: return # 正在空中飛的時候，不要管計時器了，交給 Tween 處理
	
	timer -= delta
	if timer <= 0:
		_execute_jump() # 🔴 階段二：蓄力完畢，起跳！

# ==========================================
# 🚀 階段二：核心演出 (產生預警 ＋ 平面滑行)
# ==========================================
func _execute_jump() -> void:
	has_jumped = true
	
	# 🛡️【正規作法：關閉物理碰撞】
	# 暫時關閉碰撞，讓 Boss 飛行途中不會被場景物件卡住
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", true)
	
	# 📐 計算落點 (Target Position)
	# 強制往玩家方向「飛躍 350 像素」，強行拉開距離
	var target_pos = character.global_position + (character.last_facing_vec * jump_distance)
	
	# 🌟【全新機制：生成王形狀的地板紅影預警！】
	_create_warning_shadow(target_pos)
	
	# 🚀 物理本體貼著地板滑行到落點 (高度變化已由美術動畫自行呈現)
	var move_tween = create_tween()
	move_tween.tween_property(character, "global_position", target_pos, jump_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	# 🌟 在飛行時間過了 40% 時，切換為美術畫好的 fall_down 砸地動畫
	get_tree().create_timer(jump_time * 0.4).timeout.connect(func():
		if is_instance_valid(character) and not character.is_dead:
			character.play_animation("fall_down", character.last_facing_vec)
	)
	
	# 💥 階段三：落地結算
	move_tween.finished.connect(_on_landing)

# ==========================================
# 💥 階段三：落地結算 (清除預警 ＋ 引爆 ＋ 恢復移動)
# ==========================================
func _on_landing() -> void:
	# 1. 🌟【清除影子】：落地瞬間刪除地上的紅影預警
	if is_instance_valid(warning_shadow):
		warning_shadow.queue_free()
		
	# 2. 恢復物理碰撞
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", false)
	
	# 3. 💣 生成核爆武器
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		character.get_parent().add_child(explosion)
		explosion.global_position = character.global_position 
		
	# 強烈震屏 (加強落地打擊感)
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(25.0)
	
	# 4. 完美銜接：落地後繼續風箏/追擊玩家
	state_machine.change_state("move")

# ==========================================
# 🔴 視覺核心工具區：王形狀紅影預警與蓄力閃紅光
# ==========================================

# 🌟【全新升級：半透明微紅剪影 (不壓扁、直接出現)】
func _create_warning_shadow(pos: Vector2) -> void:
	var orig_anim = character.animated_sprite_2d
	if not orig_anim: return
	
	# 1. 複製一隻假的團子王作為地上的影子
	warning_shadow = AnimatedSprite2D.new()
	warning_shadow.sprite_frames = orig_anim.sprite_frames
	warning_shadow.animation = "idle" # 使用待機動作作為地上的紅影輪廓
	warning_shadow.frame = 0          # 鎖定第 0 格不播放
	
	# 🌟【正規作法 1：維持原比例】直接使用原本的比例，不再刻意壓扁！
	warning_shadow.global_scale = orig_anim.global_scale
	
	# 🌟【正規作法 2：柔和的半透明紅影】
	# self_modulate 設為純黑，把五官跟坑洞蓋掉變成剪影。
	# modulate 設為紅色，且 Alpha 只給 0.4 (半透明)，解決顏色太深像實體的問題！
	warning_shadow.modulate = Color(1.0, 0.0, 0.0, 0.4) 
	warning_shadow.self_modulate = Color(0.0, 0.0, 0.0, 1.0)
	
	warning_shadow.offset = orig_anim.offset
	warning_shadow.centered = orig_anim.centered
	warning_shadow.flip_h = orig_anim.flip_h
	warning_shadow.z_index = character.z_index - 1 # 確保壓在 Boss 腳下的地板層
	
	# 3. 🌟【起跳瞬間直接出現】：加進場景並放到落點位置，不再做淡入！
	character.get_parent().add_child(warning_shadow)
	warning_shadow.global_position = pos 
	
	# 4. 🌟【預警呼吸閃爍】：在 0.15 (微弱) 到 0.45 (明顯) 之間快速閃爍，提醒玩家落點
	var flash_tween = create_tween().set_loops(100)
	flash_tween.tween_property(warning_shadow, "modulate:a", 0.15, 0.1)
	flash_tween.tween_property(warning_shadow, "modulate:a", 0.45, 0.1)

# 起跳前的蓄力閃紅光 (維持原邏輯，加入防呆檢查)
func _play_red_flash() -> void:
	if not character.animated_sprite_2d: return
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if not mat: return
	
	var tween = create_tween()
	# 強制將 Shader 的 flash_modifier 關閉，避免受擊死白光吃掉紅光
	tween.tween_property(mat, "shader_parameter/flash_modifier", 0.0, 0.0)
	# 快速閃紅光警告，直到起跳前慢慢褪去
	tween.tween_property(mat, "shader_parameter/state_color", flash_color, 0.1)
	tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, telegraph_time - 0.1)

# ==========================================
# 🚪 離開狀態清理 (防呆機制)
# ==========================================
func exit():
	# 防呆：如果 Boss 在空中被打死或強制切換狀態，確保紅影會被清除，不會殘留在場上
	if is_instance_valid(warning_shadow):
		warning_shadow.queue_free()
		
	# 防呆：確保物理碰撞有被打開
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", false)

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

# ==========================================
# 🔒 內部狀態計時與防呆記憶變數
# ==========================================
var timer: float = 0.0                      # 起跳前的蓄力倒數計時器
var has_jumped: bool = false                # 標記是否已經起跳
var warning_shadow: AnimatedSprite2D = null # 🌟 儲存「落點紅影預警」的實體，方便落地時刪除
var flight_timer: float = 0.0               # 🌟 計算飛行時間，用來控制預警圈「延遲出現」！
var target_landing_pos: Vector2 = Vector2.ZERO # 記住預定落點的世界座標

# ==========================================
# 🎬 階段一：進入狀態 (蓄力停頓 ＋ Shader爆閃紅光)
# ==========================================
func enter():
	timer = telegraph_time
	has_jumped = false
	flight_timer = 0.0                # 重置飛行碼錶
	character.velocity = Vector2.ZERO # 瞬間煞車停死
	
	# 轉向玩家
	if character.player_node:
		character.last_facing_vec = character.global_position.direction_to(character.player_node.global_position)
		
	# 播放美術畫好的 jump_up (壓扁蓄力＋飛出畫面) 動畫
	character.play_animation("jump_up", character.last_facing_vec)
	
	# 啟動起跳前視覺預警 (透過 Shader 控制)
	_play_red_flash()
	
func state_physics_update(delta: float):
	# 🌟【階段 2.5：飛行途中延遲出現預警】
	# 【類似遊戲思考】：為了給予玩家極限躲避的壓迫感，預警圈不要一開始就出現。
	# 等 Boss 飛行時間過了 40% (準備開始下墜前一刻)，才強制在地板秀出淡淡的紅影！
	if has_jumped:
		flight_timer += delta
		# 當飛行時間達到 40% 且影子尚未生成時，呼叫產生紅影
		if flight_timer >= (jump_time * 0.4) and warning_shadow == null:
			_create_warning_shadow(target_landing_pos)
		return # 空中飛行交給 Tween 控制，不執行後續程式碼
	
	# 階段 1：蓄力倒數，時間到就起跳
	timer -= delta
	if timer <= 0:
		_execute_jump() 

# ==========================================
# 🚀 階段二：核心演出 (平面滑行計算落點)
# ==========================================
func _execute_jump() -> void:
	has_jumped = true
	
	# 暫時關閉物理碰撞，讓 Boss 飛行途中不會被場景其他怪物卡住
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", true)
	
	# 計算強制落點：朝向玩家方向強推 350 像素
	target_landing_pos = character.global_position + (character.last_facing_vec * jump_distance)
	
	# 物理本體貼著地板滑行到落點 (Y軸高度變化已由美術畫在動畫裡)
	var move_tween = create_tween()
	move_tween.tween_property(character, "global_position", target_landing_pos, jump_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	# 在飛行時間過了 40% 時，切換為 fall_down 砸地動畫
	get_tree().create_timer(jump_time * 0.4).timeout.connect(func():
		if is_instance_valid(character) and not character.is_dead:
			character.play_animation("fall_down", character.last_facing_vec)
	)
	
	# 抵達落點時觸發落地結算
	move_tween.finished.connect(_on_landing)

# ==========================================
# 💥 階段三：落地結算 (清除預警 ＋ 引爆 ＋ 恢復移動)
# ==========================================
func _on_landing() -> void:
	# 1. 🌟【清除影子】：落地瞬間立即刪除地上的紅影預警！
	if is_instance_valid(warning_shadow):
		warning_shadow.queue_free()
		warning_shadow = null
		
	# 2. 恢復物理碰撞判定
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", false)
	
	# 3. 生成核爆判定框
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		character.get_parent().add_child(explosion)
		explosion.global_position = character.global_position 
		
	# 觸發相機強烈震屏加強打擊感
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(25.0)
	
	# 4. 完美銜接：落地後繼續風箏/追擊玩家
	state_machine.change_state("move")

# ==========================================
# 🔴 視覺核心工具區：王形狀紅影預警與蓄力閃紅光
# ==========================================

# 🌟【全新升級：半透明淡紅剪影 (延遲出現版)】
func _create_warning_shadow(pos: Vector2) -> void:
	var orig_anim = character.animated_sprite_2d
	if not orig_anim: return
	
	# 1. 建立假的精靈圖作為地板預警
	warning_shadow = AnimatedSprite2D.new()
	warning_shadow.sprite_frames = orig_anim.sprite_frames
	warning_shadow.animation = "idle" # 使用待機動作作為形狀輪廓
	warning_shadow.frame = 0          # 鎖定不動
	
	# 🌟【完美同步縮放】：直接讀取當前比例，確保預警圈會跟著 Boss 鎖血變小！
	warning_shadow.global_scale = orig_anim.global_scale
	
	# 🌟【正規作法：極淡的半透明紅影】
	# self_modulate 設為純黑，把五官跟坑洞蓋掉變成黑色剪影底圖。
	# modulate 設為紅色，且 Alpha 調到 0.25 (非常淡)，看起來就像一灘危險的血色投影！
	warning_shadow.modulate = Color(1.0, 0.2, 0.2, 0.25) 
	warning_shadow.self_modulate = Color(0.0, 0.0, 0.0, 1.0)
	
	warning_shadow.offset = orig_anim.offset
	warning_shadow.centered = orig_anim.centered
	warning_shadow.flip_h = orig_anim.flip_h
	warning_shadow.z_index = character.z_index - 1 # 圖層 -1，壓在 Boss 腳下
	
	character.get_parent().add_child(warning_shadow)
	warning_shadow.global_position = pos 
	
	# 🌟【急促警告】：因為已經延遲出現了，我們讓影子直接以高頻急閃出現，警告玩家時間不多了！
	# (注意：給予 100 次的循環限制，避免引發無窮迴圈警告)
	var flash_tween = create_tween().set_loops(100)
	flash_tween.tween_property(warning_shadow, "modulate:a", 0.1, 0.05)
	flash_tween.tween_property(warning_shadow, "modulate:a", 0.4, 0.05)

# 起跳前透過 Shader 修改 state_color 達到爆閃紅光
func _play_red_flash() -> void:
	if not character.animated_sprite_2d: return
	
	# 為了不影響其他怪物，如果沒有獨立拷貝過材質，就在這裡拷貝一份
	if character.animated_sprite_2d.material != null and not character.animated_sprite_2d.material.resource_local_to_scene:
		character.animated_sprite_2d.material = character.animated_sprite_2d.material.duplicate()
		
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if not mat: return
	
	var tween = create_tween()
	# 強制關閉白光干擾
	tween.tween_property(mat, "shader_parameter/flash_modifier", 0.0, 0.0)
	# 快速閃紅光警告，直到起跳前慢慢褪去
	tween.tween_property(mat, "shader_parameter/state_color", flash_color, 0.1)
	tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, telegraph_time - 0.1)

# ==========================================
# 🚪 離開狀態清理 (防呆機制)
# ==========================================
func exit():
	# 防呆：如果 Boss 在空中被打死或因為鎖血強制切換狀態，確保紅影被清除不殘留
	if is_instance_valid(warning_shadow):
		warning_shadow.queue_free()
		warning_shadow = null
		
	# 防呆：確保物理碰撞有被重新打開
	var body_col = character.get_node_or_null("CollisionShape2D")
	if body_col: body_col.set_deferred("disabled", false)

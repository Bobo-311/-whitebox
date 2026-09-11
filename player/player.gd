extends BaseCharacter # 【正規作法】：繼承基礎角色，共用生命週期與受擊框架
class_name Player # 宣告類別，方便其他節點透過 `is Player` 進行型別檢查

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的基準速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度 (Juice：創造極大反差)
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (0.2秒是動作遊戲的黃金手感)
@export var basic_attack_damage: float = 15.0 # 基礎揮刀攻擊力

@export var invincibility_duration: float = 0.6  # 受傷後的無敵時間 (Iframes)，避免被連續硬直連死
var is_invincible: bool = false                  # 無敵狀態的總開關

var original_sprite_scale: Vector2 = Vector2.ONE # 記憶精靈圖原始比例，防止動畫縮放引發形變 Bug
@export var base_max_hp: int = 100               # 玩家無裝備時的裸體最大血量

# ==========================================
# 🌟【全新：翻滾冷卻系統 (Dash Cooldown)】
# ==========================================
# 【類似遊戲思考】：拔除體力條後，改用獨立 CD 控制節奏，鼓勵玩家在 CD 空檔積極輸出。
@export_group("翻滾冷卻系統")
@export var dash_cd_time: float = 2.0       # [企劃設定] 翻滾冷卻時間 (2秒)
var dash_cd_timer: float = 0.0              # [系統變數] 負責在背景倒數的計時器
var is_dash_ready: bool = true              # [狀態開關] 紀錄目前翻滾是否準備就緒

# 【正規作法】：預載特效，確保生成的瞬間不會造成硬碟讀取卡頓 (Stutter)
const DASH_READY_PARTICLES = preload("res://DashEffect/dash_ready_particles.tscn")

# ==========================================
# [🌟 墨水系統] (玩家的遠程武器能量)
# ==========================================
var shoot_slow_timer: float = 0.0          # 發射武器時的減速懲罰計時器，模擬開槍後座力帶來的硬直

var input_direction: Vector2 = Vector2.ZERO # 記錄 WASD 輸入向量
var facing_direction: String = "down"       # 記錄最後面朝方向，用於決定播放哪個方向的動畫與判定框
var is_dashing: bool = false                # 動作鎖：記錄是否正在翻滾中

var is_reading_book: bool = false           # 狀態鎖：是否正在閱讀素描本 (暫停行動)
var opened_from_savepoint: bool = false     # 狀態鎖：素描本是否由存檔點開啟
var is_shopping: bool = false               # 狀態鎖：是否正在購物 (暫停行動)

enum WeaponMode { BLUE, RED, YELLOW }       # 列舉三種武器模式，增加程式碼可讀性
var current_weapon: WeaponMode = WeaponMode.BLUE # 當前裝備的武器

var max_ink: float = 60.0                   # 墨水 (彈藥) 上限
var current_ink: float = 60.0               # 當前剩餘墨水

# ==========================================
# 節點抓取 (@onready 確保在 _ready 時節點已載入完畢)
# ==========================================
@onready var state_machine: StateMachine = $StateMachine               # 動作大腦
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D  # 動畫播放器
@onready var player_hud: CanvasLayer = $PlayerHUD                      # UI 介面
@onready var magic_brush: Node2D = $MagicBrush                         # 武器發射器
@onready var knockback_component: KnockbackComponent = get_node_or_null("KnockbackComponent") # 獨立擊退組件
@onready var notebook_ui = $MenuLayer/NotebookUI                       # 素描本 UI

# 取得當下武器每次發射需消耗的墨水量
func get_weapon_cost() -> float:
	match current_weapon:
		WeaponMode.BLUE: return 10.0
		WeaponMode.RED: return 15.0  
		WeaponMode.YELLOW: return 20.0
	return 10.0

# ==========================================
# 生命週期：初始化
# ==========================================
func _ready(): 
	super._ready() # 執行父類別 (BaseCharacter) 的初始化邏輯
	print("以防大家沒看到 菜心楊是傻逼")
	
	if animated_sprite_2d:
		original_sprite_scale = animated_sprite_2d.scale # 鎖定原始比例防跑版
	
	DataManager.player_node = self # 將自己的實體註冊到全域大腦，讓所有系統都能輕易找到玩家
	
	# 綁定裝備變更訊號，只要換裝備就立刻重算血量
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	recalculate_stats() # 開局先算一次血量
	
	# 存檔點重生位置校正
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position
		
	# 讀取存檔血量
	if DataManager and DataManager.saved_hp > 0: 
		current_hp = min(DataManager.saved_hp, max_hp) 
		
	# 初始化 UI 介面同步
	if player_hud: 
		player_hud.update_hp(current_hp, max_hp) 
		if player_hud.has_method("set_ink_mode"):
			player_hud.set_ink_mode(current_weapon)
			player_hud.update_ink(current_ink, max_ink)
		
	update_hp_bar()
		
	# 撿屍體系統：如果死在同一張圖，把靈魂生出來
	if DataManager and DataManager.has_soul_on_ground: 
		if DataManager.soul_map_path == get_tree().current_scene.scene_file_path:
			var soul_scene = load("res://soul/Soul.tscn") 
			if soul_scene: 
				var soul = soul_scene.instantiate() 
				soul.global_position = DataManager.soul_spawn_pos 
				soul.lost_gold = DataManager.soul_stored_gold     
				soul.scale = Vector2(2.0, 2.0) 
				get_tree().current_scene.call_deferred("add_child", soul) 
	
	# 啟動狀態機大腦
	if state_machine:
		state_machine.init(self)
	
	# 執行防呆動畫檢查
	_run_bug_radar(get_tree().root)

# ==========================================
# 玩家硬體輸入攔截 (UI 操控層級)
# ==========================================
func _input(event):
	if is_shopping: return # 購物時鎖死操作

	var pressed_cancel = event.is_action_pressed("TAB") or event.is_action_pressed("ESC")

	# 處理開關素描本的邏輯 (含狀態機暫停)
	if is_reading_book and pressed_cancel:
		if opened_from_savepoint:
			if notebook_ui:
				notebook_ui.hide()
				notebook_ui.is_open = false
			opened_from_savepoint = false 
			var save_menus = get_tree().get_nodes_in_group("save_menu")
			if save_menus.size() > 0: save_menus[0].show()
		else:
			is_reading_book = false
			state_machine.process_mode = Node.PROCESS_MODE_INHERIT # 恢復大腦運作
			if notebook_ui: notebook_ui.toggle_notebook(false)
		return 
	
	if not is_reading_book and event.is_action_pressed("TAB"):
		is_reading_book = true
		velocity = Vector2.ZERO # 強制煞車
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED # 凍結大腦
		if notebook_ui: notebook_ui.toggle_notebook(false)

	# 開發者外掛
	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)

# ==========================================
# 數值重算 (裝備系統對接)
# ==========================================
func recalculate_stats():
	var bonus_hp = 0 
	if DataManager.has_sticker("001"): 
		bonus_hp += DataManager.STICKER_DB["001"].value 
		
	max_hp = base_max_hp + bonus_hp
	if current_hp > max_hp: current_hp = max_hp
		
	update_hp_bar() 
	print("【系統】玩家能力已更新，目前最大血量：", max_hp)

# ==========================================
# 核心物理與邏輯迴圈 (每幀執行)
# ==========================================
func _physics_process(delta: float) -> void: 
	if not is_dead: 
		
		# 【狀態鎖定】：如果在看書或買東西，強制煞車並跳出迴圈
		if is_reading_book or is_shopping:
			velocity = Vector2.ZERO
			if state_machine.process_mode != Node.PROCESS_MODE_DISABLED:
				state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
			move_and_slide()        
			return                  
		else:
			# 解除狀態鎖定，恢復大腦運作
			if state_machine.process_mode == Node.PROCESS_MODE_DISABLED:
				state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		
		# 獲取玩家移動向量
		input_direction = Input.get_vector("left", "right", "up", "down") 

		# 狙擊槍蓄力罰站系統：蓄力時強制清空輸入向量，讓玩家定格
		if magic_brush and magic_brush.is_charging:
			input_direction = Vector2.ZERO 
			var is_in_knockback: bool = knockback_component and knockback_component.knockback_force.length() > 0.0
			# 如果沒有在翻滾，也沒有被打飛，才強制煞車
			if not is_dashing and not is_in_knockback:
				velocity = Vector2.ZERO    

		# 快捷鍵與武器切換監聽
		if Input.is_action_just_pressed("slot_left"): DataManager.rotate_quick_slot(-1)
		if Input.is_action_just_pressed("slot_right"): DataManager.rotate_quick_slot(1)
		if Input.is_action_just_pressed("switch_weapon"): switch_next_weapon()

		# ==========================================
		# 發射與蓄力邏輯 (墨水消耗系統)
		# ==========================================
		if state_machine.current_state.name != "PlayerHeal": 
			var cost = get_weapon_cost()
			
			# 按下射擊
			if Input.is_action_just_pressed("skill_01"): 
				if current_ink >= cost:
					var current_buff: float = 1.0
					if DataManager.has_sticker("004"): current_buff *= DataManager.STICKER_DB["004"].value
					
					# 紅槍：開始蓄力
					if current_weapon == WeaponMode.RED:
						var max_stages = floor(current_ink / 15.0)
						magic_brush.press_shoot(current_buff, max_stages)
					# 藍黃槍：直接發射並扣墨水，套用減速硬直
					else:
						magic_brush.press_shoot(current_buff)
						current_ink -= cost
						if current_weapon == WeaponMode.YELLOW: shoot_slow_timer = 0.4 
						else: shoot_slow_timer = 0.3 
						if player_hud and player_hud.has_method("update_ink"): player_hud.update_ink(current_ink, max_ink)
				else: 
					print("⚠️ 墨水用盡！請使用近戰揮刀補充墨水！") 
			
			# 按住射擊 (紅槍蓄力 UI 預覽)
			if Input.is_action_pressed("skill_01") and current_weapon == WeaponMode.RED:
				if magic_brush and magic_brush.is_charging:
					var stage = magic_brush.get_current_stage()
					var preview_val = current_ink - (stage * 15.0)
					if player_hud and player_hud.has_method("preview_ink"): player_hud.preview_ink(preview_val)
			
			# 放開射擊 (紅槍發射結算)
			if Input.is_action_just_released("skill_01"):
				if current_weapon == WeaponMode.RED and magic_brush and magic_brush.is_charging:
					var stage = magic_brush.get_current_stage()
					if stage > 0:
						var current_buff = 1.0
						if DataManager.has_sticker("004"): current_buff *= DataManager.STICKER_DB["004"].value
						magic_brush.release_shoot(current_buff)
						current_ink -= (stage * 15.0)
						shoot_slow_timer = 0.6 
						if player_hud and player_hud.has_method("confirm_ink_drop"): player_hud.confirm_ink_drop(current_ink)
						elif player_hud and player_hud.has_method("update_ink"): player_hud.update_ink(current_ink, max_ink)
					else:
						# 蓄力不足取消發射
						magic_brush.cancel_shoot()
						if player_hud and player_hud.has_method("preview_ink"): player_hud.preview_ink(current_ink)
		
		# 使用道具快捷鍵
		if Input.is_action_just_pressed("USESKILL"): 
			if state_machine.current_state.name != "PlayerHeal": DataManager.use_current_item() 

		# ==========================================
		# 🌟【全新：翻滾 CD 倒數機制】(完全取代舊版 SP 體力條)
		# ==========================================
		if not is_dash_ready:
			dash_cd_timer -= delta # 每一物理幀扣除經過的時間
			if dash_cd_timer <= 0:
				is_dash_ready = true # CD 轉好了！開放使用！
				_play_dash_ready_effect() # 呼叫特效提示玩家

	# 結算減速懲罰與最終位移 (套用滑動)
	var is_in_knockback: bool = knockback_component and knockback_component.knockback_force.length() > 0.0
	if shoot_slow_timer > 0:
		shoot_slow_timer -= delta
		# 若玩家沒在翻滾也沒被打飛，射擊後座力減速才會生效
		if not is_dashing and not is_in_knockback: velocity *= 0.05
		
	move_and_slide()

# ==========================================
# 🌟 技能轉好提示特效 (Juice)
# ==========================================
# 【類似遊戲思考】：用「餘光」與強烈視覺回饋代替看 UI，維持戰鬥心流。
func _play_dash_ready_effect() -> void:
	# 視覺 1：身體瞬間閃耀獨特光芒 (Tween 平滑變色)
	if animated_sprite_2d:
		var tween = create_tween()
		animated_sprite_2d.modulate = Color(0.5, 1.0, 1.5, 1.0) 
		tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.3)
	
	# 視覺 2：在腳下爆開提示粒子
	if DASH_READY_PARTICLES:
		var p = DASH_READY_PARTICLES.instantiate()
		p.global_position = global_position
		get_parent().add_child(p)

# ==========================================
# 武器與墨水介面控制
# ==========================================
func switch_next_weapon() -> void:
	current_weapon = (current_weapon + 1) % 3 as WeaponMode
	if magic_brush and magic_brush.has_method("set_mode"): magic_brush.set_mode(current_weapon)
	if player_hud and player_hud.has_method("set_ink_mode"): player_hud.set_ink_mode(current_weapon)

func add_ink(amount: float = 10.0) -> void:
	if current_ink < max_ink:
		current_ink = min(current_ink + amount, max_ink)
		if player_hud and player_hud.has_method("update_ink"): player_hud.update_ink(current_ink, max_ink)

func refill_full_ink() -> void:
	current_ink = max_ink
	if player_hud and player_hud.has_method("update_ink"): player_hud.update_ink(current_ink, max_ink)

# 近戰回充橋接函數 (將原本回充 Ammo 轉換為回充墨水)
func add_ammo(amount: int = 1) -> void: add_ink(amount * 10.0)
func restore_ammo(amount: int = 1) -> void: add_ink(amount * 10.0)
func refill_full_ammo() -> void: refill_full_ink()

# ==========================================
# 戰鬥與受傷邏輯
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if is_dead or is_invincible: return # 死亡或無敵期間不收受傷害
	
	current_hp = max(current_hp - amount, 0)
	update_hp_bar()
	
	# 觸發 Hitstop (打擊頓幀) 增加重量感
	if DataManager and DataManager.has_method("trigger_hitstop"): DataManager.trigger_hitstop(0.07, 0.05)
	
	# 處理擊退
	var knockback_dir = dir if dir != Vector2.ZERO else (global_position - attacker_pos).normalized()
	if knockback_component and knockback_dir != Vector2.ZERO: 
		knockback_component.apply_knockback(knockback_dir, -1.0, extra_knockback)
		
	# 震屏反饋
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"): camera.apply_shake(14.0)
		
	play_hurt_effects()
	start_invincibility()
	
	if current_hp <= 0: die()
	else: handle_hurt()

# 受傷視覺果汁感 (變紅與壓扁變形)
func play_hurt_effects() -> void:
	if animated_sprite_2d:
		var tween = create_tween().set_parallel(true)
		animated_sprite_2d.modulate = Color(3.0, 0.4, 0.4)
		tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.15)
		
		# 假 3D 壓扁回彈 (Back Ease)
		animated_sprite_2d.scale = Vector2(original_sprite_scale.x * 1.2, original_sprite_scale.y * 0.8)
		tween.tween_property(animated_sprite_2d, "scale", original_sprite_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# 開啟無敵保護與半透明閃爍
func start_invincibility() -> void:
	is_invincible = true
	var tween = create_tween().set_loops(int(invincibility_duration / 0.1))
	tween.tween_property(animated_sprite_2d, "modulate:a", 0.3, 0.05)
	tween.tween_property(animated_sprite_2d, "modulate:a", 1.0, 0.05)
	
	await get_tree().create_timer(invincibility_duration).timeout
	is_invincible = false
	animated_sprite_2d.modulate.a = 1.0

# 護符系統對接：算取最終攻擊力 (低血增傷判定)
func get_current_basic_attack_damage() -> float:
	var final_base_damage: float = basic_attack_damage
	if DataManager.has_sticker("008"):
		var threshold: float = DataManager.STICKER_DB["008"].threshold 
		if float(current_hp) / float(max_hp) <= threshold:
			final_base_damage *= DataManager.STICKER_DB["008"].value 
	return final_base_damage

# 護符系統對接：擊殺回血
func on_enemy_killed():
	if DataManager.has_sticker("006"):
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		var heal_amount: int = int(max_hp * heal_percent)
		current_hp = min(current_hp + heal_amount, max_hp)
		update_hp_bar()

# 受擊後的大腦狀態切換
func handle_hurt(): 
	# 強制中斷看書或購物
	if is_reading_book:
		is_reading_book = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		if notebook_ui: notebook_ui.close_notebook()
	
	if is_shopping:
		is_shopping = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		for node in get_tree().root.get_children():
			if node.name == "ShopUI": node.queue_free()
	
	# 如果正在暈眩或喘氣，不切換受擊動畫
	var state_name = state_machine.current_state.name.to_lower() 
	if "stun" in state_name or "pant" in state_name: return 
	
	state_machine.change_state("PlayerHurt") 

func heal(amount: int) -> void:
	var final_amount = amount 
	# 護符對接：道具回復量提升
	if DataManager.has_sticker("016"):
		var bonus = DataManager.STICKER_DB["016"].value
		final_amount += bonus
		
	if current_hp < max_hp:
		current_hp = min(current_hp + final_amount, max_hp)
		update_hp_bar() 

func die(): 
	if is_dead: return 
	is_dead = true 
	if state_machine: state_machine.change_state("PlayerDie") 

func update_hp_bar(): 
	if player_hud: player_hud.update_hp(current_hp, max_hp) 
	
	# 同步 Shader 的彩度，血越少畫面越黑白
	var hp_ratio: float = max(float(current_hp) / float(max_hp), 0.0) 
	if animated_sprite_2d.material: 
		var tween = get_tree().create_tween() 
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) 

# 動畫播放封裝系統 (依據朝向加上後綴)
func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO):
	var anim = get_node_or_null("AnimatedSprite2D")
	if anim == null: return

	# 若沒在翻滾，且有在移動，才更新面朝變數
	if not is_dashing and input_direction != Vector2.ZERO:
		if abs(input_direction.x) > abs(input_direction.y):
			facing_direction = "right" if input_direction.x > 0 else "left"
		else:
			facing_direction = "down" if input_direction.y > 0 else "up"

	var animation_name = prefix + "_" + facing_direction
	if not anim.sprite_frames.has_animation(animation_name): return
	anim.play(animation_name)

# 遞迴檢查樹狀結構，揪出空動畫節點
func _run_bug_radar(node: Node):
	if node is AnimatedSprite2D:
		if node.animation == "":
			print("\n====================================")
			print("🚨🚨🚨 抓到真兇了！空動畫節點在這裡 🚨🚨🚨")
			print("👉 節點絕對路徑：", node.get_path())
			print("👉 來源場景檔案：", node.owner.scene_file_path if node.owner else "無")
			print("====================================\n")
			
	for child in node.get_children():
		_run_bug_radar(child)

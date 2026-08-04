extends BaseCharacter # 繼承自基礎角色類別，獲得通用功能 (如死亡、受傷框架)
class_name Player # 宣告這個腳本代表「玩家 (Player)」

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (秒)
@export var basic_attack_damage: float = 15.0 # 玩家的基礎揮刀攻擊力

# 受傷微擊退與無敵時間 (Iframes) 參數
@export var knockback_strength: float = 220.0   # 擊退力道
@export var invincibility_duration: float = 0.6  # 無敵時間 (0.6 秒)
var is_invincible: bool = false                  # 無敵狀態開關

# 🌟【防縮水修復】自動記憶 Inspector 設定的原始精靈圖大小
var original_sprite_scale: Vector2 = Vector2.ONE

# 記住玩家一絲不掛時的「基礎最大血量」
var base_max_hp: int = 100

# ==========================================
# [🌟 墨水彈藥系統] 與 體力 (SP) 系統
# ==========================================
@export var max_ammo: int = 3               # 墨水彈藥上限 (預設 3 發)
var current_ammo: int = 3                  # 當前剩餘墨水彈藥

@export var max_sp: float = 100.0          # 體力上限 (揮刀、翻滾消耗用)
var current_sp: float = 50                  # 開局預設體力
var is_overheated: bool = false            # 狀態開關：記錄玩家現在是否處於「過熱力竭」狀態
var sp_regen_delay: float = 0.5            # 體力恢復延遲：消耗後需等待 0.5 秒才能開始回體
var sp_delay_timer: float = 0.0            # 隱形計時器：負責倒數回體的等待時間

# 🌟 射擊時的減速計時器
var shoot_slow_timer: float = 0.0          # 發射時會倒數，期間移動變慢

# ==========================================
# 狀態紀錄與節點抓取
# ==========================================
var input_direction: Vector2 = Vector2.ZERO # 記錄玩家按下的 WASD 方向向量
var facing_direction: String = "down"       # 記錄玩家最後面朝的方向，預設朝下
var is_dashing: bool = false                # 記錄玩家現在是否正在衝刺中

# 素描本系統狀態變數
var is_reading_book: bool = false           # 記錄玩家是否正在看筆記本
var opened_from_savepoint: bool = false     # 記錄筆記本是不是從存檔點捷徑打開的

var is_shopping: bool = false # 記錄玩家現在是不是正在買東西(終止行動)

@onready var state_machine: StateMachine = $StateMachine               # 控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D  # 負責播放動畫的精靈圖
@onready var player_hud: CanvasLayer = $PlayerHUD                      # 畫面左上角的狀態條介面 (UI)
@onready var skill_01: Node2D = $Skill_01                              # 掛在玩家身上的技能發射器 (槍管)

# 抓取素描本 UI 節點
@onready var notebook_ui = $MenuLayer/NotebookUI
	
# ==========================================
# 遊戲初始化 (_ready)
# ==========================================
func _ready(): 
	super._ready() # 呼叫父類別準備函數，確保基本屬性初始化 (如血量補滿)
	
	# 🌟【防縮水修復】自動記錄編輯器中設定的精靈圖縮放比例
	if animated_sprite_2d:
		original_sprite_scale = animated_sprite_2d.scale
	
	DataManager.player_node = self # 玩家一出生，庫存註冊到全域大腦裡
	
	# 訂閱裝備廣播頻道，確保裝備變動時重算能力
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	# 開局防呆：手動算一次裝備屬性
	recalculate_stats()
	
	# --- 讀取存檔資料 ---
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position # 將位置強制移動到存檔點
		
	if DataManager and DataManager.saved_hp > 0: 
		current_hp = min(DataManager.saved_hp, max_hp) 
		current_sp = DataManager.saved_sp 
	else: 
		current_sp = 50     # 第一次玩給予預設體力
		
	# --- 初始化 UI 介面 ---
	if player_hud: 
		player_hud.update_hp(current_hp, max_hp)             # 更新紅血條
		player_hud.update_sp(current_sp, max_sp)             # 更新綠體力條
		player_hud.set_overheat_visual(false)                # 確保開局沒有過熱特效
		
		if player_hud.has_method("update_ammo"):
			player_hud.update_ammo(current_ammo, max_ammo)
		
	update_hp_bar()
		
	# --- 靈魂回收系統 (撿屍體) ---
	if DataManager and DataManager.has_soul_on_ground: 
		if DataManager.soul_map_path == get_tree().current_scene.scene_file_path:
			var soul_scene = load("res://soul/Soul.tscn") 
			if soul_scene: 
				var soul = soul_scene.instantiate() 
				soul.global_position = DataManager.soul_spawn_pos 
				soul.lost_gold = DataManager.soul_stored_gold     
				soul.scale = Vector2(2.0, 2.0) 
				get_tree().current_scene.call_deferred("add_child", soul) 

# ==========================================
# 裝備能力統整計算中心
# ==========================================
func recalculate_stats():
	var bonus_hp = 0 
	
	if DataManager.has_sticker("001"):
		bonus_hp += DataManager.STICKER_DB["001"].value 
		
	max_hp = base_max_hp + bonus_hp
	
	if current_hp > max_hp:
		current_hp = max_hp
		
	update_hp_bar() 
	print("【系統】玩家能力已更新，目前最大血量：", max_hp)

# ==========================================
# 開發者外掛與輸入偵測
# ==========================================
func _input(event):
	if is_shopping:
		return

	# 🌟 筆記本與存檔畫架的返回邏輯
	if event.is_action_pressed("closeyamain"):
		if is_reading_book:
			if opened_from_savepoint:
				if notebook_ui:
					notebook_ui.hide()
					notebook_ui.is_open = false
					
				opened_from_savepoint = false
				
				var save_menus = get_tree().get_nodes_in_group("save_menu")
				if save_menus.size() > 0:
					save_menus[0].show()
			else:
				is_reading_book = false
				state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
				if notebook_ui:
					notebook_ui.toggle_notebook(false)
		else:
			is_reading_book = true
			velocity = Vector2.ZERO 
			state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
			if notebook_ui:
				notebook_ui.toggle_notebook(false)

	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)
		
	if Input.is_physical_key_pressed(KEY_P) and event.is_pressed() and not event.is_echo():
		DataManager.add_item_to_reserve("potion_gugu", 1)
		print("【開發者外掛】憑空獲得 1 罐咕咕嘎嘎藥水！")

# ==========================================
# 物理與邏輯更新
# ==========================================
func _physics_process(delta: float) -> void: 
	if not is_dead: 
		if is_reading_book or is_shopping:
			velocity = Vector2.ZERO
			
			if state_machine.process_mode != Node.PROCESS_MODE_DISABLED:
				state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
				
			move_and_slide()        
			return                  
		else:
			if state_machine.process_mode == Node.PROCESS_MODE_DISABLED:
				state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		
		input_direction = Input.get_vector("left", "right", "up", "down") 

		if Input.is_action_just_pressed("slot_left"): 
			DataManager.rotate_quick_slot(-1)
			
		if Input.is_action_just_pressed("slot_right"): 
			DataManager.rotate_quick_slot(1)

		if Input.is_action_just_pressed("skill_01"): 
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
				if current_ammo > 0:
					current_ammo -= 1
					shoot_slow_timer = 0.3
					
					print("【墨水發射】射出一發！剩餘彈藥：", current_ammo, "/", max_ammo)
					
					var current_buff: float = get_oversaturation_buff() 
					if DataManager.has_sticker("004"):
						current_buff *= DataManager.STICKER_DB["004"].value
						print("【魔法棒生效】技能最終傷害倍率提升為：", current_buff)
					
					skill_01.shoot(current_buff) 
					
					if player_hud and player_hud.has_method("update_ammo"):
						player_hud.update_ammo(current_ammo, max_ammo)
				else: 
					print("⚠️ 墨水用盡！請使用近戰揮刀補充墨水！") 
					
			elif is_overheated: 
				print("系統過熱中！無法釋放技能！") 

		if Input.is_action_just_pressed("USESKILL"): 
			if state_machine.current_state.name != "PlayerHeal": 
				DataManager.use_current_item() 

		if sp_delay_timer > 0:            
			sp_delay_timer -= delta       
		else:                                      
			if current_sp < max_sp: 
				var regen_rate = 10.0 if is_overheated else 12.0 
				current_sp = min(current_sp + regen_rate * delta, max_sp) 
				
				if is_overheated and current_sp >= max_sp * 0.7: 
					is_overheated = false 
					player_hud.set_overheat_visual(false) 
					print("體力恢復至 70%，解除過熱狀態！") 
					
				player_hud.update_sp(current_sp, max_sp) 

	if shoot_slow_timer > 0:
		shoot_slow_timer -= delta
		if not is_dashing:
			velocity *= 0.05

	move_and_slide()

# ==========================================
# 資源消耗控制 (體力與彈藥)
# ==========================================
func use_sp(amount: float) -> bool: 
	if is_overheated: return false 

	if current_sp > 0: 
		current_sp = max(current_sp - amount, 0.0) 
		sp_delay_timer = sp_regen_delay 
		
		if current_sp <= 0:         
			is_overheated = true
			player_hud.set_overheat_visual(true) 
			print("體力耗盡！進入過熱狀態！") 

		player_hud.update_sp(current_sp, max_sp) 
		return true 
	return false 

# 近戰命中時呼叫此函數補充墨水，並給予頓幀打擊反饋
func restore_ammo(amount: int = 1) -> void:
	if DataManager and DataManager.has_method("trigger_hitstop"):
		DataManager.trigger_hitstop(0.04, 0.1)
		
	if current_ammo < max_ammo:
		current_ammo = min(current_ammo + amount, max_ammo)
		print("【墨水補充】近戰命中！成功回補 ", amount, " 發，目前彈藥：", current_ammo, "/", max_ammo)
		
		if player_hud and player_hud.has_method("update_ammo"):
			player_hud.update_ammo(current_ammo, max_ammo)

# ==========================================
# 戰鬥、受傷與無敵邏輯
# ==========================================

# 外部傷害接收中心 (包含扣血、擊退、相機震動與無敵觸發)
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_invincible:
		return
		
	current_hp = max(current_hp - amount, 0)
	update_hp_bar()
	
	# 1️⃣ 觸發受擊頓幀
	if DataManager and DataManager.has_method("trigger_hitstop"):
		DataManager.trigger_hitstop(0.07, 0.05)
	
	# 2️⃣ 受擊擊退計算與 0.15 秒煞車過渡
	var knockback_dir = dir
	if knockback_dir == Vector2.ZERO and attacker_pos != Vector2.ZERO:
		knockback_dir = (global_position - attacker_pos).normalized()
		
	if knockback_dir != Vector2.ZERO:
		velocity = knockback_dir * knockback_strength
		var kb_tween = create_tween()
		kb_tween.tween_property(self, "velocity", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	# 3️⃣ 受傷相機打擊震動
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(14.0)
		
	# 4️⃣ 觸發受擊紅閃 + 變形擠壓視覺特效
	play_hurt_effects()
		
	# 5️⃣ 啟動無敵時間與半透明閃爍
	start_invincibility()
	
	if current_hp <= 0:
		die()
	else:
		handle_hurt()

# 🌟【防縮水修復】受擊瞬間變紅閃爍與微擠壓，並精準彈回原始大小
func play_hurt_effects() -> void:
	if animated_sprite_2d:
		var tween = create_tween().set_parallel(true)
		
		# 瞬間變紅高亮受擊
		animated_sprite_2d.modulate = Color(3.0, 0.4, 0.4)
		tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.15)
		
		# 🌟【關鍵修改】依據原始比例做 1.2 / 0.8 擠壓，最後平滑彈回原本的體型！
		animated_sprite_2d.scale = Vector2(original_sprite_scale.x * 1.2, original_sprite_scale.y * 0.8)
		tween.tween_property(animated_sprite_2d, "scale", original_sprite_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# 無敵時間倒數與半透明閃爍視覺處理
func start_invincibility() -> void:
	is_invincible = true
	
	var tween = create_tween().set_loops(int(invincibility_duration / 0.1))
	tween.tween_property(animated_sprite_2d, "modulate:a", 0.3, 0.05)
	tween.tween_property(animated_sprite_2d, "modulate:a", 1.0, 0.05)
	
	await get_tree().create_timer(invincibility_duration).timeout
	is_invincible = false
	animated_sprite_2d.modulate.a = 1.0

func get_current_basic_attack_damage() -> float:
	var final_base_damage: float = basic_attack_damage
	
	if DataManager.has_sticker("008"):
		var threshold: float = DataManager.STICKER_DB["008"].threshold 
		
		if float(current_hp) / float(max_hp) <= threshold:
			final_base_damage *= DataManager.STICKER_DB["008"].value 
			print("【起床氣發動】血量低於 35%，基礎普攻傷害飆升至：", final_base_damage)
			
	return final_base_damage

func get_oversaturation_buff() -> float: 
	if current_ammo >= max_ammo: 
		print("【過飽和狀態】滿彈藥狀態下發射！目前倍率：1.5 倍") 
		return 1.5 
	return 1.0 

func on_enemy_killed():
	if DataManager.has_sticker("006"):
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		var heal_amount: int = int(max_hp * heal_percent)
		current_hp = min(current_hp + heal_amount, max_hp)
		update_hp_bar()
		print("【手裡劍發動】成功擊殺敵人，吸取血量：", heal_amount, "，目前血量：", current_hp)

func handle_hurt(): 
	if is_reading_book:
		is_reading_book = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		if notebook_ui:
			notebook_ui.close_notebook()
		print("【戰鬥提示】看書時遭到攻擊，筆記本已強制關閉！")
	
	if is_shopping:
		is_shopping = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		
		for node in get_tree().root.get_children():
			if node.name == "ShopUI":
				node.queue_free()
		print("【戰鬥警告】買東西時遭到攻擊！商店強制關閉！")
	
	var state_name = state_machine.current_state.name.to_lower() 
	
	if "stun" in state_name or "pant" in state_name: 
		velocity = knockback_force 
		return 
		
	state_machine.change_state("PlayerHurt") 

# ==========================================
# 外部補血接收器
# ==========================================
func heal(amount: int) -> void:
	if current_hp < max_hp:
		current_hp = min(current_hp + amount, max_hp)
		update_hp_bar()
		print("【玩家】喝下道具！恢復了 ", amount, " 點生命！目前血量：", current_hp)

# ==========================================
# 狀態與 UI 更新
# ==========================================
func die(): 
	if is_dead: return 
	is_dead = true 
	if state_machine: state_machine.change_state("PlayerDie") 

func update_hp_bar(): 
	if player_hud: player_hud.update_hp(current_hp, max_hp) 
	
	var hp_ratio: float = max(float(current_hp) / float(max_hp), 0.0) 
	if animated_sprite_2d.material: 
		var tween = get_tree().create_tween() 
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) 

# ==========================================
# 動畫播放控制器
# ==========================================
func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO): 
	var anim = get_node_or_null("AnimatedSprite2D") 
	if anim == null: return 
	
	if not is_dashing and input_direction != Vector2.ZERO: 
		if abs(input_direction.x) > abs(input_direction.y): 
			facing_direction = "right" if input_direction.x > 0 else "left" 
		else: 
			facing_direction = "down" if input_direction.y > 0 else "up" 
				
	anim.play(prefix + "_" + facing_direction)

extends BaseCharacter # 繼承自基礎角色類別，獲得通用功能 (如死亡、受傷框架)
class_name Player # 宣告這個腳本代表「玩家 (Player)」

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (秒)
@export var basic_attack_damage: float = 15.0 # 玩家的基礎揮刀攻擊力

# 受傷無敵時間 (Iframes) 參數
@export var invincibility_duration: float = 0.6  # 無敵時間 (0.6 秒)
var is_invincible: bool = false                  # 無敵狀態開關

# 🌟【防縮水修復】自動記憶 Inspector 設定的原始精靈圖大小
var original_sprite_scale: Vector2 = Vector2.ONE

# 記住玩家一絲不掛時的「基礎最大血量」
var base_max_hp: int = 100

# ==========================================
# [🌟 墨水系統] 與 體力 (SP) 系統
# ==========================================
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

# ==========================================
# 🌟 墨水武器系統變數
# ==========================================
# 宣告三種武器模式 (對應 InkBar 的 0, 1, 2)
enum WeaponMode { BLUE, RED, YELLOW }
var current_weapon: WeaponMode = WeaponMode.BLUE

# 🌟 徹底改用純墨水數值
var max_ink: float = 60.0
var current_ink: float = 60.0

@onready var state_machine: StateMachine = $StateMachine               # 控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D  # 負責播放動畫的精靈圖
@onready var player_hud: CanvasLayer = $PlayerHUD                      # 畫面左上角的狀態條介面 (UI)
@onready var magic_brush: Node2D = $MagicBrush                         # 🌟 掛在玩家身上的全能魔法畫筆

# 🌟【組件化引用】自動抓取玩家身上的擊退組件
@onready var knockback_component: KnockbackComponent = get_node_or_null("KnockbackComponent")

# 抓取素描本 UI 節點
@onready var notebook_ui = $MenuLayer/NotebookUI

# ==========================================
# 武器墨水消耗表
# ==========================================
func get_weapon_cost() -> float:
	match current_weapon:
		WeaponMode.BLUE: return 10.0
		WeaponMode.RED: return 15.0  # 紅色最低門檻需要 15 墨水
		WeaponMode.YELLOW: return 20.0
	return 10.0

# ==========================================
# 遊戲初始化 (_ready)
# ==========================================
func _ready(): 
	super._ready() 
	print("以防大家沒看到 菜心楊是傻逼")
	if animated_sprite_2d:
		original_sprite_scale = animated_sprite_2d.scale
	
	DataManager.player_node = self
	
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	recalculate_stats()
	
	# --- 讀取存檔資料 ---
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position
		
	if DataManager and DataManager.saved_hp > 0: 
		current_hp = min(DataManager.saved_hp, max_hp) 
		current_sp = DataManager.saved_sp 
	else: 
		current_sp = 50     # 第一次玩給予預設體力
		
	# --- 初始化 UI 介面 ---
	if player_hud: 
		player_hud.update_hp(current_hp, max_hp) 
		player_hud.update_sp(current_sp, max_sp) 
		player_hud.set_overheat_visual(false) 
			
		# 🌟 初始化時，同步當前的墨水池與武器模式 UI
		if player_hud.has_method("set_ink_mode"):
			player_hud.set_ink_mode(current_weapon)
			player_hud.update_ink(current_ink, max_ink)
		
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
	
	# 🌟【加在這裡！】親自幫玩家的大腦開機
	if state_machine:
		state_machine.init(self)
	
	_run_bug_radar(get_tree().root)

# ==========================================
# 開發者外掛與輸入偵測
# ==========================================
func _input(event):
	if is_shopping: return

	var pressed_cancel = event.is_action_pressed("TAB") or event.is_action_pressed("ESC")

	if is_reading_book and pressed_cancel:
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
				
		return 
	
	if not is_reading_book and event.is_action_pressed("TAB"):
		is_reading_book = true
		velocity = Vector2.ZERO 
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
		if notebook_ui:
			notebook_ui.toggle_notebook(false)

	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)
		

# ==========================================
# 裝備能力統整計算中心
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
		
		# 正常讀取玩家的 WASD 方向
		input_direction = Input.get_vector("left", "right", "up", "down") 

		# 🌟【新增攔截器】：狙擊槍蓄力罰站系統
		if magic_brush and magic_brush.is_charging:
			input_direction = Vector2.ZERO # 騙狀態機「玩家現在沒有按方向鍵」，這樣就會自動切換成站立(Idle)動畫
			
			var is_in_knockback: bool = knockback_component and knockback_component.knockback_force.length() > 0.0
			# 如果玩家不是在衝刺中、也沒有被怪物打飛，就強制瞬間煞車定住！
			if not is_dashing and not is_in_knockback:
				velocity = Vector2.ZERO    

		# ----------------------------------------------
		
		if Input.is_action_just_pressed("slot_left"): DataManager.rotate_quick_slot(-1)
		if Input.is_action_just_pressed("slot_right"): DataManager.rotate_quick_slot(1)

		# 🌟 監聽切換武器按鍵
		if Input.is_action_just_pressed("switch_weapon"):
			switch_next_weapon()

		# ==========================================
		# 🌟 發射與蓄力邏輯 (純淨墨水系統)
		# ==========================================
		if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
			var cost = get_weapon_cost()
			
			# 1. 🌟 玩家【按下】攻擊鍵 (藍色連發 / 黃色散彈，或紅色開始蓄力)
			if Input.is_action_just_pressed("skill_01"): 
				if current_ink >= cost:
					var current_buff: float = get_oversaturation_buff() 
					if DataManager.has_sticker("004"):
						current_buff *= DataManager.STICKER_DB["004"].value
					
					if current_weapon == WeaponMode.RED:
						# 紅色模式：算出目前最多能蓄力幾段
						var max_stages = floor(current_ink / 15.0)
						magic_brush.press_shoot(current_buff, max_stages)
					else:
						# 🌟 藍色與黃色共用：瞬間發射、瞬間扣墨水
						magic_brush.press_shoot(current_buff)
						current_ink -= cost
						
						# 根據武器給予不同的自身硬直 (減速時間)
						if current_weapon == WeaponMode.YELLOW:
							shoot_slow_timer = 0.4 # 散彈後座力硬直大一點
						else:
							shoot_slow_timer = 0.3 # 藍槍硬直小一點
							
						if player_hud and player_hud.has_method("update_ink"): 
							player_hud.update_ink(current_ink, max_ink)
				else: 
					print("⚠️ 墨水用盡！請使用近戰揮刀補充墨水！") 
			
			# 2. 🌟 玩家【按住】攻擊鍵 (紅色專屬：UI 預覽同步扣除墨水)
			if Input.is_action_pressed("skill_01") and current_weapon == WeaponMode.RED:
				if magic_brush and magic_brush.is_charging:
					var stage = magic_brush.get_current_stage()
					var preview_val = current_ink - (stage * 15.0)
					if player_hud and player_hud.has_method("preview_ink"): 
						player_hud.preview_ink(preview_val)
			
			# 3. 🌟 玩家【放開】攻擊鍵 (紅色專屬：確定發射或啞火)
			if Input.is_action_just_released("skill_01"):
				if current_weapon == WeaponMode.RED and magic_brush and magic_brush.is_charging:
					var stage = magic_brush.get_current_stage()
					
					if stage > 0:
						var current_buff = get_oversaturation_buff() 
						if DataManager.has_sticker("004"):
							current_buff *= DataManager.STICKER_DB["004"].value
							
						magic_brush.release_shoot(current_buff)
						current_ink -= (stage * 15.0)
						shoot_slow_timer = 0.6 
						
						if player_hud and player_hud.has_method("confirm_ink_drop"): 
							player_hud.confirm_ink_drop(current_ink)
						elif player_hud and player_hud.has_method("update_ink"):
							player_hud.update_ink(current_ink, max_ink)
					else:
						magic_brush.cancel_shoot()
						if player_hud and player_hud.has_method("preview_ink"): 
							player_hud.preview_ink(current_ink)
		
						
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
					
				player_hud.update_sp(current_sp, max_sp) 

	# 只有在非擊退狀態下，發射減速才會生效
	var is_in_knockback: bool = knockback_component and knockback_component.knockback_force.length() > 0.0
	if shoot_slow_timer > 0:
		shoot_slow_timer -= delta
		if not is_dashing and not is_in_knockback:
			velocity *= 0.05

	move_and_slide()

# ==========================================
# 🌟 武器切換系統
# ==========================================
func switch_next_weapon() -> void:
	current_weapon = (current_weapon + 1) % 3 as WeaponMode
	if magic_brush and magic_brush.has_method("set_mode"):
		magic_brush.set_mode(current_weapon)
	
	if player_hud and player_hud.has_method("set_ink_mode"):
		player_hud.set_ink_mode(current_weapon)
		
	print("已切換武器至：", current_weapon)

# ==========================================
# 資源消耗控制 (體力與墨水)
# ==========================================
func use_sp(amount: float) -> bool: 
	if is_overheated: return false 

	if current_sp > 0: 
		current_sp = max(current_sp - amount, 0.0) 
		sp_delay_timer = sp_regen_delay 
		
		if current_sp <= 0:          
			is_overheated = true
			player_hud.set_overheat_visual(true) 

		player_hud.update_sp(current_sp, max_sp) 
		return true 
	return false 

# 🌟 新版：回復墨水 (核心邏輯)
func add_ink(amount: float = 10.0) -> void:
	if current_ink < max_ink:
		current_ink = min(current_ink + amount, max_ink)
		if player_hud and player_hud.has_method("update_ink"):
			player_hud.update_ink(current_ink, max_ink)

func refill_full_ink() -> void:
	current_ink = max_ink
	if player_hud and player_hud.has_method("update_ink"):
		player_hud.update_ink(current_ink, max_ink)

# ==========================================
# 🌟 舊版近戰回血系統 (無縫橋接新版墨水！)
# ==========================================
# 讓你的近戰腳本不用改任何一個字，就能完美對接！
# 以前近戰命中回 1 發彈藥，現在會自動轉換成回復 10 點墨水！
func add_ammo(amount: int = 1) -> void:
	add_ink(amount * 10.0)

func restore_ammo(amount: int = 1) -> void:
	add_ink(amount * 10.0)

# 近戰擊殺敵人時，自動回滿墨水池！
func refill_full_ammo() -> void:
	refill_full_ink()

func get_oversaturation_buff() -> float: 
	# 判斷墨水是否全滿
	if current_ink >= max_ink: 
		return 1.5 
	return 1.0

# ==========================================
# 戰鬥、受傷與無敵邏輯
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if is_dead or is_invincible: return
		
	current_hp = max(current_hp - amount, 0)
	update_hp_bar()
	
	if DataManager and DataManager.has_method("trigger_hitstop"):
		DataManager.trigger_hitstop(0.07, 0.05)
	
	var knockback_dir = dir if dir != Vector2.ZERO else (global_position - attacker_pos).normalized()
	if knockback_component and knockback_dir != Vector2.ZERO:
		knockback_component.apply_knockback(knockback_dir, -1.0, extra_knockback)
		
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(14.0)
		
	play_hurt_effects()
	start_invincibility()
	
	if current_hp <= 0:
		die()
	else:
		handle_hurt()

func play_hurt_effects() -> void:
	if animated_sprite_2d:
		var tween = create_tween().set_parallel(true)
		animated_sprite_2d.modulate = Color(3.0, 0.4, 0.4)
		tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.15)
		
		animated_sprite_2d.scale = Vector2(original_sprite_scale.x * 1.2, original_sprite_scale.y * 0.8)
		tween.tween_property(animated_sprite_2d, "scale", original_sprite_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	return final_base_damage

func on_enemy_killed():
	if DataManager.has_sticker("006"):
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		var heal_amount: int = int(max_hp * heal_percent)
		current_hp = min(current_hp + heal_amount, max_hp)
		update_hp_bar()

func handle_hurt(): 
	if is_reading_book:
		is_reading_book = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		if notebook_ui:
			notebook_ui.close_notebook()
	
	if is_shopping:
		is_shopping = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		for node in get_tree().root.get_children():
			if node.name == "ShopUI":
				node.queue_free()
	
	var state_name = state_machine.current_state.name.to_lower() 
	if "stun" in state_name or "pant" in state_name: 
		return 
		
	state_machine.change_state("PlayerHurt") 

func heal(amount: int) -> void:
	var final_amount = amount 
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
	
	var hp_ratio: float = max(float(current_hp) / float(max_hp), 0.0) 
	if animated_sprite_2d.material: 
		var tween = get_tree().create_tween() 
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) 

func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO):
	var anim = get_node_or_null("AnimatedSprite2D")
	if anim == null:
		return

	# 只有正常移動時才更新面朝方向
	if not is_dashing and input_direction != Vector2.ZERO:
		if abs(input_direction.x) > abs(input_direction.y):
			facing_direction = "right" if input_direction.x > 0 else "left"
		else:
			facing_direction = "down" if input_direction.y > 0 else "up"

	# 組合真正要播放的動畫名稱
	var animation_name = prefix + "_" + facing_direction

	# 防止要求播放不存在的動畫
	if not anim.sprite_frames.has_animation(animation_name):
		print("⚠️【玩家動畫錯誤】找不到動畫：", animation_name)
		print("   prefix = ", prefix)
		print("   facing_direction = ", facing_direction)
		return

	anim.play(animation_name)


# 🌟🌟🌟 終極 Bug 掃描雷達 🌟🌟🌟
func _run_bug_radar(node: Node):
	if node is AnimatedSprite2D:
		# 如果抓到哪個傢伙的動畫是空的
		if node.animation == "":
			print("\n====================================")
			print("🚨🚨🚨 抓到真兇了！空動畫節點在這裡 🚨🚨🚨")
			print("👉 節點絕對路徑：", node.get_path())
			print("👉 來源場景檔案：", node.owner.scene_file_path if node.owner else "無")
			print("====================================\n")
			
	# 繼續往下挖出所有的子孫節點
	for child in node.get_children():
		_run_bug_radar(child)

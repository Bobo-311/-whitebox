extends BaseCharacter # 繼承自基礎角色類別，獲得通用功能 (如死亡、受傷框架)
class_name Player # 宣告這個腳本代表「玩家 (Player)」

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (秒)
@export var basic_attack_damage: float = 15.0 # 玩家的基礎揮刀攻擊力

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
	
	DataManager.player_node = self # 玩家一出生，立刻將自己註冊到全域大腦裡
	
	# 訂閱裝備廣播頻道，確保裝備變動時重算能力
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	# 開局防呆：手動算一次裝備屬性
	recalculate_stats()
	
	# --- 讀取存檔資料 ---
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position # 將位置強制移動到存檔點
		
	if DataManager and DataManager.saved_hp > 0: 
		# 讀檔時，現在的血量不能超過算完裝備後的新血量上限
		current_hp = min(DataManager.saved_hp, max_hp) 
		current_sp = DataManager.saved_sp 
	else: 
		current_sp = 50     # 第一次玩給予預設體力
		
	# --- 初始化 UI 介面 ---
	if player_hud: 
		player_hud.update_hp(current_hp, max_hp)             # 更新紅血條
		player_hud.update_sp(current_sp, max_sp)             # 更新綠體力條
		player_hud.set_overheat_visual(false)                # 確保開局沒有過熱特效
		
		# 墨水彈藥系統自動更新
		if player_hud.has_method("update_ammo"):
			player_hud.update_ammo(current_ammo, max_ammo)
		
	# 依照當前 current_hp 算出最精準的身體顏色！
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
# ==========================================
# 開發者外掛與輸入偵測
# ==========================================
func _input(event):
	# 如果在商店買東西，完全阻斷
	if is_shopping:
		return

	# 🌟 筆記本與存檔畫架的返回邏輯
	if event.is_action_pressed("closeyamain"):
		if is_reading_book:
			if opened_from_savepoint:
				# 情況 A：從存檔點打開的筆記本，準備退回存檔點
				
				# 1. 直接強制隱藏筆記本，不透過 toggle，最安全！
				if notebook_ui:
					notebook_ui.hide()
					notebook_ui.is_open = false
					
				opened_from_savepoint = false # 解除標記
				
				# 2. 把藏在背景的存檔畫架找出來，重新顯示
				var save_menus = get_tree().get_nodes_in_group("save_menu")
				if save_menus.size() > 0:
					save_menus[0].show()
					
				# 🚫 絕對不能在這裡加 get_tree().paused = true，否則會永久死機卡住！
				# (保留 is_reading_book = true 狀態，讓玩家繼續乖乖在畫架前罰站)
				
			else:
				# 情況 B：正常遊玩時，關閉筆記本
				is_reading_book = false
				state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
				if notebook_ui:
					notebook_ui.toggle_notebook(false)
		else:
			# 情況 C：正常遊玩時，打開筆記本
			is_reading_book = true
			velocity = Vector2.ZERO 
			state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
			if notebook_ui:
				notebook_ui.toggle_notebook(false)

	# 測試用外掛：按下指定按鍵直接加 100 元
	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)
		
	# 【全新測試外掛：按鍵盤 P 鍵，直接進貨一罐藥水】
	if Input.is_physical_key_pressed(KEY_P) and event.is_pressed() and not event.is_echo():
		DataManager.add_item_to_reserve("potion_gugu", 1)
		print("【開發者外掛】憑空獲得 1 罐咕咕嘎嘎藥水！")

# ==========================================
# 物理與邏輯更新
# ==========================================
func _physics_process(delta: float) -> void: 
	# 【第一關防呆】：檢查玩家死了沒。死人是不會動的
	if not is_dead: 
		
		# 🌟🌟🌟 [本次修改：統一看書與購物的狀態機阻斷] 🌟🌟🌟
		if is_reading_book or is_shopping:
			velocity = Vector2.ZERO # 強制煞車，避免滑行
			
			# 把狀態機「關機」，這樣所有的攻擊、翻滾腳本就不會執行
			if state_machine.process_mode != Node.PROCESS_MODE_DISABLED:
				state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
				
			move_and_slide()        
			return                  
		else:
			# 恢復自由時，將狀態機重新「開機」
			if state_machine.process_mode == Node.PROCESS_MODE_DISABLED:
				state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		# 🌟🌟🌟 [修改結束] 🌟🌟🌟
		
		# 🏃 移動向量計算
		input_direction = Input.get_vector("left", "right", "up", "down") 

		# 🎒 快捷欄切換區 (1鍵與3鍵)
		if Input.is_action_just_pressed("slot_left"): 
			DataManager.rotate_quick_slot(-1)
			
		if Input.is_action_just_pressed("slot_right"): 
			DataManager.rotate_quick_slot(1)

		# ⚔️ 戰鬥與技能區：射擊墨水彈 (skill_01 鍵)
		if Input.is_action_just_pressed("skill_01"): 
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
				
				# 檢查是否有剩餘墨水彈藥
				if current_ammo > 0:
					current_ammo -= 1
					
					# 觸發 0.3 秒射擊沉重減速
					shoot_slow_timer = 0.3
					
					print("【墨水發射】射出一發！剩餘彈藥：", current_ammo, "/", max_ammo)
					
					# 計算過飽和與貼紙倍率
					var current_buff: float = get_oversaturation_buff() 
					
					if DataManager.has_sticker("004"):
						current_buff *= DataManager.STICKER_DB["004"].value
						print("【魔法棒生效】技能最終傷害倍率提升為：", current_buff)
					
					# 執行發射
					skill_01.shoot(current_buff) 
					
					# 更新 UI
					if player_hud and player_hud.has_method("update_ammo"):
						player_hud.update_ammo(current_ammo, max_ammo)
				else: 
					print("⚠️ 墨水用盡！請使用近戰揮刀補充墨水！") 
					
			elif is_overheated: 
				print("系統過熱中！無法釋放技能！") 

		# 🎒 使用快捷欄道具 (USESKILL / Q 鍵)
		if Input.is_action_just_pressed("USESKILL"): 
			if state_machine.current_state.name != "PlayerHeal": 
				DataManager.use_current_item() 

		# 💚 體力 (SP) 自動恢復邏輯
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

	# 🌟 [射擊沉重減速懲罰]
	if shoot_slow_timer > 0:
		shoot_slow_timer -= delta
		if not is_dashing: # 衝刺閃避不受減速影響
			velocity *= 0.05

	move_and_slide() # 執行移動與物理碰撞

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

# [🌟 墨水彈藥系統改動] 近戰命中時呼叫此函數補充墨水
func restore_ammo(amount: int = 1) -> void:
	if current_ammo < max_ammo:
		current_ammo = min(current_ammo + amount, max_ammo)
		print("【墨水補充】近戰命中！成功回補 ", amount, " 發，目前彈藥：", current_ammo, "/", max_ammo)
		
		if player_hud and player_hud.has_method("update_ammo"):
			player_hud.update_ammo(current_ammo, max_ammo)

# ==========================================
# 戰鬥與受傷邏輯
# ==========================================

# 負責計算包含「起床氣 (008)」機制在內的最終基礎普攻傷害
func get_current_basic_attack_damage() -> float:
	var final_base_damage: float = basic_attack_damage
	
	if DataManager.has_sticker("008"):
		var threshold: float = DataManager.STICKER_DB["008"].threshold 
		
		if float(current_hp) / float(max_hp) <= threshold:
			final_base_damage *= DataManager.STICKER_DB["008"].value 
			print("【起床氣發動】血量低於 35%，基礎普攻傷害飆升至：", final_base_damage)
			
	return final_base_damage

# [🌟 墨水彈藥系統改動] 判斷是否處於「滿彈藥（過飽和）」狀態，給予 1.5 倍爆擊
func get_oversaturation_buff() -> float: 
	if current_ammo >= max_ammo: 
		print("【過飽和狀態】滿彈藥狀態下發射！目前倍率：1.5 倍") 
		return 1.5 
	return 1.0 

# 專門用來接收怪物死掉時傳來的通知，結算 006 吸血
func on_enemy_killed():
	if DataManager.has_sticker("006"):
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		var heal_amount: int = int(max_hp * heal_percent)
		current_hp = min(current_hp + heal_amount, max_hp)
		update_hp_bar()
		print("【手裡劍發動】成功擊殺敵人，吸取血量：", heal_amount, "，目前血量：", current_hp)

func handle_hurt(): 
	# 被打斷機制：看書時如果遭到攻擊，強制關閉筆記本並拿回控制權
	if is_reading_book:
		is_reading_book = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
		if notebook_ui:
			notebook_ui.close_notebook()
		print("【戰鬥提示】看書時遭到攻擊，筆記本已強制關閉！")
	
	# 🌟🌟🌟 [本次新增：方案 A 購物遭到攻擊強制打斷] 🌟🌟🌟
	if is_shopping:
		is_shopping = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT # 喚醒狀態機，讓玩家能反擊逃跑
		
		# 掃描畫面並強制銷毀商店，把玩家趕出購物狀態
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
# 🌟 外部補血接收器
# ==========================================
func heal(amount: int) -> void:
	if current_hp < max_hp:
		current_hp = min(current_hp + amount, max_hp)
		update_hp_bar() # 更新血條 UI 和身體顏色
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

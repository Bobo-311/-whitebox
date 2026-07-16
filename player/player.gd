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
# 能量 (EP) 與 體力 (SP) 系統
# ==========================================
@export var max_energy: int = 100          # 能量上限 (發動技能、過飽和狀態用)
var current_energy: int = 50               # 開局預設能量

@export var max_sp: float = 100.0          # 體力上限 (揮刀、翻滾消耗用)
var current_sp: float = 50                 # 開局預設體力
var is_overheated: bool = false            # 狀態開關：記錄玩家現在是否處於「過熱力竭」狀態
var sp_regen_delay: float = 0.5            # 體力恢復延遲：消耗後需等待 0.5 秒才能開始回體
var sp_delay_timer: float = 0.0            # 隱形計時器：負責倒數回體的等待時間

# ==========================================
# 狀態紀錄與節點抓取
# ==========================================
var input_direction: Vector2 = Vector2.ZERO # 記錄玩家按下的 WASD 方向向量
var facing_direction: String = "down"       # 記錄玩家最後面朝的方向，預設朝下
var is_dashing: bool = false                # 記錄玩家現在是否正在衝刺中

# [🌟 本次新增] 素描本系統狀態變數
var is_reading_book: bool = false           # 記錄玩家是否正在看筆記本

@onready var state_machine: StateMachine = $StateMachine               # 控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D  # 負責播放動畫的精靈圖
@onready var player_hud: CanvasLayer = $PlayerHUD                      # 畫面左上角的狀態條介面 (UI)
@onready var skill_01: Node2D = $Skill_01                              # 掛在玩家身上的技能發射器 (槍管)

# [🌟 本次新增] 抓取素描本 UI 節點
# ⚠️ 注意：我假設你把 NotebookUI 放進 PlayerHUD 裡了。如果名字或位置不一樣，請手動改這裡！
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
		current_energy = DataManager.saved_energy 
		current_sp = DataManager.saved_sp 
	else: 
		current_energy = 50 # 第一次玩給予預設能量
		current_sp = 50     # 第一次玩給予預設體力
		
	# --- 初始化 UI 介面 ---
	if player_hud: 
		player_hud.update_hp(current_hp, max_hp)             # 更新紅血條
		player_hud.update_energy(current_energy, max_energy) # 更新黃能量條
		player_hud.update_sp(current_sp, max_sp)             # 更新綠體力條
		player_hud.set_overheat_visual(false)                # 確保開局沒有過熱特效
		
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
func _input(event):
	# [🌟 本次新增] 監聽 Tab 鍵，開關素描本
	if event.is_action_pressed("notebook"):
		is_reading_book = !is_reading_book 
		if notebook_ui:
			notebook_ui.toggle_notebook()

	# 測試用外掛：按下指定按鍵直接加 100 元
	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)

# ==========================================
# 物理與邏輯更新 (每幀執行)
# ==========================================
func _physics_process(delta: float) -> void: 
	if not is_dead: # 只有活著才能操作
		
		# [🌟 本次新增] 核心防護：看書時強制罰站，鎖死移動與技能
		if is_reading_book:
			velocity = Vector2.ZERO # 速度歸零防滑行
			move_and_slide()        # 依然呼叫物理引擎維持基本碰撞
			return                  # 🛑 直接中斷！不跑下面的走路跟放技能邏輯
		
		# 抓取 WASD 輸入轉換成方向向量 (長度最大為 1)
		input_direction = Input.get_vector("left", "right", "up", "down") 

		# --- 技能施放 (Q鍵) ---
		if Input.is_action_just_pressed("skill_01"): 
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
				
				var current_buff: float = get_oversaturation_buff() 
				
				if DataManager.has_sticker("004"):
					current_buff *= DataManager.STICKER_DB["004"].value
					print("【魔法棒生效】技能最終傷害倍率提升為：", current_buff)
				
				if use_energy(30): 
					skill_01.shoot(current_buff) 
				else: 
					print("能量不足 30，無法施放 Q 技能！") 
			elif is_overheated: 
				print("系統過熱中！無法釋放技能！") 

		# --- 體力 (SP) 自動恢復邏輯 ---
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

	move_and_slide() # 根據目前的 velocity 執行移動與物理碰撞滑行

# ==========================================
# 資源消耗控制 (體力與能量)
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

func use_energy(amount: int) -> bool: 
	if current_energy >= amount: 
		current_energy -= amount 
		if player_hud: player_hud.update_energy(current_energy, max_energy) 
		return true 
	return false 

func add_energy(amount: int): 
	current_energy = min(current_energy + amount, max_energy) 
	if player_hud: player_hud.update_energy(current_energy, max_energy) 

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

# 負責判斷是否滿能量，並給予對應的倍率
func get_oversaturation_buff() -> float: 
	if current_energy >= max_energy: 
		print("【過飽和狀態】發動！目前倍率：1.5 倍") 
		return 1.5 
	return 1.0 

# 專門用來接收怪物死掉時傳來的通知，並結算 006 手裡劍的回血效果
func on_enemy_killed():
	if DataManager.has_sticker("006"):
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		var heal_amount: int = int(max_hp * heal_percent)
		current_hp = min(current_hp + heal_amount, max_hp)
		update_hp_bar()
		print("【手裡劍發動】成功擊殺敵人，吸取血量：", heal_amount, "，目前血量：", current_hp)

func handle_hurt(): 
	# [🌟 本次新增] 被打斷機制：看書時如果遭到攻擊，強制關閉筆記本並拿回控制權
	if is_reading_book:
		is_reading_book = false
		if notebook_ui:
			notebook_ui.close_notebook()
		print("【戰鬥提示】看書時遭到攻擊，筆記本已強制關閉！")
	
	var state_name = state_machine.current_state.name.to_lower() 
	
	if "stun" in state_name or "pant" in state_name: 
		velocity = knockback_force 
		return 
		
	state_machine.change_state("PlayerHurt") 

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

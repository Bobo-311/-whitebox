extends BaseCharacter # 繼承自基礎角色類別，獲得通用功能 (如死亡、受傷框架)
class_name Player # 宣告這個腳本代表「玩家 (Player)」

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (秒)
@export var basic_attack_damage: float = 15.0 # 玩家的基礎揮刀攻擊力

# [🌟 本次改動] 記住玩家一絲不掛時的「基礎最大血量」
# 確保裝備穿穿脫脫時，我們永遠知道最根本的血量基準是多少，不會越加越亂
var base_max_hp: int = 100

# ==========================================
# 能量 (EP) 與 體力 (SP) 系統
# ==========================================
@export var max_energy: int = 100          # 能量上限 (發動技能、過飽和狀態用)
var current_energy: int = 50               # 開局預設能量

@export var max_sp: float = 100.0          # 體力上限 (揮刀、翻滾消耗用)
var current_sp: float = 50                # 開局預設體力
var is_overheated: bool = false            # 狀態開關：記錄玩家現在是否處於「過熱力竭」狀態
var sp_regen_delay: float = 0.5            # 體力恢復延遲：消耗後需等待 0.5 秒才能開始回體
var sp_delay_timer: float = 0.0            # 隱形計時器：負責倒數回體的等待時間

# ==========================================
# 狀態紀錄與節點抓取
# ==========================================
var input_direction: Vector2 = Vector2.ZERO # 記錄玩家按下的 WASD 方向向量
var facing_direction: String = "down"       # 記錄玩家最後面朝的方向，預設朝下
var is_dashing: bool = false                # 記錄玩家現在是否正在衝刺中

@onready var state_machine: StateMachine = $StateMachine               # 控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D  # 負責播放動畫的精靈圖
@onready var player_hud: CanvasLayer = $PlayerHUD                      # 畫面左上角的狀態條介面 (UI)
@onready var skill_01: Node2D = $Skill_01                              # 掛在玩家身上的技能發射器 (槍管)

# ==========================================
# 遊戲初始化 (_ready)
# ==========================================
func _ready(): 
	super._ready() # 呼叫父類別準備函數，確保基本屬性初始化 (如血量補滿)
	
	DataManager.player_node = self # 玩家一出生，立刻將自己註冊到全域大腦裡
	
	# [🌟 本次改動] 訂閱裝備廣播頻道
	# 告訴大腦：「只要有人換裝備發出廣播，就立刻呼叫我底下的 recalculate_stats 函數重算能力」
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	# [🌟 本次改動] 開局防呆：手動算一次裝備屬性，確保開局最大血量是正確的
	recalculate_stats()
	
	# --- 讀取存檔資料 ---
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position # 將位置強制移動到存檔點
		
	if DataManager and DataManager.saved_hp > 0: 
		# [🌟 本次改動] 讀檔時，現在的血量不能超過算完裝備後的新血量上限
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
		
	# [🌟 本次改動] 刪除強制設為全彩的程式碼，改為呼叫 update_hp_bar() 
	# 讓系統載入完存檔後，立刻依照當前 current_hp 算出最精準的身體顏色！
	update_hp_bar()
		
	# --- 靈魂回收系統 (撿屍體) ---
	if DataManager and DataManager.has_soul_on_ground: 
		# 確保留在外的靈魂地圖，跟現在的地圖是同一張
		if DataManager.soul_map_path == get_tree().current_scene.scene_file_path:
			var soul_scene = load("res://soul/Soul.tscn") 
			if soul_scene: 
				var soul = soul_scene.instantiate() # 生成靈魂實體
				soul.global_position = DataManager.soul_spawn_pos # 放在上次死掉的位置
				soul.lost_gold = DataManager.soul_stored_gold     # 塞入遺失的金幣
				soul.scale = Vector2(2.0, 2.0) 
				get_tree().current_scene.call_deferred("add_child", soul) # 延遲加入場景確保安全

# ==========================================
# [🌟 本次改動] 裝備能力統整計算中心
# ==========================================
func recalculate_stats():
	var bonus_hp = 0 # 用來累加所有裝備給的「額外血量」
	
	# 向大腦圖鑑詢問：是否有裝備 "001" (愛心) 貼紙？
	if DataManager.has_sticker("001"):
		bonus_hp += DataManager.STICKER_DB["001"].value # 從圖鑑調出數值加上去
		
	# 最終最大血量 = 裸體基礎血量 (100) + 裝備總加成
	max_hp = base_max_hp + bonus_hp
	
	# 防呆：如果拔掉裝備導致上限變低，目前的血量必須往下壓，不能超過上限
	if current_hp > max_hp:
		current_hp = max_hp
		
	# 數值變動後，通知 UI 更新血條與身體顏色
	update_hp_bar() 
	print("【系統】玩家能力已更新，目前最大血量：", max_hp)

# ==========================================
# 開發者外掛與輸入偵測
# ==========================================
func _input(event):
	# 測試用外掛：按下指定按鍵直接加 100 元
	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)

# ==========================================
# 物理與邏輯更新 (每幀執行)
# ==========================================
func _physics_process(delta: float) -> void: 
	if not is_dead: # 只有活著才能操作
		# 抓取 WASD 輸入轉換成方向向量 (長度最大為 1)
		input_direction = Input.get_vector("left", "right", "up", "down") 
		
		# --- 技能施放 (Q鍵) ---
		if Input.is_action_just_pressed("skill_01"): 
			# 條件：不能在補血中，且不能處於過熱狀態
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
				
				# 1. 先取得原本的「過飽和」傷害倍率 (滿能量時會回傳 1.5，否則回傳 1.0)
				var current_buff: float = get_oversaturation_buff() 
				
				# 🌟 [本次改動] 2. 檢查大腦圖鑑，判斷是否裝備 004 魔法棒
				if DataManager.has_sticker("004"):
					# 如果有裝備，就把目前的倍率乘上魔法棒的 value (1.35)
					current_buff *= DataManager.STICKER_DB["004"].value
					print("【魔法棒生效】技能最終傷害倍率提升為：", current_buff)
				
				# 3. 嘗試扣除能量，如果成功就發射技能，並把算好的「最終倍率」傳遞給 skill_01
				if use_energy(30): 
					skill_01.shoot(current_buff) 
				else: 
					print("能量不足 30，無法施放 Q 技能！") 
			elif is_overheated: 
				print("系統過熱中！無法釋放技能！") 

		# --- 體力 (SP) 自動恢復邏輯 ---
		if sp_delay_timer > 0:            
			sp_delay_timer -= delta # 還在延遲時間內，繼續倒數      
		else:                                 
			if current_sp < max_sp: # 延遲結束且體力未滿，開始回體
				# 過熱時回體較慢 (10.0)，正常時較快 (12.0)
				var regen_rate = 10.0 if is_overheated else 12.0 
				current_sp = min(current_sp + regen_rate * delta, max_sp) # 增加體力但不超過上限
				
				# 體力恢復至 70% 解除過熱狀態
				if is_overheated and current_sp >= max_sp * 0.7: 
					is_overheated = false 
					player_hud.set_overheat_visual(false) # 關閉過熱 UI 特效
					print("體力恢復至 70%，解除過熱狀態！") 
					
				player_hud.update_sp(current_sp, max_sp) # 頻繁更新體力 UI

	move_and_slide() # 根據目前的 velocity 執行移動與物理碰撞滑行

# ==========================================
# 資源消耗控制 (體力與能量)
# ==========================================
func use_sp(amount: float) -> bool: 
	# 嘗試扣除體力。回傳 true 代表扣除成功，false 代表失敗
	if is_overheated: return false # 過熱期間嚴禁花費任何體力

	if current_sp > 0: # 只要體力大於 0 就能透支使用
		current_sp = max(current_sp - amount, 0.0) # 扣除體力，最低扣到 0
		sp_delay_timer = sp_regen_delay # 每次花費體力，重置回體延遲計時器
		
		# 體力徹底歸零，觸發過熱狀態
		if current_sp <= 0:        
			is_overheated = true
			player_hud.set_overheat_visual(true) # 開啟過熱 UI 特效
			print("體力耗盡！進入過熱狀態！") 

		player_hud.update_sp(current_sp, max_sp) # 更新 UI
		return true 
	return false # 體力已經是 0，拒絕執行動作

func use_energy(amount: int) -> bool: 
	# 嘗試扣除能量
	if current_energy >= amount: 
		current_energy -= amount 
		if player_hud: player_hud.update_energy(current_energy, max_energy) # 更新 UI
		return true 
	return false 

func add_energy(amount: int): 
	# 增加能量 (如普攻命中獎勵)
	current_energy = min(current_energy + amount, max_energy) # 增加能量但不超過上限
	if player_hud: player_hud.update_energy(current_energy, max_energy) # 更新 UI

# ==========================================
# 戰鬥與受傷邏輯
# ==========================================

# 🌟 [特別函數說明：普攻傷害結帳櫃檯]
# 負責計算包含「起床氣 (008)」機制在內的最終基礎普攻傷害
func get_current_basic_attack_damage() -> float:
	# 1. 先把原本玩家的基礎攻擊力 (你設定的 15.0) 拿出來準備計算
	var final_base_damage: float = basic_attack_damage
	
	# 2. 檢查大腦圖鑑，判斷玩家目前是否有裝備 008 憤怒大鵝 (起床氣) 貼紙
	if DataManager.has_sticker("008"):
		
		# 🌟 3. 直接讀取你在 DataManager 寫好的 threshold (門檻值 0.35)
		var threshold: float = DataManager.STICKER_DB["008"].threshold 
		
		# 4. 條件判定：計算當前血量百分比 (目前血量 / 最大血量)，檢查是否小於或等於門檻值 (0.35)
		if float(current_hp) / float(max_hp) <= threshold:
			# 5. 如果達成殘血條件，將基底攻擊力 (15.0) 乘上圖鑑裡的增傷倍率 (1.35 倍)
			final_base_damage *= DataManager.STICKER_DB["008"].value 
			print("【起床氣發動】血量低於 35%，基礎普攻傷害飆升至：", final_base_damage)
			
	# 6. 將算好的最終傷害 (沒發動是 15.0，發動是 20.25)，回傳給呼叫這個函數的人 (揮刀腳本)
	return final_base_damage

# 🌟 [特別函數說明：過飽和倍率結帳櫃檯]
# 負責判斷是否滿能量，並給予對應的倍率
func get_oversaturation_buff() -> float: 
	# 判斷：如果目前能量大於或等於最大能量上限
	if current_energy >= max_energy: 
		print("【過飽和狀態】發動！目前倍率：1.5 倍") 
		return 1.5 # 滿能量時，回傳 1.5 倍的增傷包裹
	# 如果能量沒滿
	return 1.0 # 正常狀態未滿能量時，回傳 1.0 倍 (不增傷)

# ==========================================
# 戰鬥與受傷邏輯
# ==========================================

# 🌟 [特別函數說明：擊殺接收中心]
# 專門用來接收怪物死掉時傳來的通知，並結算 006 手裡劍的回血效果
func on_enemy_killed():
	# 1. 檢查大腦圖鑑，判斷玩家目前是否有裝備 006 手裡劍
	if DataManager.has_sticker("006"):
		
		# 2. 從圖鑑讀取手裡劍的回血比例 (你在圖鑑裡設定的 value 應該是 0.10)
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		
		# 3. 計算回復量：最大血量 * 比例 (例如 100 * 0.1 = 10)。使用 int() 去掉小數點確保血量是整數
		var heal_amount: int = int(max_hp * heal_percent)
		
		# 4. 執行補血：把計算好的血量加到當前血量上，並使用 min() 防呆，確保補完不會超過最大血量
		current_hp = min(current_hp + heal_amount, max_hp)
		
		# 5. 更新 UI 血條與身體的灰階顏色
		update_hp_bar()
		
		# 6. 後台印出成功發動的訊息
		print("【手裡劍發動】成功擊殺敵人，吸取血量：", heal_amount, "，目前血量：", current_hp)



func handle_hurt(): 
	# 當玩家被怪物的 Hitbox 或子彈打中時呼叫
	var state_name = state_machine.current_state.name.to_lower() 
	
	# 霸體狀態檢測：處於暈眩或喘氣狀態時，只會被擊退，不播放受傷硬直動畫
	if "stun" in state_name or "pant" in state_name: 
		velocity = knockback_force 
		return 
		
	state_machine.change_state("PlayerHurt") # 切換到受傷狀態播放硬直動畫

# ==========================================
# 狀態與 UI 更新
# ==========================================
func die(): 
	# 處理死亡狀態切換
	if is_dead: return # 避免重複死亡
	is_dead = true 
	if state_machine: state_machine.change_state("PlayerDie") 

func update_hp_bar(): 
	# 更新 UI 血條與身體顏色
	if player_hud: player_hud.update_hp(current_hp, max_hp) 
	
	# [🌟 本次改動] 計算血量百分比 (0.0 ~ 1.0)，並透過 Shader 降低玩家精靈圖的色彩飽和度
	var hp_ratio: float = max(float(current_hp) / float(max_hp), 0.0) 
	if animated_sprite_2d.material: 
		var tween = get_tree().create_tween() 
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) 

# ==========================================
# 動畫播放控制器
# ==========================================
func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO): 
	# 統整動畫名稱。例如傳入 "run"，會根據面向組合出 "run_right" 播放
	var anim = get_node_or_null("AnimatedSprite2D") 
	if anim == null: return 
	
	# 決定面向 (翻滾衝刺時鎖定面向，不跟隨按鍵改變)
	if not is_dashing and input_direction != Vector2.ZERO: 
		# 判斷 X 軸還是 Y 軸的輸入幅度比較大，決定要播橫向還是縱向動畫
		if abs(input_direction.x) > abs(input_direction.y): 
			facing_direction = "right" if input_direction.x > 0 else "left" 
		else: 
			facing_direction = "down" if input_direction.y > 0 else "up" 
				
	anim.play(prefix + "_" + facing_direction) # 組合並播放

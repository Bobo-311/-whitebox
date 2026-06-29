extends BaseCharacter # 繼承自基礎角色類別，獲得血量、死亡、受傷等通用功能
class_name Player # 宣告這個腳本代表的肉體，正式歸類為「玩家 (Player)」

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (秒)

@export var basic_attack_damage: float = 100.0 # 玩家的基礎攻擊力 (揮刀傷害)

# [🌟 本次新增] 記住玩家一絲不掛時的「基礎最大血量」
# 確保裝備穿穿脫脫時，我們永遠知道最根本的血量基準是多少
var base_max_hp: int = 100

# ==========================================
# 能量 (EP) 與 體力 (SP) 系統
# ==========================================
@export var max_energy: int = 100      # 能量上限 (發動技能、過飽和狀態用)
var current_energy: int = 50           # 開局預設能量為 50

@export var max_sp: float = 100.0      # 體力上限 (揮刀、翻滾消耗用)
var current_sp: float = 50             # 開局預設體力為 50
var is_overheated: bool = false        # 狀態開關：記錄玩家現在是否處於「過熱力竭」狀態 (體力透支)
var sp_regen_delay: float = 0.5        # 體力恢復延遲：做出消耗動作後，必須等待 0.5 秒才能開始回體
var sp_delay_timer: float = 0.0        # 隱形計時器：負責倒數回體的等待時間

# ==========================================
# 狀態紀錄與節點抓取
# ==========================================
var input_direction: Vector2 = Vector2.ZERO # 記錄玩家按下的 WASD 方向向量
var facing_direction: String = "down"       # 記錄玩家最後面朝的方向，預設朝下
var is_dashing: bool = false                # 記錄玩家現在是否正在衝刺中

@onready var state_machine: StateMachine = $StateMachine       # 控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 負責播放動畫的精靈圖
@onready var player_hud: CanvasLayer = $PlayerHUD              # 畫面左上角的狀態條介面 (UI)
@onready var skill_01: Node2D = $Skill_01                      # 掛在玩家身上的技能發射器 (槍管)

# ==========================================
# 遊戲初始化 (_ready)
# ==========================================
func _ready(): 
	super._ready() # 呼叫父類別的準備函數，確保基本屬性初始化 (如血量補滿)
	
	DataManager.player_node = self # 玩家一出生，立刻把自己的肉體註冊到全域大腦裡
	
	# [🌟 本次新增] 訂閱裝備廣播頻道
	# 告訴大腦：「只要有人換裝備發出廣播，就立刻呼叫我底下的 recalculate_stats 函數重算能力」
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	# [🌟 本次新增] 開局防呆：手動算一次裝備屬性，確保開局最大血量是正確的
	recalculate_stats()
	
	# --- 讀取存檔資料 ---
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position # 將位置強制移動到存檔點
		
	if DataManager and DataManager.saved_hp > 0: 
		# [🌟 稍微修正] 讀檔時，現在的血量不能超過算完裝備後的新血量上限
		current_hp = min(DataManager.saved_hp, max_hp) 
		current_energy = DataManager.saved_energy 
		current_sp = DataManager.saved_sp 
	else: 
		current_energy = 50 # 第一次玩，給予預設能量
		current_sp = 50     # 第一次玩，給予預設體力
		
	# --- 初始化 UI 介面 ---
	if player_hud: 
		player_hud.update_hp(current_hp, max_hp)             # 更新紅血條
		player_hud.update_energy(current_energy, max_energy) # 更新黃能量條
		player_hud.update_sp(current_sp, max_sp)             # 更新綠體力條
		player_hud.set_overheat_visual(false)                # 確保開局沒有過熱特效
		
	# 🌟 針對灰色的修正：
	# 把原本強制設為 1.0 的程式碼刪掉，改成直接呼叫 update_hp_bar()
	# 這樣系統在載入完存檔後，會立刻依照現在的 current_hp 去算出最精準的顏色！
	update_hp_bar()
		
	# --- 靈魂回收系統 ---
	if DataManager and DataManager.has_soul_on_ground: 
		# 確保留在外的靈魂地圖，跟現在的地圖是同一張
		if DataManager.soul_map_path == get_tree().current_scene.scene_file_path:
			var soul_scene = load("res://soul/Soul.tscn") 
			if soul_scene: 
				var soul = soul_scene.instantiate() 
				soul.global_position = DataManager.soul_spawn_pos # 放在上次死掉的位置
				soul.lost_gold = DataManager.soul_stored_gold     # 塞入遺失的金幣
				soul.scale = Vector2(2.0, 2.0) 
				get_tree().current_scene.call_deferred("add_child", soul) # 延遲加入場景，確保安全

# ==========================================
# [🌟 本次新增] 裝備能力統整計算中心
# ==========================================
func recalculate_stats():
	var bonus_hp = 0 # 用來累加所有裝備給的「額外血量」
	
	# 向大腦圖鑑詢問：是否有裝備 "001" (愛心) 貼紙？
	if DataManager.has_sticker("001"):
		bonus_hp += DataManager.STICKER_DB["001"].value # 從圖鑑調出數值加上去
		print("【貼紙生效】裝備了 001 愛心，額外增加 ", DataManager.STICKER_DB["001"].value, " 點生命上限！")
		
	# 最終最大血量 = 裸體基礎血量 (100) + 裝備總加成
	max_hp = base_max_hp + bonus_hp
	
	# 防呆：如果拔掉裝備導致上限變低，目前的血量必須往下壓，不能超過上限
	if current_hp > max_hp:
		current_hp = max_hp
		
	# 數值變動後，通知 UI 更新血條顯示
	update_hp_bar() 
	print("【系統】玩家能力已重新計算，目前最大血量：", max_hp)

# ==========================================
# 開發者外掛與輸入偵測
# ==========================================
func _input(event):
	if event.is_action_pressed("cheater"): 
		if DataManager:
			DataManager.total_gold += 100 # 按下按鍵直接加 100 元，方便測試
			print("【開發者外掛】印鈔 100 元！目前總金額：" + str(DataManager.total_gold))

# ==========================================
# 物理與邏輯更新 (每幀執行)
# ==========================================
func _physics_process(delta: float) -> void: 
	if not is_dead: # 只有活著才能操作
		# 抓取 WASD 輸入轉換成方向向量 (長度最大為 1)
		input_direction = Input.get_vector("left", "right", "up", "down") 
		
		# --- 技能施放偵測 (Q鍵) ---
		if Input.is_action_just_pressed("skill_01"): 
			# 條件：不能在補血中，且不能處於過熱狀態
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
				var current_buff: float = get_oversaturation_buff() # 抓取目前的傷害倍率
				if use_energy(30): # 嘗試扣除 30 點能量
					skill_01.shoot(current_buff) # 扣除成功，發射技能並傳遞倍率
				else: 
					print("能量不足 30，無法施放 Q 技能！") 
			elif is_overheated: 
				print("系統過熱中！無法釋放技能！") 

		# --- 體力 (SP) 自動恢復邏輯 ---
		if sp_delay_timer > 0:           
			sp_delay_timer -= delta # 還在延遲時間內，繼續倒數      
		else:                            
			if current_sp < max_sp: # 延遲結束且體力未滿，開始回體     
				# 如果處於過熱狀態，回體速度變慢 (10.0)；正常狀態較快 (12.0)
				var regen_rate = 10.0 if is_overheated else 12.0 
				current_sp += regen_rate * delta 
				
				if current_sp > max_sp:  
					current_sp = max_sp # 防呆，防止回血超過上限 
				
				# 過熱解除條件：體力恢復到 70% 以上
				if is_overheated and current_sp >= max_sp * 0.7: 
					is_overheated = false 
					player_hud.set_overheat_visual(false) # 關閉過熱 UI 特效
					print("體力恢復至 70%，解除過熱狀態！") 
					
				player_hud.update_sp(current_sp, max_sp) # 頻繁更新體力 UI

	move_and_slide() # 根據目前的 velocity 執行移動與物理碰撞滑行

# ==========================================
# 體力與能量扣除中心
# ==========================================
func use_sp(amount: float) -> bool: 
	# 嘗試扣除體力。回傳 true 代表扣除成功，false 代表失敗
	if is_overheated: 
		return false # 過熱期間嚴禁花費任何體力

	if current_sp > 0: 
		current_sp -= amount # 只要體力大於 0 就能透支使用
		
		if current_sp < 0: 
			current_sp = 0.0 # 扣成負數則拉平為 0
			
		sp_delay_timer = sp_regen_delay # 每次花費體力，重置回體延遲計時器

		if current_sp <= 0:        
			is_overheated = true # 體力徹底歸零，觸發過熱狀態
			player_hud.set_overheat_visual(true) # 開啟過熱 UI 特效
			print("體力耗盡！進入過熱狀態！") 

		player_hud.update_sp(current_sp, max_sp) # 更新 UI
		return true 
	else: 
		return false # 體力已經是 0，拒絕執行動作

func use_energy(amount: int) -> bool: 
	# 嘗試扣除能量
	if current_energy >= amount: 
		current_energy -= amount 
		if player_hud: player_hud.update_energy(current_energy, max_energy) 
		return true 
	return false 

func add_energy(amount: int): 
	# 增加能量 (如普攻命中獎勵)
	current_energy += amount 
	if current_energy > max_energy: 
		current_energy = max_energy # 防止超過上限
	if player_hud: 
		player_hud.update_energy(current_energy, max_energy) 

# ==========================================
# 傷害倍率與受傷邏輯
# ==========================================
func get_oversaturation_buff() -> float: 
	# 計算目前的「過飽和」傷害倍率
	var multiplier: float = 1.0 
	if current_energy >= max_energy: 
		multiplier = 1.5 # 滿能量時，傷害變為 1.5 倍
		print("【過飽和狀態】發動！目前倍率：1.5 倍") 
	return multiplier 

func handle_hurt(): 
	# 當玩家被怪物的 Hitbox 或子彈打中時呼叫
	var state_name = state_machine.current_state.name.to_lower() 
	
	# 如果玩家處於某些無法被打斷的狀態 (目前保留野豬的邏輯框架，預留給未來擴充霸體)
	if "stun" in state_name or "pant" in state_name: 
		velocity = knockback_force 
		return 
		
	state_machine.change_state("PlayerHurt") # 切換到受傷狀態播放硬直動畫

# ==========================================
# 死亡與視覺更新
# ==========================================
func die(): 
	# 處理死亡狀態切換
	if is_dead: return # 避免重複死亡
	is_dead = true 
	if state_machine: state_machine.change_state("PlayerDie") 

func update_hp_bar(): 
	# 更新 UI 血條與身體顏色
	if player_hud: player_hud.update_hp(current_hp, max_hp) 
	
	# 計算血量百分比 (0.0 ~ 1.0)
	var hp_ratio: float = float(current_hp) / float(max_hp) 
	hp_ratio = max(hp_ratio, 0.0) 
	
	# 根據剩餘血量比例，透過 Shader 慢慢降低玩家精靈圖的色彩飽和度 (快死時會變灰)
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
	
	# 翻滾衝刺時鎖定面向，不跟隨按鍵改變
	if not is_dashing: 
		if input_direction != Vector2.ZERO: 
			# 判斷 X 軸還是 Y 軸的輸入幅度比較大，決定要播橫向還是縱向動畫
			if abs(input_direction.x) > abs(input_direction.y): 
				facing_direction = "right" if input_direction.x > 0 else "left" 
			else: 
				facing_direction = "down" if input_direction.y > 0 else "up" 
				
	anim.play(prefix + "_" + facing_direction) # 組合並播放

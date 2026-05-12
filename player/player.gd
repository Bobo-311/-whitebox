extends BaseCharacter # 繼承自基礎角色類別，獲得血量、死亡等通用功能
class_name Player # 宣告這個腳本代表的肉體，正式歸類為「玩家 (Player)」

# --- 玩家基礎物理數值設定 ---
@export var walk_speed: int = 400          # 設定玩家走路的速度為 400
@export var dash_speed: float = 1500.0     # 設定玩家翻滾衝刺時的瞬間爆發速度為 1500
@export var dash_duration: float = 0.2     # 設定衝刺維持的時間長度為 0.2 秒

# --- 玩家基礎攻擊數值 ---
@export var basic_attack_damage: float = 100.0 # 設定玩家的基礎攻擊力為 5.0

# --- 能量系統數值設定 (EP) ---
@export var max_energy: int = 100 # 設定玩家的能量上限為 100
var current_energy: int = 50      # 設定玩家開局的目前能量為 50

# --- 體力系統數值設定 (SP) ---
@export var max_sp: float = 100.0      # 設定玩家的最大體力上限為 100.0 
var current_sp: float = 50          # 設定玩家開局的目前體力為滿值 100.0
var is_overheated: bool = false        # 宣告狀態開關：記錄玩家現在是否處於「過熱力竭」狀態，預設為否
var sp_regen_delay: float = 0.5        # 設定規則：做出消耗動作後，必須等待 0.5 秒才能開始恢復體力
var sp_delay_timer: float = 0.0        # 宣告隱形計時器：負責倒數這 0.5 秒的等待時間，預設為 0

# --- 狀態紀錄變數 ---
var input_direction: Vector2 = Vector2.ZERO # 宣告變數記錄玩家按下的 WASD 方向向量，預設為零
var facing_direction: String = "down"       # 宣告變數記錄玩家最後面朝的方向，預設為往下看
var is_dashing: bool = false                # 宣告變數記錄玩家現在是否正在衝刺中，預設為否

# --- 抓取場景樹底下的各種子節點 ---
@onready var state_machine: StateMachine = $StateMachine       # 抓取控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 抓取負責播放動畫的精靈圖節點
@onready var player_hud: CanvasLayer = $PlayerHUD              # 抓取畫面左上角的狀態條介面節點
@onready var skill_01: Node2D = $Skill_01                      # 抓取掛在玩家身上的技能發射器節點

# --- 遊戲一開始會執行一次 ---
func _ready(): # 內建函數：當節點進入場景時觸發
	super._ready() # 呼叫父類別的準備函數，將血量補滿
	# 🌟 當玩家出生時，先問大腦：我有存檔座標嗎？
	if DataManager and DataManager.last_save_position != Vector2.ZERO:
		# 將玩家的位置強制設定為存檔點的 Marker2D 座標
		global_position = DataManager.last_save_position
	
	DataManager.player_node = self # 🌟 新增：玩家一出生，立刻把自己的肉體 (self) 註冊到大腦裡！
	
	
	
	if player_hud: # 檢查是否有成功抓取到 UI 介面節點
		player_hud.update_hp(current_hp, max_hp)             # 通知 UI 開局先更新一次血條畫面
		player_hud.update_energy(current_energy, max_energy) # 通知 UI 開局更新一次黃色能量條畫面
		player_hud.update_sp(current_sp, max_sp)             # 通知 UI 開局更新一次綠色體力條畫面
		player_hud.set_overheat_visual(false)                # 開局通知 UI：目前沒有過熱 (綠色體力條、畫面正常)

# --- 每一幀(1/60秒)都會執行的物理更新 ---
func _physics_process(delta: float) -> void: # 內建函數：處理物理運算與按鍵輸入
	if not is_dead: # 條件判斷：只有在玩家「還活著」的情況下，才允許接收輸入
		input_direction = Input.get_vector("left", "right", "up", "down") # 抓取玩家按鍵的上下左右移動方向
		
		# 偵測釋放技能 (Q鍵)
		if Input.is_action_just_pressed("skill_01"): # 檢查玩家是否在這一幀按下了技能鍵
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: # 條件：不能在補血，且不能過熱
				var current_buff: float = get_oversaturation_buff() # 拍下當下的過飽和倍率快照並儲存
				if use_energy(30): # 呼叫函數申請扣除 30 點能量 (如果成功回傳 true)
					skill_01.shoot(current_buff) # 呼叫發射器發射技能，並將倍率包裹傳遞過去
				else: # 如果能量扣除失敗 (不足 30)
					print("能量不足 30，無法施放 Q 技能！") # 在後台印出警告
			elif is_overheated: # 如果玩家處於過熱狀態
				print("系統過熱中！無法釋放技能！") # 在後台印出警告

		# --- 體力恢復與過熱解除邏輯 ---
		if sp_delay_timer > 0:           # 檢查體力延遲計時器是否還大於 0 (剛做完耗體力動作)
			sp_delay_timer -= delta      # 將計時器扣除這一幀經過的時間，繼續倒數
		else:                            # 如果計時器已經歸零 (等待 0.5 秒期結束)
			if current_sp < max_sp:      # 檢查目前體力是否還沒回滿
				var regen_rate = 10.0 if is_overheated else 12.0 # 決定回體速度：過熱時為 10，正常時為 12
				current_sp += regen_rate * delta # 將目前體力加上這幀該回的量
				
				if current_sp > max_sp:  # 防呆檢查：如果體力恢復超過了最大上限
					current_sp = max_sp  # 強制將體力鎖定在最大上限數值
				
				# 核心規則：檢查過熱解除條件 (恢復到 70% 解除)
				if is_overheated and current_sp >= max_sp * 0.7: # 如果正在過熱，且體力已經大於等於 70%
					is_overheated = false # 將過熱開關關閉，正式解除過熱狀態
					player_hud.set_overheat_visual(false) # 通知 UI：解除過熱特效 (綠條、畫面亮)
					print("體力恢復至 70%，解除過熱狀態！") # 後台印出解除提示
					
				player_hud.update_sp(current_sp, max_sp) # 通知 UI 即時更新體力條進度

	move_and_slide() # 呼叫內建物理函數處理移動與撞牆滑行

# --- 體力結帳中心：花費體力的專屬函數 ---
func use_sp(amount: float) -> bool: # 自訂函數：接收要扣除的體力量，回傳是否成功
	if is_overheated: # 檢查是否處於過熱狀態 
		return false # 第一道鎖：如果過熱，直接回傳失敗拒絕動作

	if current_sp > 0: # 只要體力大於 0 (哪怕只有 1 點)，都准許玩家「透支」執行動作
		current_sp -= amount # 執行扣款
		
		# 🌟 新增防呆：絕對不允許出現負數
		if current_sp < 0: # 如果扣除後體力跌破 0 變成負數
			current_sp = 0.0 # 強制把它拉平到剛好 0.0
			
		sp_delay_timer = sp_regen_delay # 將恢復延遲計時器重置為 0.5 秒，打斷回體過程

		if current_sp <= 0:        # 檢查扣除體力後，體力是否歸零 (觸發力竭)
			is_overheated = true   # 將過熱開關打開，正式觸發過熱力竭狀態！
			player_hud.set_overheat_visual(true) # 通知 UI：啟動過熱特效 (粉色條，畫面暗)
			print("體力耗盡！進入過熱狀態！") # 後台印出體力耗盡警告

		player_hud.update_sp(current_sp, max_sp) # 通知 UI 更新最新體力
		return true # 交易成功，准許玩家的動作腳本繼續執行
	else: # 如果體力已經是 0，連透支都無法
		return false # 回傳失敗，拒絕動作

# --- Buff 發放中心 ---
func get_oversaturation_buff() -> float: # 自訂函數：回傳目前的傷害倍率
	var multiplier: float = 1.0 # 設定預設倍率為 1.0 倍
	if current_energy >= max_energy: # 檢查是否滿能量
		multiplier = 1.5 # 滿能量改為 1.5 倍
		print("【過飽和狀態】發動！目前倍率：1.5 倍") # 後台提示
	return multiplier # 回傳倍率

# --- 受傷切換邏輯 ---
func handle_hurt(): # 實作父類別規定的受傷函數
	var state_name = state_machine.current_state.name.to_lower() # 【特殊函數】將目前狀態名轉為全小寫，防止大小寫拼寫錯誤
	
	# 🌟 破綻鎖定機制：如果野豬正處於暈眩或喘氣狀態
	if "stun" in state_name or "pant" in state_name: # 檢查小寫狀態名中是否包含 stun 或 pant
		velocity = knockback_force # 依然賦予擊退力道，保持打擊感
		return # 🌟 直接跳出函數！不呼叫 change_state，所以野豬原本的動畫不會被中斷
		
	state_machine.change_state("PlayerHurt") # 如果不是在破綻期間，才正常切換到受傷狀態

# --- 增加與花費能量 ---
func add_energy(amount: int): # 自訂函數：增加能量
	current_energy += amount # 增加能量
	if current_energy > max_energy: current_energy = max_energy # 防呆超過上限
	if player_hud: player_hud.update_energy(current_energy, max_energy) # 更新 UI

func use_energy(amount: int) -> bool: # 自訂函數：花費能量
	if current_energy >= amount: # 檢查能量是否足夠
		current_energy -= amount # 扣除
		if player_hud: player_hud.update_energy(current_energy, max_energy) # 更新 UI
		return true # 成功
	return false # 失敗

# --- 死亡與更新血條邏輯 ---
func die(): # 實作死亡函數
	if is_dead: return # 已死就跳出
	is_dead = true # 標記死亡
	if state_machine: state_machine.change_state("PlayerDie") # 切換死亡狀態

func update_hp_bar(): # 實作更新血條函數
	if player_hud: player_hud.update_hp(current_hp, max_hp) # 更新紅血條
	var hp_ratio: float = float(current_hp) / float(max_hp) # 計算剩餘血量比例
	hp_ratio = max(hp_ratio, 0.0) # 確保比例不是負數
	if animated_sprite_2d.material: # 檢查著色器材質
		var tween = get_tree().create_tween() # 建立動畫效果
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) # 隨血量降低飽和度

# --- 動畫播放控制器 ---
func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO): # 自訂函數：播放動畫
	var anim = get_node_or_null("AnimatedSprite2D") # 抓取動畫播放節點
	if anim == null: return # 沒抓到就跳出
	if not is_dashing: # 檢查是否不在衝刺狀態 (衝刺鎖定轉向)
		if input_direction != Vector2.ZERO: # 檢查是否有輸入方向
			if abs(input_direction.x) > abs(input_direction.y): # 比較 X Y 軸輸入決定橫向或縱向優先
				facing_direction = "right" if input_direction.x > 0 else "left" # X軸判斷面朝左右
			else: 
				facing_direction = "down" if input_direction.y > 0 else "up" # Y軸判斷面朝上下
	anim.play(prefix + "_" + facing_direction) # 組合前綴與面朝方向，播放對應動畫

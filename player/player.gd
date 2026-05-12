extends BaseCharacter # 繼承自基礎角色類別，獲得血量、死亡等通用功能
class_name Player # 宣告這個腳本代表的肉體，正式歸類為「玩家 (Player)」

# --- 玩家基礎物理數值設定 ---
@export var walk_speed: int = 400          # 設定玩家走路的速度為 400
@export var dash_speed: float = 1500.0     # 設定玩家翻滾衝刺時的瞬間爆發速度為 1500
@export var dash_duration: float = 0.2     # 設定衝刺維持的時間長度為 0.2 秒

# --- 玩家基礎攻擊數值 ---
@export var basic_attack_damage: float = 100.0 # 設定玩家的基礎攻擊力為 100.0

# --- 能量系統數值設定 (EP) ---
@export var max_energy: int = 100 # 設定玩家的能量上限為 100
var current_energy: int = 50      # 設定玩家開局的目前能量為 50

# --- 體力系統數值設定 (SP) ---
@export var max_sp: float = 100.0      # 設定玩家的最大體力上限為 100.0 
var current_sp: float = 50          # 設定玩家開局的目前體力為 50
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
	
	DataManager.player_node = self # 玩家一出生，立刻把自己的肉體 (self) 註冊到大腦裡
	
	if DataManager and DataManager.last_save_position != Vector2.ZERO: # 檢查大腦是否有存檔座標
		global_position = DataManager.last_save_position # 將玩家的位置強制設定為存檔點的座標
		
	if DataManager and DataManager.saved_hp > 0: # 檢查大腦是否有存過檔的滿血小抄
		current_hp = DataManager.saved_hp # 領回存檔時的血量
		current_energy = DataManager.saved_energy # 領回存檔時的能量
		current_sp = DataManager.saved_sp # 領回存檔時的體力
	else: # 如果是第一次開遊戲
		current_energy = 50 # 預設能量 50
		current_sp = 50 # 預設體力 50
		
	if player_hud: # 檢查是否有成功抓取到 UI 介面節點
		player_hud.update_hp(current_hp, max_hp)             # 通知 UI 更新血條畫面
		player_hud.update_energy(current_energy, max_energy) # 通知 UI 更新黃色能量條畫面
		player_hud.update_sp(current_sp, max_sp)             # 通知 UI 更新綠色體力條畫面
		player_hud.set_overheat_visual(false)                # 開局通知 UI：目前沒有過熱
		
	if animated_sprite_2d.material: # 檢查是否有材質著色器
		animated_sprite_2d.material.set_shader_parameter("saturation", 1.0) # 強制把飽和度洗回 1.0 (全彩)
		
	# 🌟 復活後檢查大腦：有沒有遺留的靈魂要生出來？
	if DataManager and DataManager.has_soul_on_ground: # 如果大腦記錄有掉落靈魂
		var soul_scene = load("res://soul/Soul.tscn") # 載入靈魂場景檔案
		if soul_scene: # 確保有載入成功
			var soul = soul_scene.instantiate() # 實例化靈魂
			soul.global_position = DataManager.soul_spawn_pos # 放在大腦紀錄的死亡座標
			soul.lost_gold = DataManager.soul_stored_gold # 塞入大腦紀錄的掉落金幣
			soul.scale = Vector2(2.0, 2.0) # 將靈魂放大 2 倍，解決太小的問題
			get_tree().current_scene.call_deferred("add_child", soul) # 延遲加入到當前關卡底層

# --- 每一幀(1/60秒)都會執行的物理更新 ---
func _physics_process(delta: float) -> void: # 內建函數：處理物理運算與按鍵輸入
	if not is_dead: # 只有在玩家「還活著」的情況下，才允許接收輸入
		input_direction = Input.get_vector("left", "right", "up", "down") # 抓取玩家按鍵的上下左右移動方向
		
		if Input.is_action_just_pressed("skill_01"): # 檢查玩家是否在這一幀按下了技能鍵
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: # 條件：不能在補血，且不能過熱
				var current_buff: float = get_oversaturation_buff() # 拍下當下的過飽和倍率快照
				if use_energy(30): # 呼叫函數申請扣除 30 點能量
					skill_01.shoot(current_buff) # 發射技能並傳遞倍率
				else: # 如果能量不足
					print("能量不足 30，無法施放 Q 技能！") # 後台警告
			elif is_overheated: # 如果處於過熱狀態
				print("系統過熱中！無法釋放技能！") # 後台警告

		# --- 體力恢復與過熱解除邏輯 ---
		if sp_delay_timer > 0:           # 檢查體力延遲計時器是否還大於 0
			sp_delay_timer -= delta      # 扣除這幀經過的時間
		else:                            # 如果計時器歸零
			if current_sp < max_sp:      # 檢查目前體力是否沒回滿
				var regen_rate = 10.0 if is_overheated else 12.0 # 決定回體速度
				current_sp += regen_rate * delta # 加上這幀該回的量
				
				if current_sp > max_sp:  # 如果恢復超過上限
					current_sp = max_sp  # 強制鎖定在最大上限
				
				if is_overheated and current_sp >= max_sp * 0.7: # 如果過熱且體力大於等於 70%
					is_overheated = false # 解除過熱狀態
					player_hud.set_overheat_visual(false) # 取消過熱特效
					print("體力恢復至 70%，解除過熱狀態！") # 後台提示
					
				player_hud.update_sp(current_sp, max_sp) # 通知 UI 更新體力條

	move_and_slide() # 呼叫內建物理函數處理移動與滑行

# --- 體力結帳中心：花費體力的專屬函數 ---
func use_sp(amount: float) -> bool: # 自訂函數：接收要扣除的體力量，回傳是否成功
	if is_overheated: # 檢查是否處於過熱狀態 
		return false # 過熱直接回傳失敗

	if current_sp > 0: # 只要體力大於 0，准許透支
		current_sp -= amount # 執行扣款
		
		if current_sp < 0: # 如果扣除後變成負數
			current_sp = 0.0 # 強制拉平到 0.0
			
		sp_delay_timer = sp_regen_delay # 重置恢復延遲計時器，打斷回體

		if current_sp <= 0:        # 檢查扣除體力後是否歸零
			is_overheated = true   # 觸發過熱力竭狀態
			player_hud.set_overheat_visual(true) # 啟動過熱特效
			print("體力耗盡！進入過熱狀態！") # 後台警告

		player_hud.update_sp(current_sp, max_sp) # 更新最新體力
		return true # 交易成功
	else: # 如果體力已經是 0
		return false # 回傳失敗

# --- Buff 發放中心 ---
func get_oversaturation_buff() -> float: # 自訂函數：回傳目前的傷害倍率
	var multiplier: float = 1.0 # 設定預設倍率為 1.0 倍
	if current_energy >= max_energy: # 檢查是否滿能量
		multiplier = 1.5 # 滿能量改為 1.5 倍
		print("【過飽和狀態】發動！目前倍率：1.5 倍") # 後台提示
	return multiplier # 回傳倍率

# --- 受傷切換邏輯 ---
func handle_hurt(): # 實作受傷函數
	var state_name = state_machine.current_state.name.to_lower() # 將目前狀態名轉為小寫
	
	if "stun" in state_name or "pant" in state_name: # 如果野豬處於暈眩或喘氣破綻
		velocity = knockback_force # 依然賦予擊退力道
		return # 直接跳出，不中斷破綻動畫
		
	state_machine.change_state("PlayerHurt") # 正常切換到受傷狀態

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
	if not is_dashing: # 檢查是否不在衝刺狀態
		if input_direction != Vector2.ZERO: # 檢查是否有輸入方向
			if abs(input_direction.x) > abs(input_direction.y): # 比較 X Y 軸輸入決定橫向或縱向優先
				facing_direction = "right" if input_direction.x > 0 else "left" # X軸判斷面朝左右
			else: 
				facing_direction = "down" if input_direction.y > 0 else "up" # Y軸判斷面朝上下
	anim.play(prefix + "_" + facing_direction) # 組合前綴與面朝方向播放動畫

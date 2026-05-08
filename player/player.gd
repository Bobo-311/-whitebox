extends BaseCharacter # 繼承自基礎角色類別，獲得血量、死亡等通用功能
class_name Player # 宣告這個腳本代表的肉體，正式歸類為「玩家 (Player)」

# --- 玩家基礎物理數值設定 ---
@export var walk_speed: int = 400          # 設定玩家走路的速度為 400
@export var dash_speed: float = 1500.0     # 設定玩家翻滾衝刺時的瞬間爆發速度為 1500
@export var dash_duration: float = 0.2     # 設定衝刺維持的時間長度為 0.2 秒

# --- 🌟 玩家基礎攻擊數值 ---
@export var basic_attack_damage: float = 5.0 # 設定玩家的基礎攻擊力為 5.0

# --- 🌟 能量系統數值設定 (EP) ---
@export var max_energy: int = 100 # 設定玩家的能量上限為 100
var current_energy: int = 50      # 設定玩家開局的目前能量為 50

# --- 🌟 體力系統數值設定 (SP) ---
@export var max_sp: float = 7.0      # 🌟 設定玩家的最大體力上限為 100.0 (配合你的修改)
var current_sp: float = 7.0          # 🌟 設定玩家開局的目前體力為滿值 100.0
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
	super._ready() # 呼叫父類別 (BaseCharacter) 的準備函數，將血量補滿
	if player_hud: # 檢查是否有成功抓取到 UI 介面節點
		player_hud.update_hp(current_hp, max_hp)             # 通知 UI 開局先更新一次血條畫面
		player_hud.update_energy(current_energy, max_energy) # 通知 UI 開局更新一次黃色能量條畫面
		player_hud.update_sp(current_sp, max_sp)             # 通知 UI 開局更新一次綠色體力條畫面
		player_hud.set_overheat_visual(false)                # 🌟 開局通知 UI：目前沒有過熱 (綠色體力條、畫面正常)

# --- 每一幀(1/60秒)都會執行的物理更新 ---
func _physics_process(delta: float) -> void: # 內建函數：處理物理運算與按鍵輸入
	if not is_dead: # 條件判斷：只有在玩家「還活著」的情況下，才允許接收輸入
		input_direction = Input.get_vector("left", "right", "up", "down") # 抓取玩家按鍵的上下左右移動方向
		
		# 🌟 偵測釋放技能 (Q鍵)
		if Input.is_action_just_pressed("skill_01"): # 檢查玩家是否在這一幀按下了技能鍵
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: # 條件判斷：不能在補血，且不能處於過熱狀態
				var current_buff: float = get_oversaturation_buff() # 呼叫函數，拍下當下的過飽和倍率快照並儲存
				if use_energy(30): # 呼叫函數申請扣除 30 點能量 (如果成功回傳 true)
					skill_01.shoot(current_buff) # 呼叫發射器發射技能，並將倍率包裹傳遞過去
				else: # 如果能量扣除失敗 (不足 30)
					print("能量不足 30，無法施放 Q 技能！") # 在後台印出能量不足的警告
			elif is_overheated: # 如果條件不符是因為玩家處於過熱狀態
				print("系統過熱中！無法釋放技能！") # 在後台印出過熱無法施放的警告

		# --- 🌟 體力恢復與過熱解除邏輯 ---
		if sp_delay_timer > 0:           # 檢查體力延遲計時器是否還大於 0 (剛做完耗體力動作)
			sp_delay_timer -= delta      # 將計時器扣除這一幀經過的時間，繼續倒數
		else:                            # 如果計時器已經歸零 (等待 0.5 秒期結束)
			if current_sp < max_sp:      # 檢查目前體力是否還沒回滿
				var regen_rate = 10.0 if is_overheated else 12.0 # 宣告變數決定回體速度：過熱時為 10，正常時為 12
				current_sp += regen_rate * delta # 將目前體力加上 (回體速度乘以一幀的時間)
				
				if current_sp > max_sp:  # 防呆檢查：如果體力恢復後超過了最大上限
					current_sp = max_sp  # 強制將體力鎖定在最大上限數值
				
				# 🌟 核心規則：檢查過熱解除條件 (必須恢復到 70% 才會解除)
				if is_overheated and current_sp >= max_sp * 0.7: # 如果正在過熱，且體力已經恢復大於或等於 70%
					is_overheated = false # 將過熱開關關閉，正式解除過熱狀態！此時玩家可以再次攻擊與翻滾！
					player_hud.set_overheat_visual(false) # 🌟 通知 UI：解除過熱特效 (體力條變回綠色、畫面恢復正常彩色)
					print("體力恢復至 70%，解除過熱狀態！") # 在後台印出解除過熱的提示
					
				player_hud.update_sp(current_sp, max_sp) # 通知 UI 即時更新體力條的長度進度

	move_and_slide() # 呼叫內建物理函數：根據速度讓玩家移動，並自動處理撞牆滑行

# --- 🌟 體力結帳中心：花費體力的專屬函數 ---
func use_sp(amount: float) -> bool: # 自訂函數：接收要扣除的體力量，並回傳是否扣除成功 (布林值)
	if is_overheated: # 🌟 檢查是否處於過熱狀態 (如果體力還沒恢復到 70%)
		return false # 如果過熱，直接回傳失敗，這會讓玩家無法執行砍擊和 DASH

	if current_sp >= amount:       # 檢查目前的體力是否大於或等於要求扣除的量 (例如 7 點)
		current_sp -= amount       # 將目前體力扣除該數值
		sp_delay_timer = sp_regen_delay # 將恢復延遲計時器重置為 0.5 秒，打斷回體過程

		if current_sp <= 0:        # 🌟 檢查扣除體力後，體力是否小於或等於 0 (也就是 0% 體力條)
			current_sp = 0         # 強制將體力鎖定在 0，防止出現負數
			is_overheated = true   # 將過熱開關打開，正式觸發過熱力竭狀態！
			player_hud.set_overheat_visual(true) # 🌟 通知 UI：啟動過熱特效 (體力條變為粉色，畫面變灰暗)
			print("體力耗盡！進入過熱狀態！") # 在後台印出體力耗盡的警告

		player_hud.update_sp(current_sp, max_sp) # 通知 UI 更新扣除後的體力條進度
		return true                # 回傳成功，准許玩家的動作腳本繼續執行 (如播放砍擊動畫)
	else: # 如果目前的體力不夠支付扣款
		return false               # 回傳失敗，拒絕玩家的動作

# --- Buff 發放中心 (檢查是否處於過飽和狀態) ---
func get_oversaturation_buff() -> float: # 自訂函數：計算並回傳目前的傷害倍率
	var multiplier: float = 1.0 # 宣告變數設定預設倍率為 1.0 倍 (無增傷)
	if current_energy >= max_energy: # 檢查目前能量是否大於或等於最大能量 (是否滿能量)
		multiplier = 1.5             # 如果滿能量，將倍率修改為 1.5 倍
		print("【過飽和狀態】發動！目前倍率：1.5 倍") # 在後台印出觸發過飽和的提示字眼
	return multiplier # 將最終決定好的倍率數值回傳

# --- 受傷切換邏輯 ---
func handle_hurt(): # 實作父類別規定的受傷函數
	state_machine.change_state("PlayerHurt") # 命令大腦切換到玩家受傷狀態

# --- 增加能量 ---
func add_energy(amount: int): # 自訂函數：接收並增加能量
	current_energy += amount # 將目前能量加上獲得的數量
	if current_energy > max_energy: # 檢查能量是否超過上限
		current_energy = max_energy # 若超過則強制鎖定為最大上限
	if player_hud: # 檢查是否有 UI 節點
		player_hud.update_energy(current_energy, max_energy) # 通知 UI 更新能量條畫面

# --- 花費能量 ---
func use_energy(amount: int) -> bool: # 自訂函數：接收要扣除的能量，回傳是否成功
	if current_energy >= amount: # 檢查目前能量是否足夠支付
		current_energy -= amount # 將能量扣除
		if player_hud: # 檢查是否有 UI 節點
			player_hud.update_energy(current_energy, max_energy) # 通知 UI 更新扣除後的能量條
		return true # 交易成功，回傳 true
	return false # 交易失敗，回傳 false

# --- 死亡邏輯 ---
func die(): # 實作父類別規定的死亡函數
	if is_dead: # 檢查是否已經處於死亡狀態
		return # 如果已死則直接跳出，避免重複執行
	is_dead = true # 將死亡標記設為 true
	if state_machine: # 檢查大腦節點是否存在
		state_machine.change_state("PlayerDie") # 命令大腦切換到玩家死亡狀態

# --- 更新血條與視覺褪色 ---
func update_hp_bar(): # 實作父類別規定的更新血條函數
	if player_hud: # 檢查 UI 節點是否存在
		player_hud.update_hp(current_hp, max_hp) # 通知 UI 更新紅血條數值
	var hp_ratio: float = float(current_hp) / float(max_hp) # 計算目前剩餘血量的百分比小數
	hp_ratio = max(hp_ratio, 0.0) # 確保血量比例最小為 0.0，不會變成負數
	if animated_sprite_2d.material: # 檢查玩家圖片是否有掛載著色器材質
		var tween = get_tree().create_tween() # 建立一個新的動畫過渡效果
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) # 讓玩家顏色的飽和度在 0.3 秒內隨血量比例降低

# --- 動畫播放控制器 ---
func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO): # 自訂函數：負責組合字串並播放對應動畫
	var anim = get_node_or_null("AnimatedSprite2D") # 抓取動畫播放節點
	if anim == null: # 如果沒抓到節點
		return # 直接跳出函數
	if not is_dashing: # 檢查玩家是否「不在」衝刺狀態中 (衝刺時鎖定轉向)
		if input_direction != Vector2.ZERO: # 檢查玩家是否正在輸入方向鍵
			if abs(input_direction.x) > abs(input_direction.y): # 比較 X 軸與 Y 軸的輸入大小，決定橫向還是縱向優先
				facing_direction = "right" if input_direction.x > 0 else "left" # X大於0面朝右，否則面朝左
			else: # 如果 Y 軸輸入較大
				facing_direction = "down" if input_direction.y > 0 else "up" # Y大於0面朝下，否則面朝上
	anim.play(prefix + "_" + facing_direction) # 組合傳入的動作前綴與算出的方向後綴，播放該動畫

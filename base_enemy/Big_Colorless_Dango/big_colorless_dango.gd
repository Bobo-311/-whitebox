extends BaseEnemy
class_name BigDango

# ==========================================
# ⚙️ Boss 專屬配置與鎖血設定
# ==========================================
@export_category("💣 Boss 鎖血與召喚設定")
@export var minion_scene: PackedScene # 從 Inspector 放入要吐出來的小怪(藍色團子)場景

var hp_thresholds: Array[float] = [0.8, 0.6, 0.4, 0.2] # 企劃設定：四次鎖血反擊的血量百分比
var current_phase_index: int = 0 # 記錄目前打到第幾個階段了
var is_invincible: bool = false  # Boss 專屬無敵開關 (紫光時會被開啟)

# ==========================================
# 🚀 開局初始化 (強制喚醒與霸體)
# ==========================================
func _ready() -> void:
	super._ready() # 讓老爸先跑完基礎的變數綁定
	
	# 🌟【根除滑行 (絕對霸體)】
	# 利用你寫好的 KnockbackComponent，把「抗性(resistance)」設為 0。
	# 這樣底層收到擊退力道時會自動 return，再也不會往後滑行！
	if knockback_component:
		knockback_component.resistance = 0.0
		
	# 延遲 1 幀呼叫喚醒函數，確保場景與玩家都已經載入完畢，避免開局抓不到人
	call_deferred("_wake_up_boss")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# 🌟【大腦偵錯器】：每秒印出牠現在到底在想什麼？速度是多少？
	if state_machine and state_machine.current_state:
		print("🧠 目前狀態: ", state_machine.current_state.name, " | 🏃 物理速度: ", velocity)

func _wake_up_boss() -> void:
	# 確保 DataManager 裡面已經有玩家的實體
	if DataManager and DataManager.player_node:
		player_node = DataManager.player_node
		can_see_player = true # Boss 戰專屬：給予全圖視野，不用等雷達掃描
		
		# 🌟【強制啟動】一出生直接踹醒，進入設定好的風箏/移動模式！
		if state_machine:
			state_machine.change_state("move")

# ==========================================
# 🛡️ 傷害攔截系統 (覆寫老爸的邏輯)
# ==========================================
func handle_hurt() -> void:
	pass # 正規做法：故意留空。讓 Boss 被打時只會閃白光，動作絕對不會被打斷 (硬直)。

func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	# 1. 如果正在紫光無敵，或已經死了，直接沒收傷害
	if is_invincible or is_dead: 
		return 
		
	# 2. 讓老爸去處理正常的扣血與閃白光
	# (額外擊退力 extra_knockback 強制傳 0.0，配合霸體)
	super.take_damage(amount, attacker_pos, dir, is_melee, 0.0)
	
	# 3. 扣完血後，檢查有沒有低於鎖血門檻
	_check_hp_threshold()

# ==========================================
# 🩸 技能階段轉換與死亡控制
# ==========================================
func _check_hp_threshold() -> void:
	# 如果四個階段都放完招了，或者王已經死了，就不做事
	if current_phase_index >= hp_thresholds.size() or is_dead: 
		return 
		
	# 計算目前的血量百分比 (例如 0.75)
	var hp_ratio = float(current_hp) / float(max_hp)
	
	# 如果當前血量低於設定的門檻 (例如 80% / 0.8)
	if hp_ratio <= hp_thresholds[current_phase_index]:
		current_phase_index += 1 # 推進到下一階段，防止重複觸發
		
		# 強制大腦中斷目前的動作，進入「鎖血召喚」狀態 (紫光無敵)
		if state_machine:
			state_machine.change_state("LockHpSpawn")

func die() -> void:
	if is_dead: return
	is_dead = true
	
	# 攔截老爸的普通死法，改為切換到 Boss 專屬的「自爆預警」狀態
	if state_machine:
		state_machine.change_state("Die")
		
	drop_coin() # 噴出金幣

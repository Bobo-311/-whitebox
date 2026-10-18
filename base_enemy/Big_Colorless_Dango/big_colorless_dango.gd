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

# -------------------------------------------------------------------------
# 🩸 技能階段轉換與血量監控 (覆寫或更新 BigDango.gd 中的這段邏輯)
# -------------------------------------------------------------------------
func _check_hp_threshold() -> void:
	# [防呆機制]：如果所有階段都已經放完，或者王已經死亡，直接中斷不處理
	if current_phase_index >= hp_thresholds.size() or is_dead: 
		return 
		
	# 計算目前的血量百分比 (例如 0.75)
	var hp_ratio = float(current_hp) / float(max_hp)
	
	# 如果當前血量低於等於目前門檻陣列裡的數值
	if hp_ratio <= hp_thresholds[current_phase_index]:
		current_phase_index += 1 # 推進階段索引，確保下一次檢查下一個門檻
		
		# 強制大腦中斷目前的行動，進入鎖血爆開與縮水狀態
		if state_machine:
			state_machine.change_state("LockHpSpawn")

# ==========================================
# 🎭 單面 Boss 動畫轉接器 (加在 BigDango.gd 最下方)
# ==========================================
# 【正規作法】：覆寫底層的四向動畫邏輯，將大團子轉接為單面動畫與左右移動
func play_animation(anim_name: String, dir: Vector2 = Vector2.ZERO) -> void:
	# 防呆檢查：確保動畫節點與圖庫已經載入
	if not animated_sprite_2d or not animated_sprite_2d.sprite_frames:
		return
		
	var target_anim = anim_name
	
	# 1. 移動方向判定：大團子移動只分左右，根據實際物理速度或目標方向的 X 軸切換
	if anim_name == "move":
		var check_x = velocity.x if abs(velocity.x) > 1.0 else dir.x
		target_anim = "move_left" if check_x < 0 else "move_right"
		
	# 2. 播放單面動畫：只要圖庫中有對應名稱 (如 idle, attack, roar, bomb)，直接播放
	if animated_sprite_2d.sprite_frames.has_animation(target_anim):
		# 避免在同一狀態下每幀重複重播第 0 幀，只有切換動作或動畫停下時才執行 play
		if animated_sprite_2d.animation != target_anim or not animated_sprite_2d.is_playing():
			animated_sprite_2d.play(target_anim)
	else:
		# 防呆降級：若找不到單面動畫名稱，才退回底層預設的四向邏輯
		super.play_animation(anim_name, dir)



func die() -> void:
	if is_dead: return
	is_dead = true
	
	# 攔截老爸的普通死法，改為切換到 Boss 專屬的「自爆預警」狀態
	if state_machine:
		state_machine.change_state("Die")
		
	drop_coin() # 噴出金幣

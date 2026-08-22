extends State # 繼承自狀態模板，代表這是大腦裡的一個狀態節點

# ==========================================
# ⚙️ 揮刀節奏設定 (可在屬性面板自由調整，調出手感)
# ==========================================
@export_category("揮刀節奏設定")
@export var windup_time: float = 0.4    # 【前搖】舉刀時間：數字越大，怪物舉刀越久，給玩家反應的時間越多
@export var active_time: float = 0.3    # 【判定】刀光時間：碰撞框(Hitbox)開啟並產生傷害的持續時間
@export var recovery_time: float = 0.4  # 【後搖】收刀時間：砍完後原地發呆喘息的時間，給玩家反擊的機會

var is_attacking: bool = false # 攻擊鎖定開關：防止在攻擊中途又重複觸發攻擊

# ==========================================
# 🚀 狀態進入時執行 (Enter)
# ==========================================
func enter():
	is_attacking = true # 鎖定狀態：告訴系統「我正在攻擊中，不要吵我」
	character.velocity = Vector2.ZERO # 物理煞車：揮刀時強制原地站死，避免滑步
	_perform_attack() # 呼叫並開始執行完整的揮刀流程

# ==========================================
# 🗡️ 核心攻擊流程 (前搖 -> 判定 -> 後搖)
# ==========================================
func _perform_attack():
	# 1️⃣ 【計算面朝方向】
	var dir_str = "down" # 預設字串為往下
	var dir_vec = character.last_facing_vec # 取得老爸記憶中的最後面朝方向 (Vector2)
	
	# 判斷 X 軸與 Y 軸哪個分量比較大，來決定是上下還是左右
	if abs(dir_vec.x) > abs(dir_vec.y):
		dir_str = "right" if dir_vec.x > 0 else "left"
	else:
		dir_str = "down" if dir_vec.y > 0 else "up"

	# 2️⃣ 【播放動畫】
	# 呼叫老爸的播放動畫功能，它會自動把 "attack" 跟算出來的方向 (例如 "_right") 組合起來
	character.play_animation("attack", dir_vec)
	
	# 3️⃣ 【抓取對應方向的 Hitbox 節點】
	# 用字串組合出精準的名稱 (例如 "Hitbox/CollisionShape_down") 並抓取那個膠囊框
	var target_hitbox = character.get_node_or_null("Hitbox/CollisionShape_" + dir_str)
	var hitbox_area = character.get_node_or_null("Hitbox")
	
	# ⏳ === 【階段一：前搖 (Wind-up)】 === ⏳
	# 怪物高舉武器，此時 Hitbox 是關閉的，不會有傷害。等待設定的前搖時間。
	await character.get_tree().create_timer(windup_time).timeout
	if character.is_dead or state_machine.current_state != self: return
	
	# 💥 === 【階段二：傷害判定 (Active)】 === 💥
	if target_hitbox and hitbox_area:
		hitbox_area.monitoring = true      # 打開 Area2D 的雷達感應
		target_hitbox.disabled = false     # 瞬間取消 Disabled 勾選，膠囊框實體化！(碰到玩家就扣血)
		
		# 維持這個具有傷害的刀光判定一段時間
		await character.get_tree().create_timer(active_time).timeout
		# 🚨【關鍵防呆】：判定結束後也要檢查
		if state_machine.current_state != self: return
		
		# 💨 === 【階段三：後搖 (Recovery)】 === 💨
		target_hitbox.disabled = true      # 傷害時間結束，趕快把膠囊框關閉 (打勾 Disabled)
		hitbox_area.monitoring = false     # 關閉 Area2D 感應雷達，避免誤判
		
	# ⏳ 等待收刀動作做完、喘息一下 (後搖時間)
	await character.get_tree().create_timer(recovery_time).timeout
	
	# 🔄 === 【攻擊結束，交還大腦控制權】 === 🔄
	is_attacking = false # 解除攻擊鎖定
	
	# 如果揮完刀怪物還活著，就切換回「追擊(Chase)」狀態，準備下一波走位或攻擊
	if not character.is_dead:
		state_machine.change_state("Chase")

# ==========================================
# ⏱️ 每一幀的物理更新 (Physics Update)
# ==========================================
func state_physics_update(_delta: float):
	# 刻意留空 (pass)
	# 因為在攻擊期間，我們不希望怪物可以移動或做其他思考
	# 所有動作都交給 _perform_attack() 裡的 await (等待) 來掌控節奏
	pass
# 🚨【新增】：如果狀態被外力強制中斷 (例如被打進二階)，安全關閉所有雷達與碰撞框
func exit():
	is_attacking = false
	var hitbox_area = character.get_node_or_null("Hitbox")
	if hitbox_area:
		hitbox_area.monitoring = false
		for child in hitbox_area.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)

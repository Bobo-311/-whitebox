extends BaseEnemy 

# ==========================================
# ⚙️ 可以在右邊 Inspector 面板自由調整的數值！
# ==========================================
@export_category("野蠻人一階設定")
@export var stage1_max_hp: float = 100.0     # 第一階段血量
@export var stage1_walk_speed: float = 80.0  # 第一階段走速
@export var stage1_damage: float = 50.0      # 第一階段傷害

@export_category("野蠻人鎖血設定")
@export var berserk_hp_threshold: float = 1.0 # 致命傷鎖血點 (鎖在 1 滴)

var is_berserk: bool = false # 狀態開關：記住他是不是已經狂暴過了

func _ready() -> void:
	# 將你在面板上設定的數值，灌入老爸的變數中
	max_hp = stage1_max_hp
	current_hp = stage1_max_hp
	walk_speed = stage1_walk_speed
	melee_damage = stage1_damage
	
	# 呼叫老爸的 _ready，啟動血條與大腦
	super._ready() 

# 🌟🌟🌟【核心覆寫】攔截受傷邏輯，加入鎖血機制 🌟🌟🌟
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	if is_dead: return 
	
	# 如果正在「狂暴變身中」，霸體無敵，完全不受傷！
	if state_machine and state_machine.current_state and state_machine.current_state.name == "BerserkTransition":
		print("野蠻人變身中，免疫傷害！")
		return

	# 先計算這刀砍下去剩多少血
	var simulated_hp = current_hp - amount

	# 🌟【鎖血判定】：如果這刀會砍死他，且他「還沒狂暴過」
	if simulated_hp <= 0 and not is_berserk:
		print("🔥 野蠻人受到致命傷！觸發二階鎖血狂暴！🔥")
		is_berserk = true                 # 標記為已狂暴
		current_hp = berserk_hp_threshold # 強制鎖血
		
		# 🌟 完美呼叫老爸的函數來更新血條和閃紅光！
		update_hp_bar()       
		
		# 🌟【新增這行】強制速度歸零，打斷他原本可能在進行的動作！
		velocity = Vector2.ZERO
		
		# 🌟 強制切換到「變身發呆」狀態！
		if state_machine:
			state_machine.change_state("BerserkTransition")
		return # 攔截成功！不要往下執行老爸的死亡邏輯

	# 如果沒觸發鎖血，就把控制權交還給老爸，執行正常扣血與處決機制
	super.take_damage(amount, attacker_pos, dir, is_melee, extra_knockback)

# 🌟 覆寫硬直邏輯 (解決子彈打到不會進二階的問題)
func handle_hurt() -> void:
	# 如果大腦正在變身，或者正在狂暴衝刺，免疫普通受傷硬直！
	if state_machine and state_machine.current_state:
		var current_name = state_machine.current_state.name
		if current_name == "BerserkTransition" or current_name == "BerserkCharge":
			return
			
	# 如果不是狂暴狀態，交給老爸正常處理
	super.handle_hurt()

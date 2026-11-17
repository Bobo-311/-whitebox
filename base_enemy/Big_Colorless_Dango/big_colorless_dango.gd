extends BaseEnemy
class_name BigDango

# ==========================================
# ⚙️ Boss 專屬配置與鎖血設定
# ==========================================
@export_category("💣 Boss 鎖血與召喚設定")
@export var boss_display_name: String = "糰子王" # 🌟 顯示在血條上的 Boss 名字 (可在右側面板修改)
@export var minion_scene: PackedScene # 從 Inspector 放入要吐出來的小怪(藍色團子)場景

var hp_thresholds: Array[float] = [0.8, 0.6, 0.4, 0.2] # 企劃設定：四次鎖血反擊的血量百分比
var current_phase_index: int = 0 # 記錄目前打到第幾個階段了
var is_invincible: bool = false  # Boss 專屬無敵開關 (紫光時會被開啟)

# 🌟 自動抓取掛在身上的 BossUI_dango (或 BossUI) 節點
@onready var boss_ui: CanvasLayer = get_node_or_null("BossUI_dango")


# ==========================================
# 🚀 開局初始化 (強制喚醒與霸體)
# ==========================================
func _ready() -> void:
	super._ready() # 讓老爸先跑完基礎的變數綁定 (含 current_hp = max_hp)
	
	# 防呆：如果節點名字叫 BossUI 或其他名字，自動尋找底下的 CanvasLayer
	if not boss_ui:
		boss_ui = get_node_or_null("BossUI")
	if not boss_ui:
		for child in get_children():
			if child is CanvasLayer and child.has_method("init_boss"):
				boss_ui = child
				break
				
	# 🌟 初始化糰子王的血量 UI 連動！
	if boss_ui and boss_ui.has_method("init_boss"):
		boss_ui.init_boss(boss_display_name, int(max_hp))
	
	# 🌟【根除滑行 (絕對霸體)】
	if knockback_component:
		knockback_component.resistance = 0.0
		
	# 延遲 1 幀呼叫喚醒函數，確保場景與玩家都已經載入完畢，避免開局抓不到人
	call_deferred("_wake_up_boss")

func _physics_process(delta: float) -> void:
	# 🌟 防呆：如果玩家正在看過場劇情，讓糰子王暫停移動與出招，乖乖等劇情演完再開打！
	if Dialogic.current_timeline != null or (DataManager and is_instance_valid(DataManager.player_node) and DataManager.player_node.get("is_in_dialogue")):
		velocity = Vector2.ZERO
		return
		
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
	super.take_damage(amount, attacker_pos, dir, is_melee, 0.0)
	
	# 🌟 3. 同步更新糰子王血條 UI (觸發閃白光、黃條衰減與震動)！
	if boss_ui and boss_ui.has_method("update_health"):
		boss_ui.update_health(int(current_hp))
	
	# 4. 扣完血後，檢查有沒有低於鎖血門檻
	_check_hp_threshold()

# -------------------------------------------------------------------------
# 🩸 技能階段轉換與血量監控
# -------------------------------------------------------------------------
func _check_hp_threshold() -> void:
	if current_phase_index >= hp_thresholds.size() or is_dead: 
		return 
		
	var hp_ratio = float(current_hp) / float(max_hp)
	
	if hp_ratio <= hp_thresholds[current_phase_index]:
		current_phase_index += 1
		if state_machine:
			state_machine.change_state("LockHpSpawn")

# ==========================================
# 🎭 單面 Boss 動畫轉接器
# ==========================================
func play_animation(anim_name: String, dir: Vector2 = Vector2.ZERO) -> void:
	if not animated_sprite_2d or not animated_sprite_2d.sprite_frames:
		return
		
	var target_anim = anim_name
	
	if anim_name == "move":
		var check_x = velocity.x if abs(velocity.x) > 1.0 else dir.x
		target_anim = "move_left" if check_x < 0 else "move_right"
		
	if animated_sprite_2d.sprite_frames.has_animation(target_anim):
		if animated_sprite_2d.animation != target_anim or not animated_sprite_2d.is_playing():
			animated_sprite_2d.play(target_anim)
	else:
		super.play_animation(anim_name, dir)

func die() -> void:
	if is_dead: return
	is_dead = true
	
	# 🌟 確保死掉時血條歸零並隱藏
	if boss_ui and boss_ui.has_method("update_health"):
		boss_ui.update_health(0)
	
	# 攔截老爸的普通死法，改為切換到 Boss 專屬的「自爆預警」狀態
	if state_machine:
		state_machine.change_state("Die")
		
	drop_coin() # 噴出金幣

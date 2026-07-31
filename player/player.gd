extends BaseCharacter # 繼承自基礎角色類別，獲得通用功能 (如死亡、受傷框架)
class_name Player # 宣告這個腳本代表「玩家 (Player)」

# ==========================================
# 基礎物理與攻擊數值
# ==========================================
@export var walk_speed: int = 400          # 正常走路的速度
@export var dash_speed: float = 1500.0     # 翻滾衝刺時的瞬間爆發速度
@export var dash_duration: float = 0.2     # 衝刺維持的時間長度 (秒)
@export var basic_attack_damage: float = 15.0 # 玩家的基礎揮刀攻擊力

# 記住玩家一絲不掛時的「基礎最大血量」
var base_max_hp: int = 100

# ==========================================
# 能量 (EP) 與 體力 (SP) 系統
# ==========================================
@export var max_energy: int = 100          # 能量上限 (發動技能、過飽和狀態用)
var current_energy: int = 50               # 開局預設能量

@export var max_sp: float = 100.0          # 體力上限 (揮刀、翻滾消耗用)
var current_sp: float = 50                 # 開局預設體力
var is_overheated: bool = false            # 狀態開關：記錄玩家現在是否處於「過熱力竭」狀態
var sp_regen_delay: float = 0.5            # 體力恢復延遲：消耗後需等待 0.5 秒才能開始回體
var sp_delay_timer: float = 0.0            # 隱形計時器：負責倒數回體的等待時間

# ==========================================
# 狀態紀錄與節點抓取
# ==========================================
var input_direction: Vector2 = Vector2.ZERO # 記錄玩家按下的 WASD 方向向量
var facing_direction: String = "down"       # 記錄玩家最後面朝的方向，預設朝下
var is_dashing: bool = false                # 記錄玩家現在是否正在衝刺中

# [🌟 本次新增] 素描本系統狀態變數
var is_reading_book: bool = false           # 記錄玩家是否正在看筆記本
var opened_from_savepoint: bool = false # 記錄筆記本是不是從存檔點捷徑打開的

@onready var state_machine: StateMachine = $StateMachine               # 控制玩家行為的大腦節點 (狀態機)
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D  # 負責播放動畫的精靈圖
@onready var player_hud: CanvasLayer = $PlayerHUD                      # 畫面左上角的狀態條介面 (UI)
@onready var skill_01: Node2D = $Skill_01                              # 掛在玩家身上的技能發射器 (槍管)

# [🌟 本次新增] 抓取素描本 UI 節點
# ⚠️ 注意：我假設你把 NotebookUI 放進 PlayerHUD 裡了。如果名字或位置不一樣，請手動改這裡！
@onready var notebook_ui = $MenuLayer/NotebookUI
	
# ==========================================
# 遊戲初始化 (_ready)
# ==========================================
func _ready(): 
	super._ready() # 呼叫父類別準備函數，確保基本屬性初始化 (如血量補滿)
	
	DataManager.player_node = self # 玩家一出生，立刻將自己註冊到全域大腦裡
	
	# 訂閱裝備廣播頻道，確保裝備變動時重算能力
	if not DataManager.equipment_changed.is_connected(recalculate_stats):
		DataManager.equipment_changed.connect(recalculate_stats)
	
	# 開局防呆：手動算一次裝備屬性
	recalculate_stats()
	
	# --- 讀取存檔資料 ---
	if DataManager and DataManager.last_save_position != Vector2.ZERO: 
		global_position = DataManager.last_save_position # 將位置強制移動到存檔點
		
	if DataManager and DataManager.saved_hp > 0: 
		# 讀檔時，現在的血量不能超過算完裝備後的新血量上限
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
		
	# 依照當前 current_hp 算出最精準的身體顏色！
	update_hp_bar()
		
	# --- 靈魂回收系統 (撿屍體) ---
	if DataManager and DataManager.has_soul_on_ground: 
		if DataManager.soul_map_path == get_tree().current_scene.scene_file_path:
			var soul_scene = load("res://soul/Soul.tscn") 
			if soul_scene: 
				var soul = soul_scene.instantiate() 
				soul.global_position = DataManager.soul_spawn_pos 
				soul.lost_gold = DataManager.soul_stored_gold     
				soul.scale = Vector2(2.0, 2.0) 
				get_tree().current_scene.call_deferred("add_child", soul) 

# ==========================================
# 裝備能力統整計算中心
# ==========================================
func recalculate_stats():
	var bonus_hp = 0 
	
	if DataManager.has_sticker("001"):
		bonus_hp += DataManager.STICKER_DB["001"].value 
		
	max_hp = base_max_hp + bonus_hp
	
	if current_hp > max_hp:
		current_hp = max_hp
		
	update_hp_bar() 
	print("【系統】玩家能力已更新，目前最大血量：", max_hp)

# ==========================================
# 開發者外掛與輸入偵測
# ==========================================
func _input(event):
	# [🌟 本次新增] 監聽 Tab 鍵，開關素描本
	# [🌟 本次新增] 監聽 Tab 鍵，開關素描本
	if event.is_action_pressed("notebook"):
		is_reading_book = !is_reading_book
		
		if is_reading_book:
			# 打開書時：煞車、並強制關閉狀態機(無法攻擊/翻滾)
			velocity = Vector2.ZERO 
			state_machine.process_mode = Node.PROCESS_MODE_DISABLED 
			
			if notebook_ui:
				notebook_ui.toggle_notebook(false) # 正常打開（有動畫）
		else:
			# 關上書時：重新啟動狀態機
			state_machine.process_mode = Node.PROCESS_MODE_INHERIT 
			
			if notebook_ui:
				# 🌟 核心判定：如果剛才是從存檔畫架進來的
				if opened_from_savepoint:
					notebook_ui.toggle_notebook(true) # 瞬間關閉筆記本
					opened_from_savepoint = false # 重置防呆
					
					# 🌟 把藏在背景的畫架找出來，重新顯示，並再次時間暫停！
					var save_menus = get_tree().get_nodes_in_group("save_menu")
					if save_menus.size() > 0:
						save_menus[0].show()
						get_tree().paused = true
				else:
					notebook_ui.toggle_notebook(false) # 正常關閉（有動畫）

	# 測試用外掛：按下指定按鍵直接加 100 元
	if event.is_action_pressed("cheater") and DataManager: 
		DataManager.total_gold += 100
		print("【開發者外掛】印鈔 100 元！總金額：", DataManager.total_gold)
		
	# 【全新測試外掛：按鍵盤 P 鍵，直接進貨一罐藥水】
	if Input.is_physical_key_pressed(KEY_P) and event.is_pressed() and not event.is_echo():
		DataManager.add_item_to_reserve("potion_gugu", 1)
		print("【開發者外掛】憑空獲得 1 罐咕咕嘎嘎藥水！")

# ==========================================
# 物理與邏輯更新 (這是一個每秒會執行 60 次的超高速迴圈)
# ==========================================
func _physics_process(delta: float) -> void: 
	
	# 【第一關防呆】：檢查玩家死了沒。死人是不會動的，直接跳過所有邏輯
	if not is_dead: 
		
		# ==========================================
		# 🛑 狀態鎖定區：看書罰站機制
		# ==========================================
		# 【第二關防呆】：如果玩家現在正在看筆記本 (is_reading_book 為 true)
		if is_reading_book:
			# 為了避免玩家按開筆記本的瞬間還在滑行，強制把速度歸零 (踩死煞車)
			velocity = Vector2.ZERO 
			
			# 雖然速度是 0，但還是要呼叫物理引擎，確保玩家不會穿牆或浮空
			move_and_slide()        
			
			# 🌟 最重要的一行！return 代表「直接中斷退出」！
			# 只要執行到這行，下面的走路、放技能、吃藥通通不會執行。
			# 這樣玩家在看書時狂按鍵盤，角色才不會在背後亂動。
			return                  
		
		# ==========================================
		# 🏃 移動判定區
		# ==========================================
		# 抓取玩家按下的 WASD (或上下左右)。
		# 為什麼用 get_vector？因為它會自動把「斜向移動」的速度縮放為 1，
		# 這樣玩家「往右上角走」的速度，就不會比「往右走」還快了！
		input_direction = Input.get_vector("left", "right", "up", "down") 


		# ==========================================
		# 🎒 快捷欄切換區 (與 DataManager 大腦連線)
		# ==========================================
		# 按下鍵盤的 1 鍵 (向左切換)
		if Input.is_action_just_pressed("slot_left"): 
			# 傳送 -1 給大腦，代表指針往左邊退一格
			# 大腦轉完之後，會自動發出廣播叫 UI 更新，我們不用管 UI 了
			DataManager.rotate_quick_slot(-1)
			
		# 按下鍵盤的 3 鍵 (向右切換)
		if Input.is_action_just_pressed("slot_right"): 
			# 傳送 1 給大腦，代表指針往右邊進一格
			DataManager.rotate_quick_slot(1)


		# ==========================================
		# ⚔️ 戰鬥與道具使用區 (徹底分家版！)
		# ==========================================
		
		# --- 1️⃣ 發射魔法棒子彈 (左鍵) ---
		# ⚠️ 注意：我這裡先假設你的滑鼠左鍵綁定的名稱叫做 "attack"
		# 如果你在專案設定裡左鍵叫別的名字 (例如 "shoot" 或 "left_click")，請把 "attack" 改掉！
		if Input.is_action_just_pressed("attack"): 
			
			if state_machine.current_state.name != "PlayerHeal" and not is_overheated: 
				
				var current_buff: float = get_oversaturation_buff() 
				
				if DataManager.has_sticker("004"):
					current_buff *= DataManager.STICKER_DB["004"].value
					print("【魔法棒生效】技能最終傷害倍率提升為：", current_buff)
				
				if use_energy(30): 
					skill_01.shoot(current_buff) 
				else: 
					print("能量不足 30，無法施放左鍵技能發射子彈！") 
					
			elif is_overheated: 
				print("系統過熱中！無法釋放技能！") 


		# --- 2️⃣ 使用快捷欄道具 (Q 鍵) ---
		if Input.is_action_just_pressed("USESKILL"): 
			# 按 Q 鍵現在只負責呼叫大腦吃道具，絕對不會再射子彈了！
			if state_machine.current_state.name != "PlayerHeal": 
				DataManager.use_current_item() 
		

		# ==========================================
		# 💚 體力 (SP) 自動恢復邏輯
		# ==========================================
		# sp_delay_timer 是一個「隱形倒數計時器」。
		# 每次玩家揮刀或翻滾，這個計時器就會被設定為 0.5 秒。
		
		if sp_delay_timer > 0:            
			# 如果計時器還沒歸零，就繼續倒數 (delta 是一幀的時間)
			sp_delay_timer -= delta       
		else:                                  
			# 計時器歸零了！代表玩家已經 0.5 秒沒消耗體力了，開始回體！
			
			if current_sp < max_sp: 
				# 決定回體速度：如果過熱就回得慢 (10.0)，沒過熱就回得快 (12.0)
				var regen_rate = 10.0 if is_overheated else 12.0 
				
				# 增加體力，但用 min() 限制它絕對不能超過最大體力值 (max_sp)
				current_sp = min(current_sp + regen_rate * delta, max_sp) 
				
				# 如果玩家處於過熱狀態，且體力已經恢復超過 70% (0.7) 了
				if is_overheated and current_sp >= max_sp * 0.7: 
					# 解除過熱封印！
					is_overheated = false 
					player_hud.set_overheat_visual(false) # 關閉紅色閃爍特效
					print("體力恢復至 70%，解除過熱狀態！") 
					
				# 最後把算好的體力值送到 UI 上顯示
				player_hud.update_sp(current_sp, max_sp) 


	# ==========================================
	# 🚗 引擎推動區
	# ==========================================
	# 不管上面算了多少速度 (velocity)，最後一定要呼叫這行！
	# 這是 Godot 內建的物理引擎函數，它會真的推動玩家，並處理撞牆、滑行等物理效果
	move_and_slide()

# ==========================================
# 資源消耗控制 (體力與能量)
# ==========================================
func use_sp(amount: float) -> bool: 
	if is_overheated: return false 

	if current_sp > 0: 
		current_sp = max(current_sp - amount, 0.0) 
		sp_delay_timer = sp_regen_delay 
		
		if current_sp <= 0:        
			is_overheated = true
			player_hud.set_overheat_visual(true) 
			print("體力耗盡！進入過熱狀態！") 

		player_hud.update_sp(current_sp, max_sp) 
		return true 
	return false 

func use_energy(amount: int) -> bool: 
	if current_energy >= amount: 
		current_energy -= amount 
		if player_hud: player_hud.update_energy(current_energy, max_energy) 
		return true 
	return false 

func add_energy(amount: int): 
	current_energy = min(current_energy + amount, max_energy) 
	if player_hud: player_hud.update_energy(current_energy, max_energy) 

# ==========================================
# 戰鬥與受傷邏輯
# ==========================================

# 負責計算包含「起床氣 (008)」機制在內的最終基礎普攻傷害
func get_current_basic_attack_damage() -> float:
	var final_base_damage: float = basic_attack_damage
	
	if DataManager.has_sticker("008"):
		var threshold: float = DataManager.STICKER_DB["008"].threshold 
		
		if float(current_hp) / float(max_hp) <= threshold:
			final_base_damage *= DataManager.STICKER_DB["008"].value 
			print("【起床氣發動】血量低於 35%，基礎普攻傷害飆升至：", final_base_damage)
			
	return final_base_damage

# 負責判斷是否滿能量，並給予對應的倍率
func get_oversaturation_buff() -> float: 
	if current_energy >= max_energy: 
		print("【過飽和狀態】發動！目前倍率：1.5 倍") 
		return 1.5 
	return 1.0 

# 專門用來接收怪物死掉時傳來的通知，並結算 006 手裡劍的回血效果
func on_enemy_killed():
	if DataManager.has_sticker("006"):
		var heal_percent: float = DataManager.STICKER_DB["006"].value
		var heal_amount: int = int(max_hp * heal_percent)
		current_hp = min(current_hp + heal_amount, max_hp)
		update_hp_bar()
		print("【手裡劍發動】成功擊殺敵人，吸取血量：", heal_amount, "，目前血量：", current_hp)

func handle_hurt(): 
	# [🌟 本次新增] 被打斷機制：看書時如果遭到攻擊，強制關閉筆記本並拿回控制權
	if is_reading_book:
		is_reading_book = false
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT # 🌟 被打時強制喚醒狀態機！
		if notebook_ui:
			notebook_ui.close_notebook()
		print("【戰鬥提示】看書時遭到攻擊，筆記本已強制關閉！")
	
	var state_name = state_machine.current_state.name.to_lower() 
	
	if "stun" in state_name or "pant" in state_name: 
		velocity = knockback_force 
		return 
		
	state_machine.change_state("PlayerHurt") 

# ==========================================
# 🌟 本次新增：外部補血接收器
# ==========================================
func heal(amount: int) -> void:
	if current_hp < max_hp:
		current_hp = min(current_hp + amount, max_hp)
		update_hp_bar() # 更新血條 UI 和身體顏色
		print("【玩家】喝下道具！恢復了 ", amount, " 點生命！目前血量：", current_hp)
		
		# 💡 如果你有綠色十字架之類的補血特效，或是喝水的音效，以後可以直接加在這裡！



# ==========================================
# 狀態與 UI 更新
# ==========================================
func die(): 
	if is_dead: return 
	is_dead = true 
	if state_machine: state_machine.change_state("PlayerDie") 

func update_hp_bar(): 
	if player_hud: player_hud.update_hp(current_hp, max_hp) 
	
	var hp_ratio: float = max(float(current_hp) / float(max_hp), 0.0) 
	if animated_sprite_2d.material: 
		var tween = get_tree().create_tween() 
		tween.tween_property(animated_sprite_2d.material, "shader_parameter/saturation", hp_ratio, 0.3) 

# ==========================================
# 動畫播放控制器
# ==========================================
func play_animation(prefix: String, _dir: Vector2 = Vector2.ZERO): 
	var anim = get_node_or_null("AnimatedSprite2D") 
	if anim == null: return 
	
	if not is_dashing and input_direction != Vector2.ZERO: 
		if abs(input_direction.x) > abs(input_direction.y): 
			facing_direction = "right" if input_direction.x > 0 else "left" 
		else: 
			facing_direction = "down" if input_direction.y > 0 else "up" 
				
	anim.play(prefix + "_" + facing_direction)

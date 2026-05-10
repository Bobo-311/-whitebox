extends BaseCharacter            # 繼承基礎角色類別，獲得扣血、死亡等功能
class_name Enemy                 # 定義為 Enemy 類別

@export var walk_speed: int = 150                 # 野豬的漫遊走路速度
@export var sprint_speed: int = 450               # 野豬追擊玩家時的衝刺速度
@export var attack_speed_multiplier: float = 2.5  # 野豬發動衝撞攻擊時的速度倍率
@export var attack_time: float = 0.45             # 攻擊狀態維持的時間長度
@export var melee_damage: float = 15.0            # 野豬肉身衝撞造成的近戰傷害量

const COIN_SCENE = preload("res://coin/coin.tscn")# 🌟 預載入金幣場景



@onready var state_machine: StateMachine = $StateMachine       # 抓取狀態機節點
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D # 抓取動畫播放器節點
@onready var hp_bar: ProgressBar = $HealthBar                  # 抓取血條UI節點

var player_node: CharacterBody2D = null           # 記憶目前鎖定的玩家實體，預設為空
var last_facing_vec: Vector2 = Vector2.DOWN       # 記憶野豬最後面朝的方向，預設朝下
var has_hit_player: bool = false                  # 標記開關：這次衝刺是不是已經咬到過玩家了？
var can_attack: bool = true                       # 攻擊冷卻開關：決定野豬現在能不能發動攻擊

func _ready():                   # 遊戲開始時執行
	super._ready()               # 呼叫父類別(BaseCharacter)的 _ready 函數，確保血量補滿

func _physics_process(_delta: float) -> void:     # 每一幀物理運算
	move_and_slide()             # 根據 velocity 執行移動，並自動處理撞牆滑行

# --- 處理受傷與擊退邏輯的專屬函數 ---
func handle_hurt(): # 當野豬被玩家的武器判定打到時呼叫
	var state_name = state_machine.current_state.name.to_lower() # 【特殊函數】把狀態名轉小寫，防止大小寫打錯字
	
	# 🌟 破綻鎖定：如果正在暈眩 (stun) 或喘氣 (pant) 期間
	if "stun" in state_name or "pant" in state_name: 
		
		# 賦予擊退力道，這配合上面的 0.15 煞車(pant)，會讓它退一小步後停下
		velocity = knockback_force 
		
		# 加上一個瞬間變白的打擊特效，這樣即使動畫沒斷，玩家也知道有砍中
		var hit_tween = get_tree().create_tween() # 建立一次性動畫
		animated_sprite_2d.modulate = Color(3, 3, 3) # 瞬間變為過曝的高亮白色
		hit_tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.1) # 0.1 秒後恢復正常色
		
		return # 🌟 直接跳出函數，拒絕執行後面的狀態切換！這能確保紫光閃爍繼續進行
		
	# 如果是平常在走路或站著時被打，才切換到正常的受傷狀態
	state_machine.change_state("EnemyHurt")

func die():                      # 實作父類別的虛擬函數：處理死亡
	if is_dead: return           # 防呆：死過就不再執行
	is_dead = true               # 標記死亡狀態為真
	state_machine.change_state("EnemyDie")        # 讓狀態機切換到 "EnemyDie" 狀態
	drop_coin() # 🌟 在野豬消失前，呼叫噴錢函數！
	
	# queue_free() 或切換死亡狀態

func update_hp_bar():            # 實作父類別的虛擬函數：更新血條
	if hp_bar:                   # 如果有抓到血條節點
		hp_bar.update_bar(current_hp, max_hp)     # 呼叫血條腳本的 update_bar 函數更新數值

func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO): # 動畫播放控制器，接收動作前綴和方向
	var suffix = ""              # 準備用來裝方向後綴的字串
	var target_dir = dir if dir != Vector2.ZERO else last_facing_vec # 如果有傳入方向就用傳入的，沒有就用最後面朝的方向
	
	if abs(target_dir.x) > abs(target_dir.y):     # 如果X軸(左右)的幅度大於Y軸(上下)
		suffix = "_right" if target_dir.x > 0 else "_left"  # 朝右就加 "_right"，否則 "_left"
	else:                                         # 如果Y軸的幅度比較大
		suffix = "_down" if target_dir.y > 0 else "_up"     # 朝下就加 "_down"，否則 "_up"
	
	animated_sprite_2d.play(prefix + suffix)      # 把動作(如"run")跟方向(如"_left")組合起來播放動畫

# --- 掉落物品系統 ---
func drop_coin(): 
	if COIN_SCENE: 
		# 🌟 使用迴圈重複執行 5 次
		for i in range(5): 
			# 【特殊函數】create_timer()：建立隨機的極短延遲 (0.01 到 0.1 秒)
			# 這樣金幣會有一點點先後順序噴出來，視覺效果更好！
			var delay = randf_range(0.01, 0.1) 
			
			get_tree().create_timer(delay).connect("timeout", func():
				var coin = COIN_SCENE.instantiate() # 生成金幣實體
				
				coin.coin_value = 1 # 設定每顆金幣面額為 1
				coin.global_position = global_position # 設定座標為野豬死亡處
			# 加到世界場景
			# 🌟 絕對關鍵修正：使用 call_deferred 延遲加入！
			# 【特殊函數解釋】：call_deferred("函數名稱", 參數) 
			# 它的功用是「延遲呼叫」。等 Godot 物理引擎把這 1/60 秒的事情全部忙完後，
			# 才會安全地執行 add_child 將金幣加入世界，完美避開當機衝突！
				get_parent().call_deferred("add_child", coin)
			)
		














func _on_detect_player_body_entered(body):        # 視野感應區(Area2D)碰到實體肉身時觸發
	if body is Player:           # 檢查碰到的實體是不是玩家(Player)類別
		player_node = body       # 如果是，就把這個玩家存進大腦當作追擊目標

func _on_detect_player_body_exited(body):         # 視野感應區離開實體時觸發
	if body == player_node:      # 如果離開的實體剛好就是目前的目標玩家
		player_node = null       # 弄丟目標，清空記憶

func _on_hitbox_area_entered(area: Area2D) -> void: # 野豬嘴巴(Hitbox)撞到感應區時觸發
	print("🔥【野豬Hitbox】撞到東西：", area, " 類型：", area.get_class()) # 後台印出撞到什麼
	
	if has_hit_player: return    # 如果這次衝刺已經咬過了，直接跳出避免重複扣血

	if area is Hurtbox:          # 如果撞到的感應區剛好是 Hurtbox (受傷區)
		print("✅ 是 Hurtbox")    # 再次確認
		var parent = area.get_parent()            # 往上找這個 Hurtbox 的主人是誰
		print("👉 父節點：", parent)              # 印出主人的名字

		if parent is Player:     # 如果主人是玩家
			print("🎯 打到玩家了") # 確認咬中
			has_hit_player = true# 把「已咬中」的標籤設為真，鎖死傷害判定
			area.take_damage(melee_damage, global_position) # 呼叫玩家的 Hurtbox 扣血，傳入野豬專屬的近戰傷害與野豬當前座標

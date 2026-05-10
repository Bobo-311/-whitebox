extends Area2D # 繼承 Area2D，用於偵測玩家碰撞

@export var coin_value: int = 5 # 金幣面額
var target_player: Node2D = null # 記錄要追蹤的玩家節點
var is_magnetic: bool = false # 開關：金幣落地後是否允許被磁吸
var current_speed: float = 0.0 # 記錄當下的飛行速度
@export var magnetic_speed_max: float = 800.0 # 磁吸的最大極速
@export var magnetic_acceleration: float = 1500.0 # 磁吸的加速度 (每秒變快多少)

func _ready(): # 金幣剛生成時執行一次
	# --- 階段一：爆發噴灑特效 (拋物線) ---
	var random_x: float = randf_range(-60.0, 60.0) # 隨機左右偏移量
	var random_y: float = randf_range(-100.0, -50.0) # 隨機向上彈跳高度
	
	var target_pos: Vector2 = position + Vector2(random_x, random_y) # 計算彈跳最高點
	var final_pos: Vector2 = position + Vector2(random_x * 1.5, randf_range(20.0, 40.0)) # 計算最終落地點

	var pop_tween = get_tree().create_tween().bind_node(self) # 建立動畫控制器
	pop_tween.set_trans(Tween.TRANS_QUAD) # 設定為平滑的拋物線曲線
	
	# 動畫排程：先減速上拋 (EASE_OUT)，再加速下落 (EASE_IN)
	pop_tween.tween_property(self, "position", target_pos, 0.25).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(self, "position", final_pos, 0.25).set_ease(Tween.EASE_IN)
	
	# 隱形計時器：確保落地 0.5 秒後才開啟磁吸功能，避免還在空中就被吸走
	get_tree().create_timer(0.5).connect("timeout", func(): is_magnetic = true)
	

func _physics_process(delta: float): # 每一幀的物理更新
	if is_magnetic: # 條件：必須落地且開啟磁吸後才執行
		
		# --- 階段二：雷達索敵 ---
		# 如果還沒鎖定玩家，直接問大腦 (DataManager) 玩家的座標
		if target_player == null and DataManager.player_node != null: 
			var distance = global_position.distance_to(DataManager.player_node.global_position) # 計算距離
			if distance < 150.0: # 如果玩家踏入 150 像素的雷達半徑
				target_player = DataManager.player_node # 鎖定目標！
		
		# --- 階段三：磁吸追蹤 ---
		if target_player != null: # 如果已經鎖定玩家
			current_speed += magnetic_acceleration * delta # 逐漸加速
			if current_speed > magnetic_speed_max: current_speed = magnetic_speed_max # 限制不超過極速
				
			# 算出飛向玩家的「方向向量」，並執行移動
			var direction: Vector2 = (target_player.global_position - global_position).normalized()
			global_position += direction * current_speed * delta

func _on_body_entered(body: Node2D): # 當有實體撞到金幣時執行
	# 🌟 完美防呆：確認撞到的是不是掛著 Player 類別的玩家實體
	if body is Player: 
		if DataManager: 
			DataManager.total_gold += coin_value # 把錢存進大腦
			print("【系統】吃掉金幣！目前總金額：" + str(DataManager.total_gold)) 
		
		queue_free() # 結帳完畢，刪除金幣實體

extends Area2D # 繼承 Area2D，用於偵測玩家碰撞

@export var coin_value: int = 5 # 金幣面額

@export var magnetic_speed_max: float = 800.0 # 磁吸的最大極速
@export var magnetic_acceleration: float = 1500.0 # 磁吸的加速度 (每秒變快多少)

var target_player: Node2D = null # 記錄要追蹤的玩家節點
var is_magnetic: bool = false # 開關：金幣落地後是否允許被磁吸
var current_speed: float = 0.0 # 記錄當下的飛行速度


func _ready(): 
	# 建立 3 秒自動銷毀計時器
	get_tree().create_timer(3.0).connect("timeout", queue_free)
	
	# --- 拋物線安全判定 ---
	var random_x: float = randf_range(-40.0, 40.0) # 縮小隨機 X 範圍減少衝擊力
	var random_y: float = randf_range(-60.0, -30.0) # 隨機向上跳躍高度
	
	var target_pos: Vector2 = position + Vector2(random_x, random_y) # 計算跳躍最高點
	var final_pos: Vector2 = position + Vector2(random_x * 1.2, randf_range(10.0, 20.0)) # 計算落地位置
	
	# 🌟 核心修正：利用物理射線探測落地點是否在牆內
	var space_state = get_world_2d().direct_space_state # 獲取物理世界狀態
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + (final_pos - position)) # 建立探測射線
	query.collision_mask = 1 # 設定只探測第一層 (牆壁層)
	var result = space_state.intersect_ray(query) # 執行探測
	
	if result: # 如果射線撞到了牆壁
		final_pos = position + (result.position - global_position) * 0.8 # 將落地點縮回到牆邊 80% 的位置，防止陷進去
	
	# --- 執行拋物線動畫 ---
	var pop_tween = get_tree().create_tween().bind_node(self) # 建立動畫控制器
	pop_tween.set_trans(Tween.TRANS_QUAD) # 設定平滑曲線
	pop_tween.tween_property(self, "position", target_pos, 0.25).set_ease(Tween.EASE_OUT) # 向上彈起
	pop_tween.tween_property(self, "position", final_pos, 0.25).set_ease(Tween.EASE_IN) # 向下落地
	
	# 落地 0.5 秒後開啟磁吸功能
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

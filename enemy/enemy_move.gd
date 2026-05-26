extends State # 繼承狀態模板 enemy_move

var timer: float = 0.0 # 漫遊計時器
var is_moving: bool = true # 狀態開關
var wander_dir: Vector2 = Vector2.ZERO # 宣告變數：記住現在散步的方向
var wall_bump_cooldown: float = 0.0 # 🌟 新增冷卻器：防止在角落瘋狂轉向

func enter(): # 進入漫遊
	_start_moving() # 開始走

func _start_moving(): # 開始走路邏輯
	is_moving = true # 標記走路
	timer = 3.0 # 固定走 3 秒
	
	wander_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() # 隨機決定一個方向
	character.velocity = wander_dir * character.walk_speed # 給予速度
	character.last_facing_vec = wander_dir # 記憶方向
	character.play_animation("move", wander_dir) # 播動畫

func _stop_moving(): # 停下邏輯
	is_moving = false # 標記停止
	timer = 1.5 # 🌟 自然走完 3 秒後，固定發呆 1.5 秒
	
	character.velocity = Vector2.ZERO # 速度歸零
	character.play_animation("idle", character.last_facing_vec) # 播待機動畫

func state_physics_update(delta: float): # 物理更新
	if character.player_node: # 發現玩家
		state_machine.change_state("EnemyRun") # 追擊
		return

	# 扣除防卡牆的冷卻時間
	if wall_bump_cooldown > 0:
		wall_bump_cooldown -= delta

	# 🌟 核心防卡牆優化：掃地機器人反射法！
	# 如果在走路，且碰到牆壁，且轉向冷卻已經結束
	if is_moving and character.is_on_wall() and wall_bump_cooldown <= 0: 
		var normal = character.get_wall_normal() # 取得這面牆壁的「法線」(牆壁面對的方向)
		if normal != Vector2.ZERO:
			wander_dir = wander_dir.bounce(normal) # 讓目前的走路方向像撞球一樣反射！
			character.velocity = wander_dir * character.walk_speed # 給予反射後的新速度
			character.last_facing_vec = wander_dir # 記憶新方向
			character.play_animation("move", wander_dir) # 播放新方向的動畫
			wall_bump_cooldown = 0.5 # 🌟 進入 0.5 秒的轉向冷卻，防止在角落瘋狂抖動
			return # 轉向後繼續走，不中斷原本的 3 秒計時器！

	timer -= delta # 倒數總行為計時器
	
	if timer <= 0: # 時間到
		if is_moving: 
			_stop_moving() # 走滿 3 秒就停下發呆
		else: 
			_start_moving() # 發呆完 1.5 秒就繼續走

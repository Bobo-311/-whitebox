extends State # 繼承狀態模板 base_move

# 🌟【升級版】把寫死的秒數變成可調整的變數
@export var walk_time: float = 3.0  # 預設漫遊走幾秒
@export var stop_time: float = 1.5  # 預設發呆停幾秒

# 🌟 新增這行：開放面板調整發現玩家後要進入什麼狀態
@export var aggro_state: String = "Chase"


var timer: float = 0.0 # 漫遊計時器
var is_moving: bool = true # 狀態開關
var wander_dir: Vector2 = Vector2.ZERO # 宣告變數：記住現在散步的方向
var wall_bump_cooldown: float = 0.0 # 🌟 新增冷卻器：防止在角落瘋狂轉向

func enter(): # 進入漫遊
	_start_moving() # 開始走

func _start_moving(): # 開始走路邏輯
	is_moving = true # 標記走路
	timer = walk_time # 固定走 3 秒
	
	wander_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() # 隨機決定一個方向
	character.last_facing_vec = wander_dir # 記憶方向
	character.play_animation("move", wander_dir) # 播動畫
	# 🌟【修改 1】：改呼叫老爸的移動調度器（野豬會直接走，青蛙會依影格跳）
	character.apply_locomotion(wander_dir, character.walk_speed)

func _stop_moving(): # 停下邏輯
	is_moving = false # 標記停止
	timer = stop_time # 🌟 自然走完 3 秒後，固定發呆 1.5 秒	
	
	character.velocity = Vector2.ZERO # 速度歸零
	character.play_animation("idle", character.last_facing_vec) # 播待機動畫

func state_physics_update(delta: float): # 物理更新
	# 🌟 加上 and character.can_see_player，確保散步時也不會透視！
	if character.player_node and character.can_see_player:
		state_machine.change_state(aggro_state) # 追擊
		return

	# 扣除防卡牆的冷卻時間
	if wall_bump_cooldown > 0:
		wall_bump_cooldown -= delta

	# 🌟【修改 2】：在移動期間，每一幀交由老爸判斷目前影格該「騰空衝刺」還是「撐地停頓」
	if is_moving:
		character.apply_locomotion(wander_dir, character.walk_speed)

	# 🌟 核心防卡牆優化：掃地機器人反射法！
	if is_moving and character.is_on_wall() and wall_bump_cooldown <= 0: 
		var normal = character.get_wall_normal()
		if normal != Vector2.ZERO:
			wander_dir = wander_dir.bounce(normal)
			character.last_facing_vec = wander_dir
			character.play_animation("move", wander_dir)
			character.apply_locomotion(wander_dir, character.walk_speed)
			wall_bump_cooldown = 0.5
			return

	timer -= delta # 倒數總行為計時器
	
	if timer <= 0: # 時間到
		if is_moving: 
			# 🌟【修改 3：青蛙完美落地防呆】
			# 如果是青蛙且剛好跳在半空中，等牠這一下落地 (is_jump_grounded) 再切換成 idle 發呆！
			if character.is_jump_grounded():
				_stop_moving()
		else: 
			_start_moving() # 發呆完 1.5 秒就繼續走

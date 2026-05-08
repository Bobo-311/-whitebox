# --- EnemyMove.gd ---
extends State

var timer: float = 0.0       # 漫遊計時器
var is_moving: bool = true   # 正在走還是停？

func enter():
	_start_moving()          # 一進來就開始隨機走動

func _start_moving():
	is_moving = true         
	timer = 5.0              # 設定走動時間為 5 秒
	
	var is_running = randf() > 0.5 # 50%機率用跑步的
	var speed = character.sprint_speed if is_running else character.walk_speed # 根據機率決定速度
	
	var wander_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() # 隨機決定一個X和Y方向
	
	character.velocity = wander_dir * speed  # 設定速度與方向
	character.last_facing_vec = wander_dir   # 記憶面朝方向
	character.play_animation("run" if is_running else "move", wander_dir) # 播放對應動畫

func _stop_moving():
	is_moving = false        
	timer = 1.0              # 設定停下來休息 1 秒
	character.velocity = Vector2.ZERO        # 速度歸零
	character.play_animation("idle", Vector2.DOWN) # 播放待機動畫

func state_physics_update(delta: float):
	if character.player_node: # 如果漫遊時突然看到玩家
		state_machine.change_state("EnemyRun") # 立刻切換到追擊狀態
		return               

	timer -= delta           # 扣除漫遊計時器
	
	if timer <= 0:           # 時間到了
		if is_moving: _stop_moving()  # 如果原本在走，就停下來
		else: _start_moving()         # 如果原本在停，就開始走

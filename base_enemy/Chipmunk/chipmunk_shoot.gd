extends State # 繼承自狀態模板

@export var bullet_scene: PackedScene # 🌟 記得去面板把 chipmunk_bullet.tscn 拖進來！
@export var burst_count: int = 10     # 企劃設定：一次連射 10 發
@export var fire_rate: float = 0.15   # 射擊間隔：0.15 秒一發
@export var spread_angle: float = 12.0 # 🎯 散射角度：正負 12 度 (數值越大越散)
@export var rest_time: float = 2.0    # 🌟 射完後的休息時間 (2秒)

var shots_fired: int = 0
var shoot_timer: float = 0.0
var is_resting: bool = false # 🌟 休息開關
var rest_timer: float = 0.0  # 🌟 休息倒數計時器

func enter():                     
	character.can_attack = false      # 第一步先沒收攻擊權力
	character.velocity = Vector2.ZERO # 煞車，定在原地準備開火
	
	shots_fired = 0                   # 重置：目前打了 0 發
	shoot_timer = 0.0                 # 計時器歸零 (馬上開第一槍)
	
	# ★ 重新進入 Shoot 時，開始新一輪射擊
	is_resting = false
	rest_timer = 0.0

func state_physics_update(delta: float):
	# 🌟 1️⃣ 如果正在休息，就專心倒數，什麼都不做！
	if is_resting:
		rest_timer -= delta
		if rest_timer <= 0:
			# 休息滿 2 秒了！退回巡邏狀態。
			# (如果玩家還在旁邊，雷達會在下一幀瞬間把它切回 Shoot 繼續下一波)
			state_machine.change_state("Move")
		return # ⚠️ 正在休息時，強制跳出，不准往下執行開槍邏輯
	# 1️⃣ 如果玩家不見了，退回巡邏狀態
	if not character.player_node or not character.can_see_player:
		state_machine.change_state("Move") 
		return

	# 2️⃣ 鎖定玩家：身體與槍管死死盯著玩家
	var aim_dir = (character.player_node.global_position - character.global_position).normalized()
	character.last_facing_vec = aim_dir
	character.play_animation("idle", aim_dir) # 站樁輸出，播 idle 動畫
	
	var aim_pivot = character.get_node_or_null("AimPivot") 
	if aim_pivot:        
		aim_pivot.look_at(character.player_node.global_position) 

	# 3️⃣ 開火計時核心
	shoot_timer -= delta
	if shoot_timer <= 0:
		shoot_timer = fire_rate # 重置冷卻時間
		_fire_bullet(aim_dir)   # 呼叫開槍
		shots_fired += 1
		
		# 🌟 如果 10 發打完了，開啟休息模式！
		if shots_fired >= burst_count:
			is_resting = true       # 打開休息開關
			rest_timer = rest_time  # 設定倒數 2 秒
			# 2秒後歸還攻擊權力
			character.get_tree().create_timer(rest_time).connect("timeout", func(): character.can_attack = true)

func _fire_bullet(base_dir: Vector2):                               

	var bullet = bullet_scene.instantiate() 
	var muzzle = character.get_node_or_null("AimPivot/Muzzle") 
	
	# 🌟 將子彈加入場景樹 (沿用你完美的野豬寫法)
	character.get_tree().current_scene.add_child(bullet)
	
	# 🌟 設定精準起點座標
	if muzzle:
		bullet.global_position = muzzle.global_position
	else:
		bullet.global_position = character.global_position 
		
	# 🎯 【元氣騎士散射邏輯】
	# 把原本筆直的 base_dir，加上一個隨機旋轉的偏角
	var random_angle = deg_to_rad(randf_range(-spread_angle, spread_angle))
	var final_dir = base_dir.rotated(random_angle)
		
	bullet.direction = final_dir  # 賦予子彈最終的飛行方向
	bullet.travel_dir = final_dir # 擊退方向同步         

extends State # 繼承自狀態模板

# -------------------------------------------------------------------------
# ⚙️ 連發散射設定面板
# -------------------------------------------------------------------------
@export var bullet_scene: PackedScene  # 彈藥庫：記得把 chipmunk_bullet.tscn 拖進來
@export var burst_count: int = 10      # 連發數量：一次連射 10 發
@export var fire_rate: float = 0.15    # 射擊間隔：0.15 秒一發
@export var spread_angle: float = 12.0 # 散射角度：正負 12 度隨機偏移
@export var rest_time: float = 2.0     # 休息時間：打完一輪後的冷卻秒數

# -------------------------------------------------------------------------
# 🔒 狀態內部計數與計時器
# -------------------------------------------------------------------------
var shots_fired: int = 0
var shoot_timer: float = 0.0
var is_resting: bool = false # 休息狀態開關
var rest_timer: float = 0.0  # 休息倒數計時器

# -------------------------------------------------------------------------
# 🎬 狀態進出管理
# -------------------------------------------------------------------------
func enter():                   
	character.can_attack = false      # 沒收攻擊權力，防止重複觸發
	character.velocity = Vector2.ZERO # 原地煞車，準備站樁開火
	
	shots_fired = 0                   # 重置已發射子彈數
	shoot_timer = 0.0                 # 計時器歸零 (馬上開第一槍)
	is_resting = false
	rest_timer = 0.0

func exit():
	# 防呆機制：確保無論任何原因離開此狀態，都會歸還攻擊權限
	character.can_attack = true

# -------------------------------------------------------------------------
# 🔄 物理更新迴圈 (控制連射與休息切換)
# -------------------------------------------------------------------------
func state_physics_update(delta: float):
	# 1️⃣ 視野檢查：如果玩家跑出視線，退回 Move 巡邏狀態
	if not character.player_node or not character.can_see_player:
		state_machine.change_state("Move") 
		return

	# 2️⃣ 休息階段：播放 idle 動畫並原地倒數 2 秒
	if is_resting:
		character.play_animation("idle", character.last_facing_vec)
		rest_timer -= delta
		
		# 休息滿 2 秒，重置開火參數，下一幀直接繼續執行下方的 attack！
		if rest_timer <= 0:
			is_resting = false
			shots_fired = 0
			shoot_timer = 0.0
		return # 休息期間強制跳出，不執行下方開槍邏輯

	# 3️⃣ 鎖定玩家：身體與槍管盯著玩家，並播放 attack 動畫
	var aim_dir = (character.player_node.global_position - character.global_position).normalized()
	character.last_facing_vec = aim_dir
	character.play_animation("attack", aim_dir)
	
	var aim_pivot = character.get_node_or_null("AimPivot") 
	if aim_pivot:        
		aim_pivot.look_at(character.player_node.global_position) 

	# 4️⃣ 開火計時核心
	shoot_timer -= delta
	if shoot_timer <= 0:
		shoot_timer = fire_rate # 重置單發冷卻
		_fire_bullet(aim_dir)   # 呼叫開槍
		shots_fired += 1
		
		# 打滿 10 發，開啟休息模式並立刻切換為 idle 動畫
		if shots_fired >= burst_count:
			is_resting = true
			rest_timer = rest_time
			character.play_animation("idle", character.last_facing_vec)

# -------------------------------------------------------------------------
# 🚀 子彈生成與散射計算
# -------------------------------------------------------------------------
func _fire_bullet(base_dir: Vector2):                                
	var bullet = bullet_scene.instantiate() 
	var muzzle = character.get_node_or_null("AimPivot/Muzzle") 
	
	# 將子彈獨立加入當前場景樹
	character.get_tree().current_scene.add_child(bullet)
	
	# 設定子彈生成的槍口起點座標
	if muzzle:
		bullet.global_position = muzzle.global_position
	else:
		bullet.global_position = character.global_position 
		
	# 散射邏輯：在基準方向加上正負 spread_angle 的隨機偏角
	var random_angle = deg_to_rad(randf_range(-spread_angle, spread_angle))
	var final_dir = base_dir.rotated(random_angle)
		
	bullet.direction = final_dir  # 賦予子彈飛行方向
	bullet.travel_dir = final_dir # 同步擊退方向

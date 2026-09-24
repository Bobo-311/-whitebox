extends State # 繼承狀態模板

@export_category("💥 鐵門頂撞設定")

# 【衝撞數值設定】
@export var push_speed: float = 400.0      # 往前頂的爆發速度 (越高撞越快)
@export var push_duration: float = 0.25    # 頂出去的「持續時間」(0.25 秒很快！)
@export var rest_duration: float = 1.5     # 頂完之後要在原地發呆喘氣多久 (給玩家輸出的破綻)

# 【動畫設定】
@export_group("動畫設定")
@export var push_anim: String = "run"      # 衝撞時要播的動畫 (例如 run 或 attack)
@export var rest_anim: String = "idle"     # 喘氣時要播的動畫 (預設為 idle)

var timer: float = 0.0 # 內部的倒數計時器
var push_direction: Vector2 = Vector2.ZERO # 記錄要往哪個方向撞過去
var is_resting: bool = false # 內部開關：記錄現在是「正在撞」還是「正在喘氣」

func enter():
	# 一進入這個狀態，先把計時器設定為「衝刺時間」
	timer = push_duration
	is_resting = false # 標記為「正在衝刺中」
	
	# 鎖定方向：鎖定發動攻擊那一瞬間，玩家所在的方位
	if character.player_node:
		push_direction = (character.player_node.global_position - character.global_position).normalized()
	else:
		push_direction = character.last_facing_vec

	# 1. 殺意全開：開啟鐵門正前方的 Hitbox (攻擊判定框)
	var hitbox = character.get_node_or_null("Hitbox")
	if hitbox:
		hitbox.monitoring = true # 允許偵測物體
		for child in hitbox.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", false) # 把碰撞牆打開
				
	# 2. 播放衝撞的動畫 (run)
	character.play_animation(push_anim, push_direction)

func state_physics_update(delta: float):
	timer -= delta # 每一幀都扣除一點點時間

	# 【階段 A：正在往前撞】
	if not is_resting:
		# 給予極高的爆發速度
		character.velocity = push_direction * push_speed
		
		# 🌟【新增這行】強制每幀檢查有沒有撞到玩家！

		# 如果衝刺時間 (0.25秒) 結束了
		if timer <= 0:
			is_resting = true # 把狀態切換成「正在喘氣」
			timer = rest_duration # 把計時器重新設定為「喘氣時間」(1.2秒)
			
			character.velocity = Vector2.ZERO # 物理瞬間煞車
			character.play_animation(rest_anim, push_direction) # 播放發呆動畫
			
			# 非常重要：關閉 Hitbox，這樣他站著發呆時才不會傷到玩家
			_disable_hitbox()
			
	# 【階段 B：正在原地喘氣】
	else:
		character.velocity = Vector2.ZERO # 確保喘氣時絕對不會動
		
		# 如果喘氣時間 (1.2秒) 結束了
		if timer <= 0:
			# 恢復理智，大腦切換回 Chase 狀態，繼續下一輪的逼近！
			state_machine.change_state("Chase")

# 當這個狀態因為任何原因被中斷時 (例如死掉、或是切換狀態)
func exit():
	_disable_hitbox() # 買個保險，確保攻擊判定框一定有被關掉

# 專門用來安全關閉 Hitbox 的小工具函數
func _disable_hitbox():
	var hitbox = character.get_node_or_null("Hitbox")
	if hitbox:
		hitbox.monitoring = false
		for child in hitbox.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)

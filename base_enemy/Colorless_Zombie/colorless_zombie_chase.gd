extends State

# ==========================================
# ⚙️ 遠程走位設定 (開放給 Inspector 面板微調)
# ==========================================
@export_group("遠程走位設定")
@export var chase_speed: float = 120.0       # 遠程怪通常比較脆，移動速度可以設慢一點
@export var shooting_distance: float = 250.0 # 🌟 核心距離限制：距離玩家多近時要停下來開火？

var locked_jump_dir: Vector2 = Vector2.ZERO  # 🌟 記住起跳瞬間鎖定的方向 (防止在半空中轉彎)

# ==========================================
# 🎬 狀態進入 (剛切換到追擊狀態的第一幀)
# ==========================================
func enter():
	# 🌟【本次修改 1：初始化起跳方向】
	# 剛進入追擊時，先繼承角色最後面對的方向，避免第一幀方向為 (0,0)
	locked_jump_dir = character.last_facing_vec
	
	# 播放跑步/追擊動畫
	character.play_animation("move", character.last_facing_vec) 
	
	# 🌟【正規作法：關閉近戰傷害】
	# 因為牠是遠程怪物，肉體碰到玩家不應該扣血 (對玩家才公平)
	# 所以在追擊過程中，強制把近戰碰撞框 (Hitbox) 關掉
	if character.hitbox:
		character.hitbox.set_deferred("monitoring", false)

# ==========================================
# 🔄 物理更新 (每秒執行 60 次的思考迴圈)
# ==========================================
func state_physics_update(_delta: float):
	
	# 💡 1. 視野與目標丟失判定 (防呆)
	# 如果玩家死掉了 (player_node 不存在)，或是玩家跑出視線被牆壁擋住
	if not character.player_node or not character.can_see_player:
		# 放棄追擊，切換回發呆/漫遊狀態
		state_machine.change_state("Move")
		return

	# 🌟 2. 射程判定 (遠程大腦的核心)
	# 實時計算怪物自己與玩家之間的「直線距離」
	var dist = character.global_position.distance_to(character.player_node.global_position)
	
	# 🌟【本次修改 2：加上 character.is_jump_grounded() 落地檢查】
	# 如果進入了 250 像素射程內，而且青蛙目前「已經雙腳落地 (不在半空中)」：
	# 才停止走位、切換到攻擊狀態，避免跳到一半在半空中突兀瞬間開火！
	if dist <= shooting_distance and character.is_jump_grounded():
		state_machine.change_state("Attack")
		return

	# 🏃 3. 追擊移動邏輯 (還沒進入射程時)
	# 🌟【本次修改 3：起跳方向鎖定 + 呼叫老爸的影格跳躍調度器】
	# 只有當青蛙「手腳撐在地板上蓄力 (第 1~4 格)」時，才重新瞄準玩家並更新動畫方向！
	# 一旦雙腳離地騰空 (第 5, 6, 7, 0 格)，就鎖死 locked_jump_dir 直線飛躍，絕不在空中轉彎！
	if character.is_jump_grounded() or locked_jump_dir == Vector2.ZERO:
		locked_jump_dir = (character.player_node.global_position - character.global_position).normalized()
		
		# 隨時更新怪物最後面朝的方向，讓下一個狀態（Attack / Pant）能記住面向
		character.last_facing_vec = locked_jump_dir
		
		# 傳入移動方向，讓老爸自動切換 move_left_up / move_right_down 等四向移動動畫
		character.play_animation("move", locked_jump_dir)
	
	# 🌟 把原本寫死的 character.velocity = dir * chase_speed 替換成這行：
	# 交給老爸 BaseEnemy 的 apply_locomotion()，自動依影格決定「撐地停頓 (速度 0)」或「騰空衝刺」！
	character.apply_locomotion(locked_jump_dir, chase_speed)

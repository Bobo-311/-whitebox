extends State

# ==========================================
# ⚙️ 遠程走位設定 (開放給 Inspector 面板微調)
# ==========================================
@export_group("遠程走位設定")
@export var chase_speed: float = 120.0       # 遠程怪通常比較脆，移動速度可以設慢一點
@export var shooting_distance: float = 500.0 # 🌟 核心距離限制：距離玩家多近時要停下來開火？

# ==========================================
# 🎬 狀態進入 (剛切換到追擊狀態的第一幀)
# ==========================================
func enter():
	# 播放跑步/追擊動畫
	character.play_animation("run") 
	
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
	
	if dist <= shooting_distance:
		# 如果進入了我們設定的 250 像素射程內...
		# 停止走位，立刻切換到攻擊狀態，準備吐酸液！
		state_machine.change_state("Attack")
		return

	# 🏃 3. 追擊移動邏輯 (還沒進入射程時)
	# 算出從怪物指向玩家的方向向量 (normalized 會把它變成基準長度 1 的方向指針)
	var dir = (character.player_node.global_position - character.global_position).normalized()
	
	# 賦予怪物移動速度
	character.velocity = dir * chase_speed
	# 記憶怪物最後面朝的方向，確保動畫播放正確
	character.last_facing_vec = dir
	# 播放對應方向的跑步動畫
	character.play_animation("run", dir)

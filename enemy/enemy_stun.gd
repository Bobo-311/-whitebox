extends State                    # 繼承自狀態機的狀態模板 enemy_stun

var stun_timer: float = 3.0      # 宣告浮點數：暈眩計時器，預設暈眩 3 秒
var flash_tween: Tween           # 宣告 Tween 控制器：用來處理紫紅色閃爍特效

func enter():                    # 內建函數：當野豬撞牆切換到這個狀態時執行一次
	stun_timer = 3.0             # 重置暈眩倒數時間為 3 秒
	
	# 播放待機動畫，並傳入最後的面朝方向，確保野豬不會在暈倒時突然轉向
	character.play_animation("idle", character.last_facing_vec)  

	# --- 啟動紫紅色閃爍迴圈 ---
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 如果上次有殘留的特效就強制砍掉
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立新的動畫控制器並綁定到野豬身上
	flash_tween.set_loops()      # 設定動畫為無限迴圈播放
	
	# 使用 self_modulate 改變顏色，這樣不會干擾到受傷時的全身閃光
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.MAGENTA, 0.2) # 0.2 秒漸變為紫紅色
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.2)   # 0.2 秒恢復為純白色

func state_physics_update(delta: float): # 內建函數：物理引擎每一幀執行一次
	stun_timer -= delta          # 讓計時器扣除這一幀的時間
	
	# 🌟 擊退煞車系統：讓被玩家砍退的野豬在 0.15 的權重下慢慢停住，製造摩擦感
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.15)
		
	if stun_timer <= 0:          # 條件判斷：如果 3 秒的暈眩時間結束了
		state_machine.change_state("EnemyRun") # 命令大腦切換回狂奔追擊狀態 (EnemyRun)

func exit():                     # 內建函數：當大腦準備切換到下一個狀態前執行一次
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 強行停止所有的紫光閃爍特效
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制將身體顏色恢復成預設的純白色
	
	# 🌟 核心修正：野豬暈完了，在離開這個狀態的瞬間，必須把攻擊權限還給它！
	character.can_attack = true 
	print("【系統】野豬撞牆暈醒了，恢復攻擊權限，準備再次衝撞！") # 在後台印出提示訊息

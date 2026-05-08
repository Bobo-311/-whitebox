extends State                    # 繼承自狀態模板

var stun_timer: float = 3.0      # 暈眩計時器：預設暈眩 3 秒
var flash_tween: Tween           # 用來處理閃爍動畫的節點

func enter():                    # 進入暈眩狀態時執行
	stun_timer = 3.0             # 重置暈眩時間為 3 秒
	character.play_animation("idle")  # 播放待機動畫 (假裝暈倒站不穩)

	# --- 青藍/紫紅色閃爍迴圈 ---
	if flash_tween: flash_tween.kill() # 砍掉舊的閃爍動畫
	flash_tween = character.get_tree().create_tween() # 建立新的 Tween
	flash_tween.set_loops()      # 設定為無限迴圈
	flash_tween.tween_property(character.animated_sprite_2d, "modulate", Color.MAGENTA, 0.2) # 0.2秒變紫紅
	flash_tween.tween_property(character.animated_sprite_2d, "modulate", Color.WHITE, 0.2)   # 0.2秒變白

func state_physics_update(delta: float): # 每一幀的物理更新
	stun_timer -= delta          # 扣除暈眩時間
	
	# 讓剛撞牆或被打退的野豬，在地上摩擦慢慢停下
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.1)
		
	if stun_timer <= 0:          # 如果 3 秒暈眩時間結束
		state_machine.change_state("EnemyRun") # 醒來，直接切換到狂奔追擊狀態

func exit():                     # 離開暈眩狀態時的保險機制
	if flash_tween: flash_tween.kill() # 砍掉閃爍動畫
	character.animated_sprite_2d.modulate = Color.WHITE # 強制恢復原本的白色

extends State                    # 繼承自狀態模板

var pant_timer: float = 1.5      # 喘氣時間 (會被攻擊腳本覆蓋修改)
var flash_tween: Tween           # 處理閃爍動畫的節點

func enter():                    # 進入喘氣狀態時執行
	# --- 綠白相間閃爍 (代表破綻) ---
	if flash_tween: flash_tween.kill() # 砍掉舊的動畫
	flash_tween = character.get_tree().create_tween() # 建立新的動畫
	flash_tween.set_loops()      # 設定為無限迴圈
	flash_tween.tween_property(character.animated_sprite_2d, "modulate", Color.GREEN, 0.2) # 變綠
	flash_tween.tween_property(character.animated_sprite_2d, "modulate", Color.WHITE, 0.2) # 變白

func state_physics_update(delta: float): # 每一幀的物理更新
	pant_timer -= delta          # 扣除喘氣時間

	# 慣性煞車：讓衝過頭的野豬平滑煞車
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.1)

	# 根據滑行速度切換動畫
	if character.velocity.length() > 50: # 速度還很快
		character.play_animation("move") # 播放移動(滑行)
	else:                                # 快停下來了
		character.play_animation("idle") # 播放待機(喘氣)

	if pant_timer <= 0:          # 如果喘氣時間到了
		state_machine.change_state("EnemyRun") # 時間到，直接切回追擊狀態

func exit():                     # 離開狀態時執行
	if flash_tween: flash_tween.kill() # 關閉閃爍動畫
	character.animated_sprite_2d.modulate = Color.WHITE # 恢復原本的白色

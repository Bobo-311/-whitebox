extends State                    # 繼承狀態模板

var heal_timer: float = 2.0      # 詠唱時間：2 秒
var flash_tween: Tween           # 閃爍動畫
var is_healing_success: bool = false # 開關：記錄這次補血是不是「平安完成」？

func enter():                    # 按下 H 鍵進場時
	is_healing_success = false   # 預設為尚未成功
	
	# 1. 審查資格：向身體請款 50 點能量
	var can_heal = character.use_energy(50) 
	
	if not can_heal:             # 如果能量不夠
		state_machine.change_state("PlayerIdle") # 拒絕補血，退回待機
		return                   # 終止執行
		
	# 2. 開始罰站詠唱
	character.velocity = Vector2.ZERO # 速度歸零定在原地
	character.play_animation("idle")  # 播放待機動畫
	heal_timer = 2.0                  # 重置 2 秒計時器
	
	# 啟動淺綠色閃爍動畫 (代表正在凝聚治癒力量)
	if flash_tween and flash_tween.is_valid(): flash_tween.kill()
	flash_tween = character.get_tree().create_tween().bind_node(character)
	flash_tween.set_loops()
	flash_tween.tween_property(character.animated_sprite_2d, "modulate", Color.LIGHT_GREEN, 0.2)
	flash_tween.tween_property(character.animated_sprite_2d, "modulate", Color.WHITE, 0.2)

func state_physics_update(delta: float): # 詠唱時每一幀更新
	heal_timer -= delta          # 倒數計時
	
	if heal_timer <= 0:          # 平安撐過 2 秒
		_finish_healing()        # 呼叫順利結算

func _finish_healing():          # 結算補血功能
	is_healing_success = true    # 標記為順利完成 (退場就不會退錢了)
	
	var heal_amount = int(character.max_hp * 0.7) # 計算補血量：最大血量的 70%
	character.current_hp += heal_amount           # 把血補上去
	
	if character.current_hp > character.max_hp:   # 防呆：不能超過血量上限
		character.current_hp = character.max_hp
		
	print("補血成功！目前血量：", character.current_hp)
	character.update_hp_bar()    # 更新 UI 血條
	state_machine.change_state("PlayerIdle") # 切回自由狀態

func exit():                     # 離開狀態時執行
	if flash_tween and flash_tween.is_valid(): flash_tween.kill()
	character.animated_sprite_2d.modulate = Color.WHITE # 恢復正常顏色
	
	# 🌟 神級判定：如果離開時「尚未成功」(代表這 2 秒內被打飛了)
	if not is_healing_success:
		print("【系統】補血遭到中斷！退還 50 點能量。")
		character.add_energy(50) # 把剛進場扣的 50 點能量退還給玩家！

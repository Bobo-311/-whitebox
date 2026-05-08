extends State # 繼承自狀態模板，讓腳本可被大腦呼叫

var pant_timer: float = 0.0      # 宣告浮點數計時器：記錄還要喘氣多久 (這數值由 Attack 腳本設定)
var flash_tween: Tween           # 宣告 Tween 動畫控制器，用來處理綠/黑閃爍特效
var is_shaking_head: bool = false # 宣告布林值開關：判斷是否已進入最後 0.5 秒的「甩頭階段」

func enter(): # 當剛切換到喘氣狀態時執行一次
	is_shaking_head = false # 開局先將甩頭開關重置為 false，代表現在是正常的喘氣階段
	
	# 🌟 溜冰修正一：不要在這裡把速度歸零！
	# 如果這裡寫 character.velocity = Vector2.ZERO，剛傳進來的擊退力道就會瞬間被吃掉。
	# 我們讓它保留力道，交給 update 裡面的摩擦力來煞車！
	
	character.play_animation("idle", character.last_facing_vec) # 播放待機動畫，視覺上假裝正在喘氣
	
	# --- 啟動第一階段：喘氣綠光閃爍 ---
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 清除前一次殘留的特效
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立綁定野豬的動畫控制器
	flash_tween.set_loops() # 指示動畫無限迴圈播放
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.GREEN, 0.2) # 花 0.2 秒把身體變綠
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.2) # 花 0.2 秒變回白色

func state_physics_update(delta: float): # 每一幀的物理更新
	pant_timer -= delta # 讓喘氣計時器每一幀扣除時間，開始倒數
	
	# --- 🌟 溜冰修正二：加強地面摩擦力 (煞車系統) ---
	# 【特殊函數解釋】：lerp(目標值, 權重) 是「線性插值」。
	# 它的功用是：把「目前的速度」，以你設定的權重比例，慢慢拉向「目標值 (Vector2.ZERO，也就是靜止)」。
	# 權重越接近 1，煞車越猛。我們把原本的 0.1 改成 0.4，野豬就會在短短幾幀內瞬間煞住，製造沉重感！
	character.velocity = character.velocity.lerp(Vector2.ZERO, 0.4) 
	
	# --- 關鍵邏輯：檢查是否進入最後 0.5 秒 (甩頭階段) ---
	if pant_timer <= 0.5 and not is_shaking_head: # 條件：如果時間小於等於 0.5 秒，且甩頭開關還沒打開
		is_shaking_head = true # 把開關打開，確保這段特效代碼只會執行一次
		
		if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 停止第一階段的綠光閃爍
		
		# --- 啟動第二階段：甩頭黑白閃爍 ---
		flash_tween = character.get_tree().create_tween().bind_node(character) # 重新建立動畫控制器
		flash_tween.set_loops() # 無限迴圈播放
		flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color(0.2, 0.2, 0.2), 0.1) # 花 0.1 秒急速變深灰/黑
		flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.1) # 花 0.1 秒急速變回白色
		
		print("【系統】野豬喘氣結束，進入最後 0.5 秒甩頭回神階段！") # 後台提示
		
	# --- 檢查狀態是否徹底結束 ---
	if pant_timer <= 0: # 條件：如果計時器徹底歸零
		state_machine.change_state("EnemyRun") # 命令大腦切換回追逐狀態 (EnemyRun)

func exit(): # 當野豬準備離開這個喘氣狀態時執行的保險機制
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 強行砍掉所有閃爍特效
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制將野豬身體顏色恢復成純白色
	
	character.can_attack = true # 野豬喘完氣了，把攻擊權限還給牠！
	print("【系統】野豬休息完畢，重新獲得攻擊權力！") # 後台提示

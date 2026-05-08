extends State                    # 繼承自狀態模板

@export var bullet_scene: PackedScene # 提供一個插槽，讓你在編輯器把子彈的場景檔 (tscn) 拖進來

var shoot_timer: float = 0.5     # 計時器：瞄準需要 0.5 秒
var has_shot: bool = false       # 標記：這波是不是已經射過了？
var flash_tween: Tween           # 用來處理閃爍的 Tween

func enter():                    # 切換到射擊狀態時執行
	character.can_attack = false # 第一步先沒收攻擊權力，進入冷卻
	character.velocity = Vector2.ZERO # 煞車，定在原地準備吐子彈
	shoot_timer = 0.5            # 重置瞄準時間為 0.5 秒
	has_shot = false             # 重置射擊標記為「未射擊」
	
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 清除舊動畫
	flash_tween = character.get_tree().create_tween().bind_node(character) # 建立新 Tween
	flash_tween.set_loops()      # 設定為無限迴圈
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.RED, 0.1) # 0.1秒變紅
	flash_tween.tween_property(character.animated_sprite_2d, "self_modulate", Color.WHITE, 0.1) # 0.1秒變白 (高頻率閃爍)

func state_physics_update(delta: float): # 每一幀的物理更新
	if shoot_timer > 0:          # 階段一：瞄準階段
		shoot_timer -= delta     # 扣除瞄準時間
		
		if character.player_node:# 如果玩家還在視野內
			var aim_dir = (character.player_node.global_position - character.global_position).normalized() # 算出瞄準方向
			character.last_facing_vec = aim_dir # 更新野豬身體面朝方向
			character.play_animation("idle", aim_dir) # 播放待機動畫，假裝在瞄準
			
			var aim_pivot = character.get_node_or_null("AimPivot") # 尋找掛載槍口旋轉軸 (AimPivot)
			if aim_pivot:        # 如果有找到
				aim_pivot.look_at(character.player_node.global_position) # 呼叫神級函數 look_at，讓旋轉軸永遠死死盯著玩家座標
			
	else:                        # 階段二：發射瞬間 (時間到了)
		if not has_shot:         # 如果還沒發射過
			_fire_bullet()       # 呼叫發射子彈函數

func _fire_bullet():             # 處理發射子彈的邏輯
	has_shot = true              # 標記為「已經射擊」
	
	if bullet_scene == null:     # 防呆：如果編輯器裡忘記拖入子彈場景
		print("【警告】你忘記把 EnemyBullet.tscn 拖進 EnemyShoot 狀態裡了！") # 印出警告
		_end_shoot()             # 結束射擊流程
		return                   # 提早跳出
		
	var bullet = bullet_scene.instantiate() # 依照你給的藍圖，在記憶體裡「實體化」製造出一顆子彈
	
	var muzzle = character.get_node_or_null("AimPivot/Muzzle") # 找尋槍口 (Muzzle) 節點
	
	if muzzle:                   # 如果有槍口
		bullet.global_position = muzzle.global_position # 把子彈放在槍口的絕對座標上
	else:                        # 如果沒找到槍口
		bullet.global_position = character.global_position # 備用方案：從野豬肚子中間生出子彈
	
	bullet.direction = character.last_facing_vec # 把子彈的飛行方向設定為野豬最後的面朝方向
	bullet.travel_dir = bullet.direction         # 同時把擊退方向也設為同一邊
	
	character.get_tree().current_scene.add_child(bullet) # 將這顆設定好的子彈，正式加入到遊戲世界(場景樹)中
	
	_end_shoot()                 # 呼叫結束射擊流程

func _end_shoot():               # 射擊完畢後的善後
	character.get_tree().create_timer(3.0).connect("timeout", func(): character.can_attack = true) # 啟動 3 秒計時器，時間到恢復攻擊權力
	
	await character.get_tree().create_timer(0.5).timeout # 魔法指令：在這裡強制暫停等待 0.5 秒 (射擊後搖硬直)
	
	var pant_state = state_machine.states.get("enemypant") # 從大腦拿出喘氣狀態
	if pant_state: pant_state.pant_timer = 1.5   # 把喘氣時間設為 1.5 秒
	state_machine.change_state("EnemyPant")      # 切換到喘氣狀態

func exit():                     # 離開射擊狀態時的保險機制
	if flash_tween and flash_tween.is_valid(): flash_tween.kill() # 砍掉紅色閃爍
	character.animated_sprite_2d.self_modulate = Color.WHITE # 強制恢復白色

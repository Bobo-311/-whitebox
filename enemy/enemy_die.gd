extends State # 繼承自狀態模板 enemy_die

func enter(): # 進入死亡狀態時執行
	character.velocity = Vector2.ZERO # 物理速度徹底歸零，不再滑行
	
	# 🌟 視覺修正 1：死掉瞬間變半透明，讓屍體「不太明顯」(0.5 代表 50% 透明度)
	character.modulate.a = 0.5 
	
	var anim_dir = character.last_facing_vec # 沿用野豬原本的面朝方向播放動畫
	
	var push_dir = Vector2.ZERO # 宣告變數：用來計算物理推擠的方向
	if DataManager and DataManager.player_node: # 條件判斷：確保大腦與玩家實體都存在
		push_dir = (character.global_position - DataManager.player_node.global_position).normalized() # 計算從玩家往野豬推的方向
		
	# 瞬間退後一步：使用物理位移，撞到牆會自動卡住不穿透
	if push_dir != Vector2.ZERO: # 如果有算出推擠方向
		character.move_and_collide(push_dir * 60.0) # 往後蹬 40 像素的距離
	
	character.play_animation("dead", anim_dir) # 播放倒地死亡動畫
	
	var collision = character.get_node_or_null("CollisionShape2D") # 抓取肉體碰撞
	if collision: collision.set_deferred("disabled", true) # 安全關閉物理碰撞，讓玩家可直接踩過屍體
		
	var hitbox = character.get_node_or_null("Hitbox/CollisionShape2D") # 抓取嘴巴攻擊判定
	if hitbox: hitbox.set_deferred("disabled", true) # 關閉攻擊區，確保死後不會咬人
	
	var hurtbox = character.get_node_or_null("Hurtbox/CollisionShape2D") # 抓取受傷區
	if hurtbox: hurtbox.set_deferred("disabled", true) # 關閉受傷區，防止鞭屍回能量
	
	var camera = character.get_tree().get_first_node_in_group("camera") # 尋找場景中的攝影機
	if camera: camera.apply_shake(50.0) # 呼叫畫面震動，增加死亡打擊感
	
	_start_despawn() # 呼叫屍體消失流程

func _start_despawn(): # 處理屍體消失的計時與動畫
	await character.get_tree().create_timer(10.0).timeout # 讓半透明的屍體在原地留存 10 秒鐘
	
	var tween = character.get_tree().create_tween() # 建立一個新的動畫控制器
	# 🌟 視覺修正 2：從剛死掉的半透明 (0.5)，花 1.5 秒慢慢漸隱到完全消失 (0.0)
	tween.tween_property(character, "modulate:a", 0.0, 1.5) 
	
	await tween.finished # 等待漸隱動畫播放結束
	character.queue_free() # 徹底從記憶體中刪除野豬節點

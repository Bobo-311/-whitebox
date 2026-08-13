#繼承自狀態模板 base_die
extends State # 繼承自狀態模板 enemy_die

func enter(): # 進入死亡狀態時執行
	character.velocity = Vector2.ZERO # 物理速度徹底歸零，不再滑行
	
	# 🌟 視覺修正 1：死掉瞬間變半透明，讓屍體「不太明顯」(0.5 代表 50% 透明度)
	character.modulate.a = 0.5 
	
	var anim_dir = character.last_facing_vec # 沿用野豬原本的面朝方向播放動畫
	
	var push_dir = Vector2.ZERO # 宣告變數：用來計算物理推擠的方向
	
	if DataManager and DataManager.player_node: # 條件判斷：確保大腦與玩家實體都存在
		push_dir = (character.global_position - DataManager.player_node.global_position).normalized() # 計算推擠方向
		
		# 🌟🌟🌟 [本次改動核心] 🌟🌟🌟
		# 既然確定玩家存在，立刻通知玩家：「我死掉了，你可以結算擊殺效果了！」
		# 使用 has_method 防呆，確保玩家身上真的有寫這個函數才呼叫，避免報錯
		#has_method() 是一個用來檢查特定物件是否擁有某個函式（方法）的內建函式。防禦性檢查
		if DataManager.player_node.has_method("on_enemy_killed"):
			DataManager.player_node.on_enemy_killed()
			
	# 瞬間退後一步：使用物理位移，撞到牆會自動卡住不穿透
	if push_dir != Vector2.ZERO: 
		character.move_and_collide(push_dir * 60.0) 
	
	character.play_animation("dead", anim_dir) # 播放倒地死亡動畫
	
	var collision = character.get_node_or_null("CollisionShape2D") 
	if collision: collision.set_deferred("disabled", true) # 安全關閉物理碰撞
		
	var hitbox = character.get_node_or_null("Hitbox/CollisionShape2D") 
	if hitbox: hitbox.set_deferred("disabled", true) # 關閉攻擊區
	
	var hurtbox = character.get_node_or_null("Hurtbox/CollisionShape2D") 
	if hurtbox: hurtbox.set_deferred("disabled", true) # 關閉受傷區
	
	var camera = character.get_tree().get_first_node_in_group("camera") 
	if camera: camera.apply_shake(100.0) # 呼叫畫面震動
	
	_start_despawn() # 呼叫屍體消失流程


func _start_despawn(): # 處理屍體消失的計時與動畫
	await character.get_tree().create_timer(10.0).timeout # 讓半透明的屍體在原地留存 10 秒鐘
	
	var tween = character.get_tree().create_tween() # 建立一個新的動畫控制器
	# 🌟 視覺修正 2：從剛死掉的半透明 (0.5)，花 1.5 秒慢慢漸隱到完全消失 (0.0)
	tween.tween_property(character, "modulate:a", 0.0, 1.5) 
	
	await tween.finished # 等待漸隱動畫播放結束
	character.queue_free() # 徹底從記憶體中刪除野豬節點

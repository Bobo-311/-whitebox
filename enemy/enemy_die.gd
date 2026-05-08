extends State                    # 繼承自狀態模板

func enter():                    # 進入死亡狀態時執行
	# 保留 30% 擊退慣性，讓屍體有往後滑倒的感覺
	character.velocity = character.knockback_force * 0.3
	
	# 決定倒地動畫方向 (加上負號，讓它面向玩家死掉)
	var death_dir = -character.knockback_force.normalized()
	if death_dir == Vector2.ZERO: # 如果沒有明確的擊退方向
		death_dir = character.last_facing_vec # 就用最後面朝的方向
	
	character.play_animation("dead", death_dir) # 播放死亡倒地動畫
	
	# 🌟 關閉實體碰撞：避免玩家被野豬的屍體卡住走不過去
	var collision = character.get_node_or_null("CollisionShape2D")
	if collision:
		collision.set_deferred("disabled", true) # 安全關閉碰撞實體
	
	# 呼叫鏡頭震動 (強度 15.0，增加打擊回饋)
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera:
		camera.apply_shake(15.0)
	
	_start_despawn()             # 呼叫屍體消失流程

func _start_despawn():           # 處理屍體消失
	await character.get_tree().create_timer(0.3).timeout # 先讓屍體在地上躺 0.3 秒
	
	# 屍體在 0.5 秒內慢慢變透明 (modulate:a 代表 Alpha 透明度)
	var tween = character.get_tree().create_tween()
	tween.tween_property(character, "modulate:a", 0.0, 0.5)
	
	await tween.finished         # 等待透明動畫播放完畢
	character.queue_free()       # 徹底從記憶體銷毀這隻野豬節點

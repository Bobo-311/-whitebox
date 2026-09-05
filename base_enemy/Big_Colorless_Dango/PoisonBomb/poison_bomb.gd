extends Node2D

@export_category("💣 毒彈飛行設定")
@export var puddle_scene: PackedScene  # 🌟 裝填你要留在地上的「劇毒泥沼 (poison_puddle.tscn)」
@export var flight_time: float = 0.6   # 飛在空中的時間 (太快玩家躲不掉，太慢沒壓迫感，0.6秒是動作遊戲常見的反應時間)
@export var jump_height: float = 80.0  # 拋物線彈跳的高度 (視覺效果，不影響實際落點)

@onready var bomb_sprite = $BombSprite # 抓取骷髏毒彈的圖片

# ==========================================
# 🚀 核心邏輯：啟動拋物線飛行
# ==========================================
# 【業界思考：預判打擊 (Predictive Targeting)】
# 這個函數接收的 target_pos 是一個「絕對死座標」。
# 毒彈一旦起飛，就會死心塌地砸向這個點，絕對不會追蹤玩家。
# 這樣才能給予玩家「看到王吐口水 -> 預判落點 -> 翻滾閃避」的成就感 (如: 黑帝斯、法環)。
func launch_to(target_pos: Vector2) -> void:
	
	# 💀 【視覺細節：智能轉向】
	# 判斷目標落點在左邊還是右邊。如果是右邊，就把骷髏圖片水平翻轉，
	# 確保骷髏的臉永遠朝向飛行的方向，不會出現「後腦勺砸人」的蠢畫面。
	if target_pos.x > global_position.x:
		bomb_sprite.flip_h = true  # 往右飛，骷髏朝右
	else:
		bomb_sprite.flip_h = false # 往左飛，骷髏維持朝左 (原圖方向)

	# 建立一個可以同時執行多個動畫的 Tween
	var tween = create_tween().set_parallel(true)
	
	# 1. 影子與碰撞基準點：貼著地板「直線」滑向目標點
	tween.tween_property(self, "global_position", target_pos, flight_time)
	
	# 2. 毒彈本體：製造「假 3D 拋物線 (Fake 3D Arc)」
	# 【業界思考：2D 景深錯覺】
	# 為了讓平面的 2D 遊戲有「飛在空中」的感覺，影子走直線，但圖片(BombSprite)要往上拉高。
	bomb_sprite.position.y = 0
	
	# 升空階段：(Ease Out = 像丟球一樣，對抗地心引力慢慢減速到最高點)
	tween.tween_property(bomb_sprite, "position:y", -jump_height, flight_time / 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	# 下墜階段：(Ease In = 被地心引力往下拉，加速往下掉)
	tween.chain().tween_property(bomb_sprite, "position:y", 0.0, flight_time / 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# 3. 飛行結束後，呼叫落地碎裂函數
	tween.chain().tween_callback(_shatter_and_spawn_puddle)


# ==========================================
# 💥 落地碎裂與召喚毒沼
# ==========================================
# 【業界思考：職責分離 (Decoupling)】
# 飛行的炸彈只是一個「送貨員」，它本身不帶任何傷害。
# 任務到達後，它負責把真正有傷害的「毒沼」放在地上，然後自己光榮退場。
func _shatter_and_spawn_puddle() -> void:
	# 確保右邊 Inspector 有塞入 poison_puddle.tscn
	if puddle_scene:
		# 1. 實例化生出一攤毒沼
		var puddle = puddle_scene.instantiate()
		
		# 2. 把它加入到這個世界的根節點底下 (避免炸彈消失時把毒沼也帶走)
		get_parent().call_deferred("add_child", puddle)
		
		# 3. 把毒沼的位置，精準放在炸彈剛好落地的位置
		puddle.global_position = global_position
		
	# 任務完成，送貨員(炸彈)自我刪除
	queue_free()

extends Node2D                   # 繼承自 2D 節點，這個節點綁在玩家身上當作發射器skill_01

# 🌟 預載筆尖墨力漣漪特效 (若報錯 Parse Error，請確認檔案是否有存放在 Bullet 資料夾)
const MAGIC_RING = preload("res://Bullet/magic_ring_effect.tscn")

@export var bullet_scene: PackedScene # 屬性欄位：讓你在編輯器拖入技能(子彈)的藍圖

@onready var bullet_spawn: Marker2D = $BulletSpawn # 抓取發射點的座標記號
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D # 音效播放器

# 🌟 抓取槍管/畫筆的精靈圖節點
@onready var sprite_2d: Sprite2D = get_node_or_null("Sprite2D") 

func _process(_delta):           # 每一幀執行
	look_at(get_global_mouse_position()) # 讓發射器永遠死盯著滑鼠游標轉動
	
	if sprite_2d:
		if get_global_mouse_position().x < global_position.x:
			sprite_2d.flip_v = true   # 垂直翻轉
		else:
			sprite_2d.flip_v = false  # 取消翻轉

# 🌟 發射函數
func shoot(buff: float):         
	var bullet = bullet_scene.instantiate() # 照藍圖做出一顆新子彈
	var muzzle = bullet_spawn               # 找出槍口/筆尖
	
	# 🛑 必須先加入場景樹，Godot 才能正確計算 global_position
	get_tree().current_scene.add_child(bullet) 
	bullet.global_position = muzzle.global_position
	
	# 計算子彈飛行方向
	bullet.direction = (get_global_mouse_position() - muzzle.global_position).normalized() 
	bullet.travel_dir = bullet.direction    # 擊退方向
	bullet.shooter = get_parent()           # 記錄發射者
	bullet.received_buff = buff             # 塞入過飽和倍率
	
	# 🌟 生成筆尖墨力漣漪衝擊環
	if MAGIC_RING:
		var ring = MAGIC_RING.instantiate()
		get_tree().current_scene.add_child(ring)
		ring.global_position = muzzle.global_position
		ring.rotation = bullet.direction.angle()

	# 槍管/畫筆後縮動畫
	if sprite_2d:
		sprite_2d.scale.x = 0.7
		var tween = create_tween()
		tween.tween_property(sprite_2d, "scale:x", 1.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 射擊音效
	if audio_stream_player_2d:
		if buff > 1.0:
			audio_stream_player_2d.pitch_scale = randf_range(0.85, 0.92)
		else:
			audio_stream_player_2d.pitch_scale = randf_range(0.96, 1.08)
		audio_stream_player_2d.play()

	# 頓幀
	if DataManager and DataManager.has_method("hitstop"):
		DataManager.hitstop(0.03)

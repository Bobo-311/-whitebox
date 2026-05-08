extends Node2D                   # 繼承自 2D 節點，這個節點綁在玩家身上當作發射器

@export var bullet_scene: PackedScene # 屬性欄位：讓你在編輯器拖入技能(子彈)的藍圖

@onready var bullet_spawn: Marker2D = $BulletSpawn # 抓取發射點的座標記號
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D # 音效播放器

func _process(_delta):           # 每一幀執行
	look_at(get_global_mouse_position()) # 神級函數：讓發射器(槍管)永遠死盯著滑鼠游標轉動
	if get_global_mouse_position().x < global_position.x: # 如果游標跑到角色左邊
		scale.y = -1             # Y軸翻轉，避免槍管和子彈上下顛倒
	else:
		scale.y = 1              # 保持正常

# 🌟 發射函數：接收從 player.gd 傳過來的「過飽和倍率包裹」
func shoot(buff: float):         
	var bullet = bullet_scene.instantiate() # 照藍圖做出一顆新子彈
	var muzzle = bullet_spawn               # 找出槍口
	bullet.global_position = muzzle.global_position # 把子彈放到槍口上
	
	# 計算子彈飛行方向：(滑鼠位置 - 槍口位置) 的標準化向量
	bullet.direction = (get_global_mouse_position() - muzzle.global_position).normalized() 
	bullet.travel_dir = bullet.direction    # 擊退方向同上
	
	bullet.shooter = get_parent()           # 記錄發射者是這支槍管的主人(玩家)，避免打到自己
	
	bullet.received_buff = buff             # 🌟 核心傳遞：把收到的倍率包裹(1.0或1.5)塞進子彈裡
	
	get_tree().current_scene.add_child(bullet) # 把子彈正式加入遊戲畫面
	audio_stream_player_2d.play()              # 播音效

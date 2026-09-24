extends StaticBody2D

@export var open_texture: Texture2D 
var is_opened: bool = false 
var can_interact: bool = false 
var can_show_block_msg: bool = false # 🌟 紀錄是否在反向區域內

@onready var sprite = $Sprite2D
@onready var solid_collision = $CollisionPolygon2D
@onready var unlock_zone = $UnlockZone
@onready var block_zone = $BlockZone       # 🌟 綁定反向區
@onready var prompt_icon = $PromptIcon     # 🌟 綁定 E 鍵圖示
@onready var block_label = $BlockLabel     # 🌟 綁定文字提示

func _ready() -> void:
	# 預設先隱藏 UI
	prompt_icon.hide()
	block_label.hide()
	
	# 連接訊號
	unlock_zone.body_entered.connect(_on_unlock_zone_body_entered)
	unlock_zone.body_exited.connect(_on_unlock_zone_body_exited)
	block_zone.body_entered.connect(_on_block_zone_body_entered)
	block_zone.body_exited.connect(_on_block_zone_body_exited)

# ==========================================
# 🟢 正面解鎖區邏輯 (顯示 E 按鍵)
# ==========================================
func _on_unlock_zone_body_entered(body: Node2D) -> void:
	if is_opened: return
	if body is Player:
		can_interact = true
		prompt_icon.show() # 顯示 E 鍵提示

func _on_unlock_zone_body_exited(body: Node2D) -> void:
	if body is Player:
		can_interact = false
		prompt_icon.hide() # 隱藏 E 鍵提示

# ==========================================
# 🔴 反向阻擋區邏輯 (準備顯示提示字)
# ==========================================
func _on_block_zone_body_entered(body: Node2D) -> void:
	if is_opened: return
	if body is Player:
		can_show_block_msg = true
		prompt_icon.show() # 也可以在這一側顯示 E 鍵，引誘玩家按

func _on_block_zone_body_exited(body: Node2D) -> void:
	if body is Player:
		can_show_block_msg = false
		prompt_icon.hide()
		block_label.hide() # 離開時立刻把字收起來

# ==========================================
# 🎮 按鍵偵測與動畫
# ==========================================
func _input(event: InputEvent) -> void:
	if is_opened: return
	
	if event.is_action_pressed("interact"):
		# 如果在正面，開門！
		if can_interact:
			open_door()
			
		# 🌟 如果在反面，顯示提示文字！
		elif can_show_block_msg:
			show_block_message()

func open_door() -> void:
	is_opened = true
	can_interact = false
	can_show_block_msg = false
	
	prompt_icon.hide()
	block_label.hide()
	
	if open_texture:
		sprite.texture = open_texture
		
	solid_collision.set_deferred("disabled", true)
	
	# 開門後，為了效能可以直接把兩個感應區關掉
	unlock_zone.set_deferred("monitoring", false)
	block_zone.set_deferred("monitoring", false)

# 🌟 新增：用 Tween 做一個文字浮現又消失的動畫
func show_block_message() -> void:
	prompt_icon.hide() # 按了之後把 E 鍵先藏起來
	block_label.modulate.a = 0.0 # 透明度歸零
	block_label.show()
	
	# 創建一個平滑動畫 (淡入 -> 停留 -> 淡出)
	var tween = create_tween()
	tween.tween_property(block_label, "modulate:a", 1.0, 0.2) # 0.2 秒淡入
	tween.tween_interval(1.5) # 停留 1.5 秒
	tween.tween_property(block_label, "modulate:a", 0.0, 0.3) # 0.3 秒淡出
	
	# 動畫結束後，如果玩家還站在這，就把 E 鍵叫回來
	tween.tween_callback(func():
		block_label.hide()
		if can_show_block_msg:
			prompt_icon.show()
	)

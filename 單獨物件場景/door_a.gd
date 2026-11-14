extends StaticBody2D

@export_group("🔑 門鎖與劇本設定")
@export var key_flag: String = "got_key"                # 🌟 檢查大腦裡有沒有這個鑰匙旗標 (也可填小木屋劇本名如 "A017")
@export var locked_timeline: String = "door_locked"     # 🌟 沒鑰匙時按 E 播的劇本（門推不開）
@export var unlock_timeline: String = "door_unlocked"   # 🌟 有鑰匙時按 E 播的劇本（成功開門）
@export var opened_flag: String = "door_a_opened"       # 🌟 記錄這扇門已經開過，跨地圖回來不用重開

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var collision_polygon_2d: CollisionPolygon2D = $CollisionPolygon2D
@onready var interact_prompt: Sprite2D = $InteractPrompt
@onready var interact_area: Area2D = $InteractArea

var player_in_range: bool = false
var tween: Tween
var prompt_original_y: float = 0.0
var is_opened: bool = false
var _is_interacting: bool = false

func _ready() -> void:
	if interact_prompt:
		interact_prompt.hide()
		prompt_original_y = interact_prompt.position.y
		
	# 自動綁定 Area2D 的進出訊號，免手動連訊號！
	if interact_area:
		if not interact_area.body_entered.is_connected(_on_body_entered):
			interact_area.body_entered.connect(_on_body_entered)
		if not interact_area.body_exited.is_connected(_on_body_exited):
			interact_area.body_exited.connect(_on_body_exited)
			
	# 🌟 如果玩家之前已經開過這扇門，一進地圖直接保持敞開（不擋路）！
	if opened_flag != "" and DataManager.is_cutscene_completed(opened_flag):
		_set_door_open_immediately()

func _process(_delta: float) -> void:
	if is_opened:
		return
		
	# 防呆：對話中、看書中或逛商店時隱藏 E 鍵
	if DataManager.player_node and (DataManager.player_node.is_in_dialogue or DataManager.player_node.is_reading_book or DataManager.player_node.is_shopping):
		if interact_prompt and interact_prompt.visible:
			interact_prompt.hide()
		return
	elif player_in_range and interact_prompt and not interact_prompt.visible:
		show_prompt()
		
	# 按下 E 鍵互動
	if player_in_range and Input.is_action_just_pressed("interact"):
		if Dialogic.current_timeline != null or _is_interacting:
			return
			
		# 檢查大腦：玩家是不是已經在小木屋拿到鑰匙了？
		var has_key = (key_flag != "" and DataManager.is_cutscene_completed(key_flag))
		
		if has_key:
			_start_door_dialogue(unlock_timeline, true)
		else:
			_start_door_dialogue(locked_timeline, false)

func _start_door_dialogue(tl_name: String, will_open_door: bool) -> void:
	if tl_name == "":
		if will_open_door:
			_open_door_effect()
		return
		
	hide_prompt()
	_is_interacting = true
	
	var player = DataManager.player_node
	if player:
		player.is_in_dialogue = true
		if "velocity" in player:
			player.velocity = Vector2.ZERO
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			
	# 如果劇本裡有 CutsceneDirector 要接手（例如 walk:player:1），CutsceneDirector 會透過 timeline_started 自動接管！
	Dialogic.timeline_ended.connect(func():
		_is_interacting = false
		if will_open_door:
			_open_door_effect()
		var p = DataManager.player_node
		if is_instance_valid(p):
			p.is_in_dialogue = false
			if p.state_machine:
				p.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		if player_in_range and not is_opened:
			show_prompt()
	, CONNECT_ONE_SHOT)
	
	Dialogic.start(tl_name)
	Dialogic.timeline_started.emit()

# 🚪 開門演出：大門漸漸淡出消失，並移除擋路碰撞箱！
func _open_door_effect() -> void:
	if is_opened:
		return
	is_opened = true
	if opened_flag != "":
		DataManager.mark_cutscene_completed(opened_flag)
		
	hide_prompt()
	if collision_polygon_2d:
		collision_polygon_2d.set_deferred("disabled", true)
	if interact_area:
		interact_area.monitoring = false
		
	if sprite_2d:
		var open_tween = create_tween()
		open_tween.tween_property(sprite_2d, "modulate:a", 0.0, 0.5)
		open_tween.tween_callback(func(): sprite_2d.hide())

# 載入地圖時若已開過門，直接隱藏並解除碰撞
func _set_door_open_immediately() -> void:
	is_opened = true
	hide_prompt()
	if collision_polygon_2d:
		collision_polygon_2d.set_deferred("disabled", true)
	if interact_area:
		interact_area.monitoring = false
	if sprite_2d:
		sprite_2d.hide()

func show_prompt() -> void:
	if not interact_prompt or is_opened: return
	interact_prompt.show()
	if tween: tween.kill()
	tween = create_tween().set_loops()
	tween.tween_property(interact_prompt, "position:y", prompt_original_y - 15.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(interact_prompt, "position:y", prompt_original_y, 0.5).set_trans(Tween.TRANS_SINE)

func hide_prompt() -> void:
	if not interact_prompt: return
	interact_prompt.hide()
	if tween: tween.kill()
	interact_prompt.position.y = prompt_original_y

func _on_body_entered(body: Node2D) -> void:
	if body is Player and not is_opened:
		player_in_range = true
		if not body.is_in_dialogue and not body.is_reading_book:
			show_prompt()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_in_range = false
		hide_prompt()

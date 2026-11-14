extends Area2D

# ==========================================
# ⚙️ 企劃設定區 (會在右側屬性面板顯示)
# ==========================================
@export var timeline_name: String = ""          # 🌟 要呼叫的 Dialogic 劇本名稱 (如 "A003")
@export var is_one_time: bool = true            # 🌟 是否只能調查一次？(重要劇情道具建議打勾)
@export var hide_after_interact: bool = false   # 🌟 勾選後，對話一結束道具本體會自動淡出消失 (適合「撿起道具」)

@onready var prompt = get_node_or_null("InteractPrompt")
var is_player_near: bool = false
var has_been_interacted: bool = false           # 記錄是否已經互動過
var _is_reading_now: bool = false               # 確保只有當前觸發的道具會處理結束解鎖

func _ready() -> void:
	if prompt:
		prompt.visible = false
		
	# 🌟 1. 檢查跨地圖記憶：如果是一次性道具且已經在 DataManager 登記過，進地圖直接關閉或隱藏！
	if is_one_time and timeline_name != "":
		if DataManager.has_method("is_cutscene_completed") and DataManager.is_cutscene_completed(timeline_name):
			has_been_interacted = true
			if hide_after_interact:
				visible = false
				process_mode = Node.PROCESS_MODE_DISABLED
			return

	# 自動連接訊號
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

# 🌟 輔助函數：安全抓取玩家節點
func _get_player() -> Node2D:
	if is_instance_valid(DataManager.player_node):
		return DataManager.player_node
	if get_tree() and get_tree().current_scene:
		var p = get_tree().current_scene.find_child("player", true, false)
		if p: DataManager.player_node = p
		return p as Node2D
	return null

func _on_body_entered(body: Node2D) -> void:
	if body == _get_player():
		is_player_near = true
		if is_one_time and has_been_interacted: return
		if prompt: prompt.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body == _get_player():
		is_player_near = false
		if prompt: prompt.visible = false

func _input(event: InputEvent) -> void:
	# 支援按互動鍵 interact 或鍵盤 E 鍵
	var is_e_pressed = event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_E)
	
	if is_e_pressed and is_near_player() and not _is_reading_now:
		var player = _get_player()
		# 防呆：避免沒填劇本，或正在播劇情時重複觸發
		if timeline_name == "" or Dialogic.current_timeline != null: return
		if player and player.is_in_dialogue: return
			
		get_viewport().set_input_as_handled()
		has_been_interacted = true 
		_is_reading_now = true
		if prompt: prompt.visible = false
		
		# 🌟 登記到 DataManager 跨地圖記憶 (防止換地圖回來又能重複撿)
		if is_one_time and DataManager.has_method("mark_cutscene_completed"):
			DataManager.mark_cutscene_completed(timeline_name)
		
		# 鎖定玩家大腦與速度
		if player:
			player.is_in_dialogue = true
			if "velocity" in player:
				player.velocity = Vector2.ZERO
			if player.state_machine:
				player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			if player.animated_sprite_2d:
				player.animated_sprite_2d.play("idle_down")
		
		# 🌟 連接「對話結束」與「劇本暗號」訊號
		if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
			Dialogic.timeline_ended.connect(_on_timeline_ended)
		if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
			Dialogic.signal_event.connect(_on_dialogic_signal)
		
		# 🌟 啟動劇本並通知 HUD 開啟電影黑邊！
		Dialogic.start(timeline_name)
		Dialogic.timeline_started.emit()

# 🌟 支援在劇本裡讓這個道具本體「閃一下」或「提前消失」！
func _on_dialogic_signal(arg: String) -> void:
	if not _is_reading_now: return
	# 在劇本寫 [signal arg="flash:item"] 或 [signal arg="flash:player:0.35"] 都能讓道具閃白光！
	if arg.begins_with("flash"):
		var tween = create_tween()
		tween.tween_property(self, "modulate", Color(4.5, 4.5, 5.0, 1.0), 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif arg == "hide:item":
		visible = false

# 🔓 對話結束時，自動解鎖玩家！(修復原本卡死動不了的問題)
func _on_timeline_ended() -> void:
	if not _is_reading_now: return
	_is_reading_now = false
	
	if Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_timeline_ended)
	if Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.disconnect(_on_dialogic_signal)
		
	var player = _get_player()
	if is_instance_valid(player):
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
			
	# 🌟 如果有勾選 hide_after_interact，對話一結束道具就會平滑淡出消失！
	if hide_after_interact:
		monitoring = false
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func():
			visible = false
			process_mode = Node.PROCESS_MODE_DISABLED
		)
	elif is_player_near and not is_one_time and prompt:
		prompt.visible = true

# 輔助判斷函數
func is_near_player() -> bool:
	if is_one_time and has_been_interacted: return false
	return is_player_near

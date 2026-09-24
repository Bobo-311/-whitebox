extends Area2D

# ==========================================
# ⚙️ 企劃設定區 (會在右側屬性面板顯示)
# ==========================================
@export var timeline_name: String = ""   # 🌟 要呼叫的 Dialogic 劇本名稱
@export var is_one_time: bool = false    # 🌟 是否只能調查一次？(打勾代表拋棄式)

@onready var prompt = $InteractPrompt
var is_player_near: bool = false
var has_been_interacted: bool = false    # 記錄是否已經互動過

func _ready() -> void:
	# 自動連接訊號，不用再手動去右邊拉線了！
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body == DataManager.player_node:
		is_player_near = true
		# 如果是一次性且已互動過，就不顯示圖示
		if is_one_time and has_been_interacted: return
		prompt.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body == DataManager.player_node:
		is_player_near = false
		prompt.visible = false

func _input(event: InputEvent) -> void:
	# 條件：按下E + 靠近 + (如果是一次性，必須還沒互動過)
	if event.is_action_pressed("interact") and is_near_player():
		
		# 防呆：避免沒填劇本，或正在播劇情時重複觸發
		if timeline_name == "" or Dialogic.current_timeline != null: return
		if DataManager.player_node and DataManager.player_node.is_in_dialogue: return
			
		# 標記為已互動，並隱藏 E 圖示
		has_been_interacted = true 
		prompt.visible = false
		
		# 鎖定玩家大腦 (我們之前寫好的標準流程)
		if DataManager.player_node:
			DataManager.player_node.is_in_dialogue = true
			if DataManager.player_node.state_machine:
				DataManager.player_node.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			DataManager.player_node.animated_sprite_2d.play("idle_down")
		
		# 🌟 動態呼叫企劃在面板填寫的劇本！
		Dialogic.start(timeline_name)

# 輔助判斷函數
func is_near_player() -> bool:
	if is_one_time and has_been_interacted: return false
	return is_player_near

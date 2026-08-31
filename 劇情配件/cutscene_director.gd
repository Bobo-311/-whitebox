extends Node2D
class_name CutsceneDirector

# 🌟 讓企劃在右側面板指定這場戲有哪些演員
@export var player: Node2D
@export var target_npc: Node2D
@export var target_timeline: String = "" # 要播放的 Dialogic 劇本

@onready var anim_player: AnimationPlayer = $AnimationPlayer

# 外部呼叫這個函數，就能一鍵播放整段過場
func play_cutscene() -> void:
	if player:
		# 1. 鎖住阿尼大腦，防止玩家亂動
		player.is_in_dialogue = true
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			
	# 2. 播放 AnimationPlayer 裡面做好的動畫時間軸
	anim_player.play("cherry_tree_event")

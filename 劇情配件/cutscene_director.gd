extends Area2D
class_name CutsceneDirector

# ==========================================
# ⚙️ 企劃設定區 (在右側面板拖拉設定)
# ==========================================
@export var target_timeline: String = ""    # 1. 填寫要播放的 Dialogic 劇本名稱
@export var target_npc: Node2D              # 2. 拖入這場戲的 NPC (例如小女孩)
@export var markers: Dictionary = {}        # 3. 裝載所有走位目標的字典
@export var player_dch: Resource
@export var npc_dch: Resource

var has_triggered: bool = false # 確保劇情只觸發一次

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# 讓導演監聽 Dialogic 的暗號與結束通知
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)
	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)

# ==========================================
# 🎬 玩家踩進觸發區 ➡️ 開拍！
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if body == DataManager.player_node and not has_triggered:
		has_triggered = true
		
		# 1. 鎖住阿尼大腦
		body.is_in_dialogue = true
		if body.state_machine:
			body.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		body.animated_sprite_2d.play("idle_down")
		
		# 2. 🌟 啟動劇本並存下 layout
		var layout = Dialogic.start(target_timeline)
		
		# 3. 🌟 動態綁定玩家氣泡 (如果有在面板拖入阿尼.dch)
		if player_dch and body.has_node("BubbleMaker"):
			layout.register_character(player_dch, body.get_node("BubbleMaker"))
			
		# 4. 🌟 動態綁定 NPC 氣泡 (如果有在面板拖入小女孩.dch)
		if npc_dch and target_npc and target_npc.has_node("BubbleMaker"):
			layout.register_character(npc_dch, target_npc.get_node("BubbleMaker"))

# 🏃‍♂️ 2. 接收劇本暗號 ➡️ 指揮走位
# 暗號格式預期為： 動作:對象:目標點 (例如 walk:player:tree_pos)
func _on_dialogic_signal(argument: String) -> void:
	if not has_triggered: return 
	
	var parts = argument.split(":")
	if parts.size() < 3: return
	
	var action = parts[0]     # "walk" 或 "run"
	var actor = parts[1]      # "player" 或 "npc"
	var target_key = parts[2] # 字典裡的 key (例如 "tree_pos")
	
	# 檢查有沒有這個定位點
	if not markers.has(target_key): return
	var target_marker = get_node(markers[target_key]) as Node2D
	if not target_marker: return
	
	# 🌟 阿尼移動邏輯
	if actor == "player":
		var player = DataManager.player_node
		if player:
			if action == "walk":
				player.animated_sprite_2d.play("move_left") # 換走路動畫
				var tween = create_tween()
				tween.tween_property(player, "global_position", target_marker.global_position, 1.5)
				tween.tween_callback(func(): player.animated_sprite_2d.play("idle_right"))
				
	# 🌟 NPC 移動邏輯
	elif actor == "npc":
		if target_npc and action == "run":
			var tween = create_tween()
			tween.tween_property(target_npc, "global_position", target_marker.global_position, 0.6)
			tween.parallel().tween_property(target_npc, "modulate:a", 0.0, 0.4) # 淡出
			tween.tween_callback(func(): target_npc.visible = false)
			
		elif action == "walk":
				var tween = create_tween()
				tween.tween_property(target_npc, "global_position", target_marker.global_position, 1.5)

# 🔓 3. 劇本結束 ➡️ 解鎖阿尼
func _on_timeline_ended() -> void:
	var player = DataManager.player_node
	# 確保是同一個劇本結束才解鎖
	if player and player.is_in_dialogue and has_triggered:
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT

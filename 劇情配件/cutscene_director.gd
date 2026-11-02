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

@export_group("⏱️ 預設演出速度 (當 Signal 沒填秒數時使用)")
@export var cam_pan_time: float = 2.0       # 鏡頭平移過去的預設秒數 (pan:cam)
@export var cam_reset_time: float = 0.8     # 鏡頭回到阿尼身上的預設秒數 (reset:cam)
@export var player_walk_time: float = 1.5   # 阿尼慢走的預設秒數 (walk:player)
@export var player_run_time: float = 0.8    # 阿尼快跑的預設秒數 (run:player)
@export var npc_walk_time: float = 1.5      # NPC 慢走的預設秒數 (walk:npc)
@export var npc_run_time: float = 0.6       # NPC 逃跑的預設秒數 (run:npc)
@export var npc_fade_time: float = 0.4      # NPC 逃跑時的預設淡出秒數

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

# 🏃‍♂️ 2. 接收劇本暗號 ➡️ 指揮走位與運鏡
# 暗號格式支援彈性填寫： 動作:對象:目標點:[移動動畫]:[停下動畫]:[秒數]
# 例如： run:player:girl_side_pos:1.2 或 run:player:girl_side_pos:move_up:idle_right:1.5
func _on_dialogic_signal(argument: String) -> void:
	if not has_triggered: return 
	
	# 🌟 接收淡出電影黑邊的暗號 (交給 player_hud.gd 與黑底處理)
	if argument == "fade_out_cinematic":
		return
		
	var parts = argument.split(":")
	if parts.size() < 3: return
	
	var action = parts[0].strip_edges()     # "walk"、"run"、"pan"、"reset"、"anim"
	var actor = parts[1].strip_edges()      # "player"、"npc"、"cam"
	var target_key = parts[2].strip_edges() # 字典裡的 key (例如 "girl_side_pos")
	
	# 🌟 智慧解析第 4 格以後的參數：如果是數字就當作「秒數」，如果是文字就依序當作「移動動畫」與「停下動畫」
	var custom_move_anim: String = ""
	var custom_idle_anim: String = ""
	var custom_duration: float = -1.0 # -1 代表未指定，將使用預設秒數
	
	for i in range(3, parts.size()):
		var param = parts[i].strip_edges()
		if param == "": continue
		if param.is_valid_float():
			custom_duration = param.to_float()
		elif custom_move_anim == "":
			custom_move_anim = param
		elif custom_idle_anim == "":
			custom_idle_anim = param
	
	# 🎥 鏡頭運鏡邏輯 (支援 pan:cam:目標點:秒數 與 reset:cam:player:秒數)
	if actor == "cam":
		var cam = get_viewport().get_camera_2d()
		var player = DataManager.player_node
		if not cam: return
		
		if action == "pan" and markers.has(target_key):
			var cam_marker = get_node(markers[target_key]) as Node2D
			if cam_marker:
				var duration = custom_duration if custom_duration > 0.0 else cam_pan_time
				var current_pos = cam.get_screen_center_position()
				cam.top_level = true
				cam.global_position = current_pos
				var tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(cam, "global_position", cam_marker.global_position, duration)
				
		elif action == "reset" and player:
			var duration = custom_duration if custom_duration > 0.0 else cam_reset_time
			var tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(cam, "global_position", player.global_position, duration)
			tween.tween_callback(func():
				cam.top_level = false
				cam.position = Vector2.ZERO
			)
		return

	# 🎭 原地單純切換動畫邏輯 (例如 anim:npc:stand_up 或 anim:player:idle_up)
	if action == "anim":
		if actor == "player" and DataManager.player_node:
			DataManager.player_node.animated_sprite_2d.play(target_key)
		elif actor == "npc" and target_npc:
			var npc_sprite = target_npc.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if npc_sprite:
				npc_sprite.play(target_key)
		return

	# 檢查有沒有這個定位點
	if not markers.has(target_key): return
	var target_marker = get_node(markers[target_key]) as Node2D
	if not target_marker: return
	
	# 🌟 阿尼移動邏輯
	if actor == "player":
		var player = DataManager.player_node
		if player:
			# 1. 決定預設動畫 (如果沒有填動畫名稱，就自動判斷左右)
			var is_moving_right = target_marker.global_position.x > player.global_position.x
			var move_anim = "move_right" if is_moving_right else "move_left"
			var idle_anim = "idle_right" if is_moving_right else "idle_left"
			
			# 2. 如果有填自訂移動動畫，覆蓋移動動畫！
			if custom_move_anim != "":
				move_anim = custom_move_anim
				if custom_idle_anim == "" and custom_move_anim.begins_with("move_"):
					idle_anim = custom_move_anim.replace("move_", "idle_")
					
			# 3. 如果有填自訂停下動畫，覆蓋停下動畫！
			if custom_idle_anim != "":
				idle_anim = custom_idle_anim
			
			# 4. 執行移動與動畫播放 (優先使用 Signal 填的秒數，沒填則用預設秒數)
			if action == "walk":
				var duration = custom_duration if custom_duration > 0.0 else player_walk_time
				player.animated_sprite_2d.play(move_anim)
				var tween = create_tween()
				tween.tween_property(player, "global_position", target_marker.global_position, duration)
				tween.tween_callback(func(): player.animated_sprite_2d.play(idle_anim))
				
			elif action == "run":
				var duration = custom_duration if custom_duration > 0.0 else player_run_time
				player.animated_sprite_2d.play(move_anim)
				var tween = create_tween()
				tween.tween_property(player, "global_position", target_marker.global_position, duration)
				tween.tween_callback(func(): player.animated_sprite_2d.play(idle_anim))
				
	# 🌟 NPC 移動邏輯
	elif actor == "npc":
		if target_npc:
			var npc_sprite = target_npc.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if npc_sprite and custom_move_anim != "":
				npc_sprite.play(custom_move_anim)
				
			if action == "run":
				var duration = custom_duration if custom_duration > 0.0 else npc_run_time
				var tween = create_tween()
				tween.tween_property(target_npc, "global_position", target_marker.global_position, duration)
				tween.parallel().tween_property(target_npc, "modulate:a", 0.0, npc_fade_time) # 淡出
				tween.tween_callback(func(): 
					target_npc.visible = false
					if npc_sprite and custom_idle_anim != "":
						npc_sprite.play(custom_idle_anim)
				)
			elif action == "walk":
				var duration = custom_duration if custom_duration > 0.0 else npc_walk_time
				var tween = create_tween()
				tween.tween_property(target_npc, "global_position", target_marker.global_position, duration)
				tween.tween_callback(func():
					if npc_sprite and custom_idle_anim != "":
						npc_sprite.play(custom_idle_anim)
				)

# 🔓 3. 劇本結束 ➡️ 解鎖阿尼並確保鏡頭歸位
func _on_timeline_ended() -> void:
	var player = DataManager.player_node
	# 確保是同一個劇本結束才解鎖
	if player and player.is_in_dialogue and has_triggered:
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
			
		# 防呆：確保對話結束時鏡頭一定回到玩家身上
		var cam = get_viewport().get_camera_2d()
		if cam and cam.top_level:
			cam.top_level = false
			cam.position = Vector2.ZERO

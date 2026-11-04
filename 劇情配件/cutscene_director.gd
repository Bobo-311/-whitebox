extends Area2D
class_name CutsceneDirector

# ==========================================
# ⚙️ 企劃設定區 (在右側面板拖拉設定)
# ==========================================
@export var target_timeline: String = ""    # 1. 填寫要播放的 Dialogic 劇本名稱
@export var target_npc: Node2D              # 2. 單一 NPC (相容舊劇本，對應暗號 "npc")
@export var actors: Dictionary = {}         # 🌟 新增：複數演員字典 (例如 key 填 "m1", "m2" 指派多隻怪物)
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
@export var trigger_on_map_enter: bool = false # 🌟 新增：勾選後，一進入這張地圖就會自動開拍！

var has_triggered: bool = false # 確保劇情只觸發一次
var is_active: bool = false     # 🌟 新增：確保只有「正在演出中」的導演會接收暗號，多場戲不互衝！

func _ready() -> void:
	# 🌟 關鍵防呆：如果是「進圖自動觸發」，就關閉 Area2D 碰撞偵測，防止出生瞬間跟 BaseMap 搶著重複觸發！
	if trigger_on_map_enter:
		monitoring = false
	else:
		body_entered.connect(_on_body_entered)
		
	# 讓導演監聽 Dialogic 的暗號與結束通知
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)
	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)
		
	# 🌟 防呆：把 target_npc 以及 actors 字典裡所有「一開始關眼睛隱形」的怪物都先凍結 AI
	_freeze_hidden_actor(target_npc)
	for key in actors.keys():
		var actor_node = get_node_or_null(actors[key]) as Node2D
		_freeze_hidden_actor(actor_node)

# 🌟 輔助函數：凍結隱形怪物的 AI，但保留 AnimatedSprite2D 動畫播放能力
func _freeze_hidden_actor(actor_node: Node2D) -> void:
	if actor_node and not actor_node.visible:
		actor_node.process_mode = Node.PROCESS_MODE_DISABLED
		var sprite = actor_node.get_node_or_null("AnimatedSprite2D")
		if sprite:
			sprite.process_mode = Node.PROCESS_MODE_ALWAYS

# 🌟 輔助函數：安全取得玩家節點 (防止開場第一幀 DataManager.player_node 還沒賦值)
func _get_player() -> Node2D:
	if DataManager.player_node:
		return DataManager.player_node
	# 備用方案：直接從當前場景樹尋找名為 "player" 的節點
	var p = get_tree().current_scene.find_child("player", true, false)
	if p:
		DataManager.player_node = p
	return p as Node2D

# 🌟 輔助函數：根據暗號裡的名稱 ("npc" 或 "m1"、"m2") 抓出對應的角色節點
func _get_actor_node(actor_key: String) -> Node2D:
	if actor_key == "npc":
		return target_npc
	elif actors.has(actor_key):
		return get_node_or_null(actors[actor_key]) as Node2D
	return null

# ==========================================
# 🎬 玩家踩進觸發區 ➡️ 開拍！
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if body == _get_player() and not has_triggered:
		start_cutscene(body)
			
# 🌟 統一開拍函數（踩進區域 與 BaseMap 開場 皆由此進入）
func start_cutscene(player_body: Node2D = null) -> void:
	if has_triggered: return
	if not player_body:
		player_body = _get_player()
	if not player_body:
		push_warning("【CutsceneDirector】找不到 player 節點，無法鎖定玩家！")
		return
		
	has_triggered = true
	is_active = true # 🌟 標記這場戲正式開拍！
	
	# 1. 徹底鎖住阿尼大腦與移動速度
	player_body.is_in_dialogue = true
	if "velocity" in player_body:
		player_body.velocity = Vector2.ZERO
	if player_body.state_machine:
		player_body.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if player_body.animated_sprite_2d:
		player_body.animated_sprite_2d.play("idle_down")
	
	# 2. 🌟 啟動劇本並存下 layout
	var layout = Dialogic.start(target_timeline)
	
	# 🌟 保險機制：確保開場時 player_hud 的電影黑邊一定會收到啟動通知！
	Dialogic.timeline_started.emit()
	
	# 3. 🌟 動態綁定玩家氣泡 (如果有在面板拖入阿尼.dch)
	if player_dch and player_body.has_node("BubbleMaker") and layout and layout.has_method("register_character"):
		layout.register_character(player_dch, player_body.get_node("BubbleMaker"))
		
	# 4. 🌟 動態綁定 NPC 氣泡 (如果有在面板拖入小女孩.dch)
	if npc_dch and target_npc and target_npc.has_node("BubbleMaker") and layout and layout.has_method("register_character"):
		layout.register_character(npc_dch, target_npc.get_node("BubbleMaker"))
		
# 🏃‍♂️ 2. 接收劇本暗號 ➡️ 指揮走位與運鏡
# 暗號格式： 動作:對象(player/cam/npc/m1/m2...):目標點:[移動動畫]:[停下動畫]:[秒數]
func _on_dialogic_signal(argument: String) -> void:
	if not is_active: return # 🌟 只有當前正在演出的導演才處理暗號！
	
	# 🌟 接收淡出電影黑邊的暗號 (交給 player_hud.gd 與黑底處理)
	if argument == "fade_out_cinematic":
		return
		
	var parts = argument.split(":")
	if parts.size() < 3: return
	
	var action = parts[0].strip_edges()     # "walk"、"run"、"back"、"ambush"、"throw"、"show"、"hide"、"pan"、"reset"、"anim"
	var actor = parts[1].strip_edges()      # "player"、"cam"、"npc" 或 actors 字典裡的 "m1"、"m2"、"rock"
	var target_key = parts[2].strip_edges() # markers 字典裡的 key 或 動畫名稱 或 被砸目標代號
	
	# 🌟 智慧解析第 4 格以後的參數：數字當「秒數」，文字依序當「移動動畫」與「停下動畫」
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
		var player = _get_player()
		if not cam: return
		
		if action == "pan" and markers.has(target_key):
			var cam_marker = get_node_or_null(markers[target_key]) as Node2D
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

	# 🎭 原地單純切換動畫 或 顯示/隱藏 或 投擲邏輯 (支援 player、npc、m1、m2...)
	if action == "anim":
		var player = _get_player()
		if actor == "player" and player:
			player.animated_sprite_2d.play(target_key)
		else:
			var current_npc = _get_actor_node(actor)
			if current_npc:
				var npc_sprite = current_npc.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
				if npc_sprite:
					npc_sprite.play(target_key)
		return
	elif action == "show":
		var current_npc = _get_actor_node(actor)
		if current_npc:
			current_npc.visible = true
			current_npc.modulate.a = 1.0
		return
	elif action == "hide":
		var current_npc = _get_actor_node(actor)
		if current_npc:
			current_npc.visible = false
		return
	elif action == "throw":
		var projectile = _get_actor_node(actor)      # 抓取石頭 (例如 "rock")
		var victim = _get_actor_node(target_key)     # 抓取被砸的怪物 (例如 "m2" 或 "m1")
		if projectile and victim:
			var duration = custom_duration if custom_duration > 0.0 else 0.25
			projectile.visible = true
			projectile.modulate.a = 1.0
			projectile.rotation = 0.0
			
			# 瞄準怪物腦袋 (假設怪物中心點往上偏移 24 像素，可依怪物身高微調)
			var hit_pos = victim.global_position + Vector2(0, -24)
			# 計算石頭飛來的方向，決定砸中後石頭往哪彈、怪物往哪退
			var bounce_dir = -1.0 if projectile.global_position.x < victim.global_position.x else 1.0
			
			var tween = create_tween()
			# 1. 石頭高速飛向怪物腦袋 (飛行期間同時旋轉一圈半)
			tween.tween_property(projectile, "global_position", hit_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(projectile, "rotation", TAU * 1.5, duration)
			
			# 2. 💥 砸中瞬間：觸發怪物受擊反應 ＋ 石頭彈開落地消失
			tween.tween_callback(func():
				# (A) 石頭往反方向微幅彈起、再掉落地面並淡出
				var bounce_tween = create_tween()
				var peak_pos = hit_pos + Vector2(28.0 * bounce_dir, -18.0)
				var ground_pos = hit_pos + Vector2(48.0 * bounce_dir, 24.0)
				bounce_tween.tween_property(projectile, "global_position", peak_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				bounce_tween.tween_property(projectile, "global_position", ground_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				bounce_tween.parallel().tween_property(projectile, "modulate:a", 0.0, 0.18)
				bounce_tween.tween_callback(func(): projectile.visible = false)
				
				# (B) 怪物被砸中：HDR 閃白光 + 順著撞擊方向往後震退一小步
				var hit_tween = create_tween()
				victim.modulate = Color(3.0, 3.0, 3.0, 1.0) # 瞬間受擊閃白
				hit_tween.tween_property(victim, "modulate", Color.WHITE, 0.2)
				var knockback_pos = victim.global_position + Vector2(-16.0 * bounce_dir, 0)
				hit_tween.parallel().tween_property(victim, "global_position", knockback_pos, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			)
		return

	# 檢查有沒有這個定位點
	if not markers.has(target_key): return
	var target_marker = get_node_or_null(markers[target_key]) as Node2D
	if not target_marker: return
	
	# 🌟 阿尼移動邏輯 (支援 walk、run、以及嚇到倒退一步 back)
	if actor == "player":
		var player = _get_player()
		if player:
			var is_moving_right = target_marker.global_position.x > player.global_position.x
			var move_anim = "move_right" if is_moving_right else "move_left"
			var idle_anim = "idle_right" if is_moving_right else "idle_left"
			
			# 若是嚇到後退一步 (back)，預設面朝反方向（看著怪物倒退）
			if action == "back":
				move_anim = "move_left" if is_moving_right else "move_right"
				idle_anim = "idle_left" if is_moving_right else "idle_right"
			
			if custom_move_anim != "":
				move_anim = custom_move_anim
				if custom_idle_anim == "" and custom_move_anim.begins_with("move_"):
					idle_anim = custom_move_anim.replace("move_", "idle_")
					
			if custom_idle_anim != "":
				idle_anim = custom_idle_anim
			
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
				
			elif action == "back":
				var duration = custom_duration if custom_duration > 0.0 else 0.25
				player.animated_sprite_2d.play(move_anim)
				var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tween.tween_property(player, "global_position", target_marker.global_position, duration)
				tween.tween_callback(func(): player.animated_sprite_2d.play(idle_anim))
				
	# 🌟 單一 NPC 或 複數怪物 (m1, m2...) 移動邏輯
	else:
		var current_npc = _get_actor_node(actor)
		if current_npc:
			var npc_sprite = current_npc.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if npc_sprite and custom_move_anim != "":
				npc_sprite.play(custom_move_anim)
				
			if action == "run":
				# 小女孩專用：邊跑邊淡出消失
				var duration = custom_duration if custom_duration > 0.0 else npc_run_time
				var tween = create_tween()
				tween.tween_property(current_npc, "global_position", target_marker.global_position, duration)
				tween.parallel().tween_property(current_npc, "modulate:a", 0.0, npc_fade_time) # 淡出
				tween.tween_callback(func(): 
					current_npc.visible = false
					if npc_sprite and custom_idle_anim != "":
						npc_sprite.play(custom_idle_anim)
				)
			elif action == "walk":
				current_npc.visible = true
				current_npc.modulate.a = 1.0
				var duration = custom_duration if custom_duration > 0.0 else npc_walk_time
				var tween = create_tween()
				tween.tween_property(current_npc, "global_position", target_marker.global_position, duration)
				tween.tween_callback(func():
					if npc_sprite and custom_idle_anim != "":
						npc_sprite.play(custom_idle_anim)
				)
			elif action == "ambush":
				# 👾 🌟 怪物專用：瞬間打開眼睛現身，並平滑等速移向目標點（不淡出！）
				current_npc.visible = true
				current_npc.modulate.a = 1.0
				var duration = custom_duration if custom_duration > 0.0 else 0.35
				var tween = create_tween() # 🌟 拿掉曲線設定，改回跟 run 一樣的平滑等速移動！
				tween.tween_property(current_npc, "global_position", target_marker.global_position, duration)
				tween.tween_callback(func():
					if npc_sprite and custom_idle_anim != "":
						npc_sprite.play(custom_idle_anim)
				)

# 🔓 3. 劇本結束 ➡️ 解鎖阿尼，並把場上所有已現身的怪物 AI 全部解凍！
func _on_timeline_ended() -> void:
	if not is_active: return # 🌟 確保只有當前這場戲結束時才執行收尾
	is_active = false
	
	var player = _get_player()
	if player and player.is_in_dialogue:
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
			
		# 🌟 解凍單一 target_npc 與 actors 字典裡所有已經現身的怪物 (排除 rock 等純道具)
		if target_npc and target_npc.visible:
			target_npc.process_mode = Node.PROCESS_MODE_INHERIT
		for key in actors.keys():
			var actor_node = get_node_or_null(actors[key]) as Node2D
			if actor_node and actor_node.visible:
				actor_node.process_mode = Node.PROCESS_MODE_INHERIT
			
		# 防呆：確保對話結束時鏡頭一定回到玩家身上
		var cam = get_viewport().get_camera_2d()
		if cam and cam.top_level:
			cam.top_level = false
			cam.position = Vector2.ZERO

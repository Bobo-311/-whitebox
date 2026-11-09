extends Area2D
class_name CutsceneDirector

# ==========================================
# ⚙️ 企劃設定區 (在右側面板拖拉設定)
# ==========================================
@export var target_timeline: String = ""    # 1. 填寫要播放的 Dialogic 劇本名稱
@export var target_npc: Node2D              # 2. 單一 NPC (相容舊劇本，對應暗號 "npc")
@export var actors: Dictionary = {}         # 🌟 複數演員字典 (例如 key 填 "m1", "m2", "cat")
@export var markers: Dictionary = {}        # 3. 裝載所有走位目標的字典
@export var player_dch: Resource
@export var npc_dch: Resource

@export_group("📖 跨地圖記憶與角色去留設定")
@export var trigger_on_map_enter: bool = false             # 勾選後，一進入這張地圖就會自動開拍
@export var hide_target_npc_after_complete: bool = false   # 🌟 勾選後，演完重回地圖時 target_npc 會永遠消失
@export var permanent_hide_actors: Array[String] = []      # 🌟 填入演完後要「永遠消失」的 actors 代號 (如 "m1")，沒填的會保留！

@export_group("⚔️ 戰鬥全滅觸發設定 (打完指定怪物自動開拍)")
@export var trigger_on_enemies_cleared: bool = false   # 🌟 勾選後，當指定怪物全部死亡時自動開拍！
@export var target_enemies: Array[Node2D] = []         # 🌟 可拖入怪物；若留空，會自動抓取 Permanent Hide Actors 或 Actors 裡的怪物！
@export var clear_delay: float = 1.0                   # 🌟 最後一隻怪死掉後，隔幾秒才跳出對話 (預設 1 秒喘息時間)

var _tracked_enemies: Array[Node2D] = []
var _battle_started: bool = false # 確保怪物已經正式登場開始戰鬥後，才開始判定全滅

@export_group("⏱️ 預設演出速度與距離 (當 Signal 沒填秒數時使用)")
@export var cam_pan_time: float = 2.0       # 鏡頭平移過去的預設秒數 (pan:cam)
@export var cam_reset_time: float = 0.8     # 鏡頭回到阿尼身上的預設秒數 (reset:cam)
@export var player_walk_time: float = 1.5   # 阿尼慢走的預設秒數 (walk:player)
@export var player_run_time: float = 0.8    # 阿尼快跑的預設秒數 (run:player)
@export var npc_walk_time: float = 1.5      # NPC 慢走的預設秒數 (walk:npc)
@export var npc_run_time: float = 0.6       # NPC 逃跑的預設秒數 (run:npc)
@export var npc_fade_time: float = 0.4      # NPC 逃跑時的預設淡出秒數
@export var side_offset: float = 48.0       # 🌟 走到阿尼身邊時的左右間距 (player_right / player_left)
@export var step_offset: float = 60.0       # 🌟 原地往某方向走幾步的距離 (self_right / self_left)

var has_triggered: bool = false # 確保劇情只觸發一次
var is_active: bool = false     # 🌟 確保只有「正在演出中」的導演會接收暗號，多場戲不互衝！
var _cam_tween: Tween = null    # 🌟 記錄當前的鏡頭動畫，防止玩家按太快時兩個鏡頭動畫打架！
var _shake_tween: Tween = null  # 🌟 記錄鏡頭震動動畫，防止連續震動互搶
var _zoom_tween: Tween = null   # 🌟 記錄鏡頭縮放動畫，防止連續 zoom 互搶
var _actor_tweens: Dictionary = {}         # 🌟 記錄每個角色正在跑的移動 Tween (key: actor名稱 -> value: Tween)
var _actor_target_pos: Dictionary = {}     # 🌟 記錄每個角色這一步原本要走到的終點座標 (被跳過時瞬間補位！)
var _actor_target_idle: Dictionary = {}    # 🌟 記錄每個角色走完這一步後應該播放的待機動畫

@export var click_cooldown: float = 0.18   # 🌟 防連點冷卻秒數 (避免狂按空白鍵/滑鼠導致 Dialogic 與 Tween 崩潰)
var _last_advance_time: float = 0.0

func _ready() -> void:
	# ==========================================
	# 🌟 1. 跨地圖記憶檢查：如果這段劇情已經在 DataManager 登記看過了
	# ==========================================
	if DataManager.has_method("is_cutscene_completed") and DataManager.is_cutscene_completed(target_timeline):
		has_triggered = true
		monitoring = false
		set_process(false)
		
		# (A) 檢查單一 target_npc 是否需要永久消失
		if hide_target_npc_after_complete and target_npc:
			target_npc.visible = false
			target_npc.process_mode = Node.PROCESS_MODE_DISABLED
			
		# (B) 檢查複數 actors 字典：只把有寫在 permanent_hide_actors 名單裡的角色永久隱藏！
		for key in permanent_hide_actors:
			if actors.has(key):
				var actor_node = get_node_or_null(actors[key]) as Node2D
				if actor_node:
					actor_node.visible = false
					actor_node.process_mode = Node.PROCESS_MODE_DISABLED
					
		# (C) 防呆：把場上其他原本就關眼睛隱形的埋伏怪也凍結 AI
		_freeze_hidden_actor(target_npc)
		for key in actors.keys():
			var actor_node = get_node_or_null(actors[key]) as Node2D
			_freeze_hidden_actor(actor_node)
		return

	# ==========================================
	# 🌟 2. 尚未看過此劇情的正常初始化
	# ==========================================
	# 讓導演監聽 Dialogic 的暗號與結束通知
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)
	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)
		
	# 防呆：把 target_npc 以及 actors 字典裡所有「一開始關眼睛隱形」的怪物都先凍結 AI
	_freeze_hidden_actor(target_npc)
	for key in actors.keys():
		var actor_node = get_node_or_null(actors[key]) as Node2D
		_freeze_hidden_actor(actor_node)

	# 判斷觸發模式：進圖觸發 / 怪物全滅觸發 / 踩區域觸發
	if trigger_on_map_enter:
		monitoring = false
		set_process(false)
	elif trigger_on_enemies_cleared:
		monitoring = false # 關閉腳下碰撞，改由怪物全滅觸發！
		set_process(false)
		# 🌟 等待 2 幀，確保場景樹排在下面的 m1, m2, m3 都已經載入完成後，再抓進追蹤清單！
		await get_tree().process_frame
		await get_tree().process_frame
		_setup_enemy_clear_trigger()
	else:
		set_process(false)
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)

# 🌟 離開場景樹時安全清理所有 Tween 與訊號連線，防止換地圖時閃退
func _exit_tree() -> void:
	_clear_all_cutscene_tweens(false)
	if Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.disconnect(_on_dialogic_signal)
	if Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_timeline_ended)

# 🛡️ 防禦 1：過場演戲期間的「防狂按節流閥」
func _input(event: InputEvent) -> void:
	if not is_active: return
	
	# 偵測滑鼠左鍵按下、空白鍵、Enter 或互動鍵 (連按不放 is_echo 也會直接擋掉)
	var is_click = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var is_key = event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)
	var is_act = event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")
	
	if is_click or is_key or is_act:
		if event.is_echo():
			get_viewport().set_input_as_handled()
			return
		var now = Time.get_ticks_msec() / 1000.0
		if now - _last_advance_time < click_cooldown:
			# 點太快了！直接吃掉這次按鍵，不讓它傳給 Dialogic 造成當機
			get_viewport().set_input_as_handled()
			return
		_last_advance_time = now

# 🛡️ 防禦 2A：在計算下一步方向與座標「之前」，先切斷角色身上未完成的 Tween 並瞬間補位到上一步終點！
func _snap_and_kill_actor_tween(actor_key: String, actor_node: Node2D) -> void:
	if _actor_tweens.has(actor_key):
		var old_tween = _actor_tweens[actor_key] as Tween
		if old_tween and old_tween.is_valid() and old_tween.is_running():
			old_tween.kill()
			if is_instance_valid(actor_node) and _actor_target_pos.has(actor_key):
				actor_node.global_position = _actor_target_pos[actor_key]
				if _actor_target_idle.has(actor_key) and _actor_target_idle[actor_key] != "":
					var sp = _get_actor_sprite(actor_node)
					if sp: sp.play(_actor_target_idle[actor_key])
		_actor_tweens.erase(actor_key)

# 🛡️ 防禦 2B：安全建立角色移動 Tween (修正綁定在 PROCESS_MODE_DISABLED 怪物身上會導致 Tween 凍結不動的問題！)
func _create_safe_actor_tween(actor_key: String, actor_node: Node2D, new_target_pos: Vector2, idle_anim: String = "") -> Tween:
	_snap_and_kill_actor_tween(actor_key, actor_node)
	_actor_target_pos[actor_key] = new_target_pos
	_actor_target_idle[actor_key] = idle_anim
	
	# 🌟 關鍵修正：不能 bind_node 在被 DISABLED 的怪物身上，否則 Tween 會跟著被凍結！
	# 改為由 CutsceneDirector 建立並強制設定 TWEEN_PAUSE_PROCESS，確保所有怪物都能順暢移動！
	var new_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_actor_tweens[actor_key] = new_tween
	return new_tween

# 🛡️ 防禦 3：劇本結束或離開場景時，清理所有殘留的 Tween（並將未走完的角色補位到終點）
func _clear_all_cutscene_tweens(snap_to_end: bool = true) -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = null
	
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null
	
	for key in _actor_tweens.keys():
		var t = _actor_tweens[key] as Tween
		if t and t.is_valid():
			var was_running = t.is_running()
			t.kill()
			if snap_to_end and was_running:
				var node = _get_player() if key == "player" else _get_actor_node(key)
				if is_instance_valid(node) and _actor_target_pos.has(key):
					node.global_position = _actor_target_pos[key]
					if _actor_target_idle.has(key) and _actor_target_idle[key] != "":
						var sp = _get_actor_sprite(node)
						if sp: sp.play(_actor_target_idle[key])
	_actor_tweens.clear()
	_actor_target_pos.clear()
	_actor_target_idle.clear()
	
# 🌟 自動收集要追蹤的目標小怪（支援從 Target Enemies、Permanent Hide Actors 或 Actors 自動抓取！）
func _setup_enemy_clear_trigger() -> void:
	_tracked_enemies.clear()
	
	# 1. 優先使用 Target Enemies 陣列裡設定的怪物
	for enemy in target_enemies:
		if is_instance_valid(enemy) and not _tracked_enemies.has(enemy):
			_tracked_enemies.append(enemy)
			
	# 2. 🌟 貼心防呆：如果你是把 m1, m2, m3 填在 Permanent Hide Actors 或 Actors 字典，直接自動幫你抓過來！
	if _tracked_enemies.is_empty():
		for key in permanent_hide_actors:
			if actors.has(key):
				var node = get_node_or_null(actors[key]) as Node2D
				if is_instance_valid(node) and not _tracked_enemies.has(node):
					_tracked_enemies.append(node)
					
	if _tracked_enemies.is_empty():
		for key in actors.keys():
			if key == "cat" or key == "npc": continue # 自動排除白貓！
			var node = get_node_or_null(actors[key]) as Node2D
			if is_instance_valid(node) and node != target_npc and not _tracked_enemies.has(node):
				_tracked_enemies.append(node)

	print("【CutsceneDirector: ", name, "】已綁定戰鬥全滅監聽，目標怪物數量：", _tracked_enemies.size())
	if _tracked_enemies.size() > 0:
		set_process(true) # 啟動即時監控！

# 🌟 每幀自動檢查怪物是否全滅（無論怪物是 queue_free 刪除、還是血量歸零，都能 100% 偵測！）
func _process(_delta: float) -> void:
	if not trigger_on_enemies_cleared or has_triggered:
		set_process(false)
		return
		
	# 步驟 A：如果怪物一開始是隱形埋伏的，要先等至少一隻怪物現身 (visible == true) 且不在對話中，才算戰鬥正式開始！
	if not _battle_started:
		for enemy in _tracked_enemies:
			if is_instance_valid(enemy) and enemy.visible:
				_battle_started = true
				break
		return
		
	# 步驟 B：如果此時正在播前一段劇情 (A012)，先不要判定，等進入實機戰鬥再說
	var player = _get_player()
	if player and player.is_in_dialogue:
		return
		
	# 步驟 C：檢查還有幾隻怪物活著
	var alive_count: int = 0
	for enemy in _tracked_enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree() and enemy.visible:
			var is_dead_flag = enemy.get("is_dead") if "is_dead" in enemy else false
			var current_hp = enemy.get("hp") if "hp" in enemy else 1
			if not is_dead_flag and current_hp > 0:
				alive_count += 1
				
	# 🌟 當存活數量歸零 ➡️ 觸發戰後劇情！
	if alive_count == 0:
		set_process(false)
		print("【CutsceneDirector: ", name, "】偵測到怪物全滅！將於 ", clear_delay, " 秒後啟動劇本：", target_timeline)
		await get_tree().create_timer(clear_delay).timeout
		if is_inside_tree() and not has_triggered:
			start_cutscene()

# 🌟 輔助函數：凍結隱形怪物的 AI，但保留 AnimatedSprite2D 動畫播放能力
func _freeze_hidden_actor(actor_node: Node2D) -> void:
	if actor_node and not actor_node.visible:
		actor_node.process_mode = Node.PROCESS_MODE_DISABLED
		var sprite = _get_actor_sprite(actor_node)
		if sprite:
			sprite.process_mode = Node.PROCESS_MODE_ALWAYS

# 🌟 輔助函數：安全取得玩家節點 (防止開場第一幀 DataManager.player_node 還沒賦值)
func _get_player() -> Node2D:
	if is_instance_valid(DataManager.player_node):
		return DataManager.player_node
	if get_tree() and get_tree().current_scene:
		var p = get_tree().current_scene.find_child("player", true, false)
		if p:
			DataManager.player_node = p
		return p as Node2D
	return null

# 🌟 輔助函數：根據暗號裡的名稱 ("npc" 或 "m1"、"m2") 抓出對應的角色節點
func _get_actor_node(actor_key: String) -> Node2D:
	if actor_key == "npc":
		return target_npc
	elif actors.has(actor_key):
		return get_node_or_null(actors[actor_key]) as Node2D
	return null

# 🌟 輔助函數：不管 AnimatedSprite2D 叫什麼名字，都能自動從角色身上抓出來！
func _get_actor_sprite(actor_node: Node2D) -> AnimatedSprite2D:
	if not is_instance_valid(actor_node): return null
	if "animated_sprite_2d" in actor_node and actor_node.animated_sprite_2d is AnimatedSprite2D:
		return actor_node.animated_sprite_2d
	var sprite = actor_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not sprite:
		sprite = actor_node.find_child("*Sprite*", true, false) as AnimatedSprite2D
	return sprite

# 🌟 輔助函數：演戲期間暫時關閉白貓/NPC 自身的腳本與狀態機，防止牠每幀把導演播放的動畫蓋掉！
func _set_actor_ai_active(actor_node: Node2D, active: bool) -> void:
	if not actor_node or not is_instance_valid(actor_node): return
	if not actor_node.visible: return # 隱形埋伏怪維持原本的凍結狀態即可
	
	actor_node.set_physics_process(active)
	actor_node.set_process(active)
	if "velocity" in actor_node and not active:
		actor_node.velocity = Vector2.ZERO
	if "state_machine" in actor_node and actor_node.state_machine:
		actor_node.state_machine.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	elif actor_node.has_node("StateMachine"):
		actor_node.get_node("StateMachine").process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		
	# 確保角色身上的動畫播放器在演戲期間永遠維持開啟！
	var sprite = _get_actor_sprite(actor_node)
	if sprite:
		sprite.process_mode = Node.PROCESS_MODE_ALWAYS

# ==========================================
# 🎬 玩家踩進觸發區 ➡️ 開拍！
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if body == _get_player() and not has_triggered:
		start_cutscene(body)
			
# 🌟 統一開拍函數（踩進區域、BaseMap 開場、怪物全滅 皆由此進入）
func start_cutscene(player_body: Node2D = null) -> void:
	if has_triggered: 
		return
	if DataManager.has_method("is_cutscene_completed") and DataManager.is_cutscene_completed(target_timeline):
		return
		
	if not player_body:
		player_body = _get_player()
	if not player_body:
		push_warning("【CutsceneDirector】找不到 player 節點，無法鎖定玩家！")
		return
		
	has_triggered = true
	is_active = true # 🌟 標記這場戲正式開拍！
	_last_advance_time = Time.get_ticks_msec() / 1000.0
	
	# 🌟 向 DataManager 永久登記這段劇情已觸發過，下次離開再重進地圖就不會再播！
	if DataManager.has_method("mark_cutscene_completed"):
		DataManager.mark_cutscene_completed(target_timeline)
	
	# 1. 徹底鎖住阿尼大腦與移動速度
	player_body.is_in_dialogue = true
	if "velocity" in player_body:
		player_body.velocity = Vector2.ZERO
	if player_body.state_machine:
		player_body.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if player_body.animated_sprite_2d:
		player_body.animated_sprite_2d.play("idle_down")
	
	# 🌟 同時暫停白貓/NPC 自身的移動腳本，讓導演能 100% 控制白貓的走路與轉頭動畫！
	_set_actor_ai_active(target_npc, false)
	for key in actors.keys():
		_set_actor_ai_active(get_node_or_null(actors[key]) as Node2D, false)
		
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
# 暗號格式： 動作:對象(player/cam/npc/m1/m2...):[目標點或秒數]:[移動動畫]:[停下動畫]:[秒數]
func _on_dialogic_signal(argument: String) -> void:
	if not is_active: return # 🌟 只有當前正在演出的導演才處理暗號！
	
	# 🌟 接收淡出電影黑邊的暗號 (交給 player_hud.gd 與黑底處理)
	if argument == "fade_out_cinematic":
		return
		
	var parts = argument.split(":")
	# 🌟 放寬為至少 2 格，這樣直接寫 "hide:npc" 或 "show:m1" 或 "shake:cam" 也能正常運作！
	if parts.size() < 2: return
	
	var action = parts[0].strip_edges()     # "walk"、"run"、"back"、"ambush"、"throw"、"glow"、"flash"、"beam"、"show"、"hide"、"pan"、"reset"、"zoom"、"shake"、"anim"
	var actor = parts[1].strip_edges()      # "player"、"cam"、"npc" 或 actors 字典裡的 "m1"、"m2"、"rock"
	var target_key = parts[2].strip_edges() if parts.size() >= 3 else ""
	
	# 🌟 智慧解析第 4 格以後的參數：數字當「秒數」，文字依序當「移動動畫」與「停下動畫」
	var custom_move_anim: String = ""
	var custom_idle_anim: String = ""
	var custom_duration: float = -1.0 # -1 代表未指定，將使用預設秒數
	
	for i in range(3, parts.size()):
		var param = parts[i].strip_edges()
		if param == "": continue
		if param.is_valid_float():
			custom_duration = param.to_float()
		elif param.begins_with("idle") and custom_idle_anim == "":
			# 🌟 如果只填了 idle_left，直接當作「停下動畫」，把移動動畫留給系統自動判斷左右！
			custom_idle_anim = param
		elif custom_move_anim == "":
			custom_move_anim = param
		elif custom_idle_anim == "":
			custom_idle_anim = param

	# 👻 🌟 專門用來隱藏與顯示角色的暗號 (支援 hide:npc、hide:m1 或帶淡出秒數 hide:m1:0.5)
	if action == "hide":
		var target_node = _get_player() if actor == "player" else _get_actor_node(actor)
		if is_instance_valid(target_node):
			var fade_time = target_key.to_float() if target_key.is_valid_float() else custom_duration
			if fade_time > 0.0:
				var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				tween.tween_property(target_node, "modulate:a", 0.0, fade_time)
				tween.tween_callback(func():
					if is_instance_valid(target_node):
						target_node.visible = false
						if actor != "player":
							target_node.process_mode = Node.PROCESS_MODE_DISABLED
				)
			else:
				target_node.visible = false
				if actor != "player":
					target_node.process_mode = Node.PROCESS_MODE_DISABLED
		return
	elif action == "show":
		var target_node = _get_player() if actor == "player" else _get_actor_node(actor)
		if is_instance_valid(target_node):
			var fade_time = target_key.to_float() if target_key.is_valid_float() else custom_duration
			target_node.visible = true
			var sprite = _get_actor_sprite(target_node)
			if sprite:
				sprite.process_mode = Node.PROCESS_MODE_ALWAYS
			if fade_time > 0.0:
				target_node.modulate.a = 0.0
				var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				tween.tween_property(target_node, "modulate:a", 1.0, fade_time)
			else:
				target_node.modulate.a = 1.0
		return

	# 以下指令至少需要 3 格參數 (但如果是 shake:cam 或 reset:cam 可以只寫 2 格！)
	if parts.size() < 3 and action != "shake" and action != "reset": return
	
	# 🎥 鏡頭運鏡邏輯 (支援單點 pan:cam:點1:秒數、多點連續 pan:cam:點1,點2:每段秒數)
	if actor == "cam":
		var cam = get_viewport().get_camera_2d()
		var player = _get_player()
		if not cam: return
		
		if action == "pan":
			# 🌟 支援用逗號 "," 串聯多個鏡頭定位點！(例如 cam_tree_pos,cam_tree_pos2)
			var point_keys = target_key.split(",")
			var valid_markers: Array[Node2D] = []
			for pk in point_keys:
				var k = pk.strip_edges()
				var actual_key = k if markers.has(k) else k.replace("_", " ")
				if markers.has(actual_key):
					var m = get_node_or_null(markers[actual_key]) as Node2D
					if m: valid_markers.append(m)
					
			if valid_markers.size() > 0:
				var duration = custom_duration if custom_duration > 0.0 else cam_pan_time
				var current_pos = cam.get_screen_center_position()
				cam.top_level = true
				cam.global_position = current_pos
				
				if _cam_tween and _cam_tween.is_valid() and _cam_tween.is_running():
					_cam_tween.kill()
				_cam_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				for m in valid_markers:
					_cam_tween.tween_property(cam, "global_position", m.global_position, duration)
				
		elif action == "reset" and is_instance_valid(player):
			var duration = custom_duration if custom_duration > 0.0 else cam_reset_time
			if _cam_tween and _cam_tween.is_valid() and _cam_tween.is_running():
				_cam_tween.kill()
			_cam_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			_cam_tween.tween_property(cam, "global_position", player.global_position, duration)
			_cam_tween.tween_callback(func():
				if is_instance_valid(cam):
					cam.top_level = false
					cam.position = Vector2.ZERO
			)
		elif action == "zoom":
			# 🔍 鏡頭縮放並維持狀態 (放大：zoom:cam:1.35:2.0 / 恢復原狀：zoom:cam:1.0:0.8)
			var zoom_val = target_key.to_float() if target_key.is_valid_float() else 1.0
			var duration = custom_duration if custom_duration > 0.0 else 0.5
			if _zoom_tween and _zoom_tween.is_valid() and _zoom_tween.is_running():
				_zoom_tween.kill()
			_zoom_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			_zoom_tween.tween_property(cam, "zoom", Vector2(zoom_val, zoom_val), duration)
			
		elif action == "shake":
			# 💥 鏡頭受擊短促搖晃 (支援 shake:cam 或 shake:cam:強度:秒數)
			var strength: float = target_key.to_float() if target_key.is_valid_float() else 8.0 # 預設中等強度 8 像素
			var duration: float = custom_duration if custom_duration > 0.0 else 0.2            # 預設短促時間 0.2 秒
			var step_count: int = 5
			var step_time: float = duration / float(step_count)
			
			if _shake_tween and _shake_tween.is_valid() and _shake_tween.is_running():
				_shake_tween.kill()
				cam.offset = Vector2.ZERO
				
			_shake_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			for i in range(step_count):
				# 強度隨次數遞減 (100% -> 80% -> 60% -> 40% -> 20%)，做出被打到的瞬間爆發與快速收斂感
				var current_str = strength * (1.0 - float(i) / float(step_count))
				# 左右交替猛烈震動，上下帶一點點隨機微幅偏移
				var dir_x = 1.0 if i % 2 == 0 else -1.0
				var offset_vec = Vector2(dir_x * current_str, randf_range(-current_str * 0.5, current_str * 0.5))
				_shake_tween.tween_property(cam, "offset", offset_vec, step_time)
			# 最後一瞬間精準歸零
			_shake_tween.tween_property(cam, "offset", Vector2.ZERO, 0.02)
		return

	# 🎭 原地單純切換動畫、投擲、畫筆發光、光束秒殺邏輯 (支援 player、npc、m1、m2...)
	if action == "anim":
		var player = _get_player()
		if actor == "player" and is_instance_valid(player):
			_snap_and_kill_actor_tween("player", player)
			if player.animated_sprite_2d:
				player.animated_sprite_2d.play(target_key)
		else:
			var current_npc = _get_actor_node(actor)
			if is_instance_valid(current_npc):
				_snap_and_kill_actor_tween(actor, current_npc)
				var npc_sprite = _get_actor_sprite(current_npc)
				if npc_sprite:
					npc_sprite.play(target_key)
		return
	elif action == "glow":
		var target_node = _get_player() if actor == "player" else _get_actor_node(actor)
		if is_instance_valid(target_node):
			var duration = custom_duration if custom_duration > 0.0 else 0.8
			var brush = target_node.get_node_or_null("MagicBrush") as Node2D
			var glow_target = brush if (brush and brush.visible) else target_node
			var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.tween_property(glow_target, "modulate", Color(4.0, 4.0, 4.0, 1.0), duration)
		return
	elif action == "flash":
		# 🌟 瞬間閃一下光又恢復原狀 (例如 flash:player:0.35 或 flash:brush:0.35)
		var target_node = _get_player() if actor == "player" else _get_actor_node(actor)
		if is_instance_valid(target_node):
			var duration = custom_duration if custom_duration > 0.0 else 0.35
			var brush = target_node.get_node_or_null("MagicBrush") as Node2D
			var flash_target = brush if (brush and brush.visible) else target_node
			var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			# 先在極短時間內衝高亮度 (HDR 發光)，再平滑退回原本顏色
			tween.tween_property(flash_target, "modulate", Color(4.5, 4.5, 5.0, 1.0), duration * 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tween.tween_property(flash_target, "modulate", Color.WHITE, duration * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	elif action == "beam":
		var shooter = _get_player() if actor == "player" else _get_actor_node(actor)
		var victim = _get_actor_node(target_key)
		if is_instance_valid(shooter) and is_instance_valid(victim):
			shooter.modulate = Color.WHITE
			var brush = shooter.get_node_or_null("MagicBrush") as Node2D
			if brush: brush.modulate = Color.WHITE
			
			var line = Line2D.new()
			line.width = 0.0
			line.default_color = Color(3.0, 3.0, 3.5, 1.0)
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.z_index = 50
			get_tree().current_scene.add_child(line)
			
			var start_pos = shooter.global_position + Vector2(0, -16)
			var end_pos = victim.global_position + Vector2(0, -16)
			line.add_point(start_pos)
			line.add_point(end_pos)
			
			var beam_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			beam_tween.tween_property(line, "width", 28.0, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			beam_tween.tween_property(line, "width", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			beam_tween.tween_callback(func(): 
				if is_instance_valid(line):
					line.queue_free()
			)
			
			var hit_dir = 1.0 if victim.global_position.x >= shooter.global_position.x else -1.0
			var hit_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			victim.modulate = Color(5.0, 5.0, 5.0, 1.0)
			hit_tween.tween_property(victim, "global_position", victim.global_position + Vector2(45.0 * hit_dir, 0), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			hit_tween.parallel().tween_property(victim, "modulate:a", 0.0, 0.35)
			hit_tween.tween_callback(func(): 
				if is_instance_valid(victim):
					victim.queue_free()
			)
		return
	elif action == "throw":
		var projectile = _get_actor_node(actor)      # 抓取石頭 (例如 "rock")
		var victim = _get_actor_node(target_key)     # 抓取被砸的怪物 (例如 "m2" 或 "m1")
		if is_instance_valid(projectile) and is_instance_valid(victim):
			_snap_and_kill_actor_tween(target_key, victim) # 確保被砸的怪物已經站到定位點上！
			var duration = custom_duration if custom_duration > 0.0 else 0.25
			projectile.visible = true
			projectile.modulate.a = 1.0
			projectile.rotation = 0.0
			
			var hit_pos = victim.global_position + Vector2(0, -24)
			var bounce_dir = -1.0 if projectile.global_position.x < victim.global_position.x else 1.0
			
			var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.tween_property(projectile, "global_position", hit_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(projectile, "rotation", TAU * 1.5, duration)
			
			tween.tween_callback(func():
				if is_instance_valid(projectile):
					var bounce_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
					var peak_pos = hit_pos + Vector2(28.0 * bounce_dir, -18.0)
					var ground_pos = hit_pos + Vector2(48.0 * bounce_dir, 24.0)
					bounce_tween.tween_property(projectile, "global_position", peak_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					bounce_tween.tween_property(projectile, "global_position", ground_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					bounce_tween.parallel().tween_property(projectile, "modulate:a", 0.0, 0.18)
					bounce_tween.tween_callback(func(): 
						if is_instance_valid(projectile):
							projectile.visible = false
					)
				
				if is_instance_valid(victim):
					var hit_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
					victim.modulate = Color(3.0, 3.0, 3.0, 1.0)
					hit_tween.tween_property(victim, "modulate", Color.WHITE, 0.2)
					var knockback_pos = victim.global_position + Vector2(-16.0 * bounce_dir, 0)
					hit_tween.parallel().tween_property(victim, "global_position", knockback_pos, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			)
		return

	# ==========================================
	# 🌟 移動前預處理：在計算相對座標 (self_right / player_right) 與方向之前，先把角色上一步未完成的 Tween 補位！
	# ==========================================
	var player_node = _get_player()
	var current_actor_node = player_node if actor == "player" else _get_actor_node(actor)
	if not is_instance_valid(current_actor_node): return
	
	# 如果該角色上一步還沒走完就被玩家連點跳過，這裡會先把他瞬間移到上一步的終點！
	_snap_and_kill_actor_tween(actor, current_actor_node)
	# 如果目標是參考阿尼的位置 (player_right / player_left)，也要確保阿尼本人已經站到定位點上！
	if (target_key == "player_right" or target_key == "player_left") and is_instance_valid(player_node):
		_snap_and_kill_actor_tween("player", player_node)

	# 🌟 智慧計算目標座標 (支援免 Marker 的動態位置，如 player_right、self_right，也自動容錯 markers 字典的底線與空白！)
	var target_pos: Vector2 = Vector2.ZERO
	var has_valid_target: bool = false

	if target_key == "player_right" and is_instance_valid(player_node):
		target_pos = player_node.global_position + Vector2(side_offset, 0)
		has_valid_target = true
	elif target_key == "player_left" and is_instance_valid(player_node):
		target_pos = player_node.global_position + Vector2(-side_offset, 0)
		has_valid_target = true
	elif target_key == "self_right":
		target_pos = current_actor_node.global_position + Vector2(step_offset, 0)
		has_valid_target = true
	elif target_key == "self_left":
		target_pos = current_actor_node.global_position + Vector2(-step_offset, 0)
		has_valid_target = true
	elif target_key == "self_up":
		target_pos = current_actor_node.global_position + Vector2(0, -step_offset)
		has_valid_target = true
	elif target_key == "self_down":
		target_pos = current_actor_node.global_position + Vector2(0, step_offset)
		has_valid_target = true
	elif markers.has(target_key) or markers.has(target_key.replace("_", " ")):
		var actual_key = target_key if markers.has(target_key) else target_key.replace("_", " ")
		var target_marker = get_node_or_null(markers[actual_key]) as Node2D
		if target_marker:
			target_pos = target_marker.global_position
			has_valid_target = true

	if not has_valid_target: return

	# 🌟 阿尼移動邏輯 (支援 walk、run、以及嚇到倒退一步 back，具備防連點覆蓋保護)
	if actor == "player":
		var player = player_node
		var is_moving_right = target_pos.x > player.global_position.x
		var move_anim = "move_right" if is_moving_right else "move_left"
		var idle_anim = "idle_right" if is_moving_right else "idle_left"
		
		if action == "back":
			move_anim = "move_left" if is_moving_right else "move_right"
			idle_anim = "idle_left" if is_moving_right else "idle_right"
		
		if custom_move_anim != "":
			move_anim = custom_move_anim
			if custom_idle_anim == "" and custom_move_anim.begins_with("move_"):
				idle_anim = custom_move_anim.replace("move_", "idle_")
				
		if custom_idle_anim != "":
			idle_anim = custom_idle_anim
			
		var tween = _create_safe_actor_tween("player", player, target_pos, idle_anim)
		
		if action == "walk":
			var duration = custom_duration if custom_duration > 0.0 else player_walk_time
			if player.animated_sprite_2d: player.animated_sprite_2d.play(move_anim)
			tween.tween_property(player, "global_position", target_pos, duration)
			tween.tween_callback(func(): 
				if is_instance_valid(player) and player.animated_sprite_2d:
					player.animated_sprite_2d.play(idle_anim)
			)
			
		elif action == "run":
			var duration = custom_duration if custom_duration > 0.0 else player_run_time
			if player.animated_sprite_2d: player.animated_sprite_2d.play(move_anim)
			tween.tween_property(player, "global_position", target_pos, duration)
			tween.tween_callback(func(): 
				if is_instance_valid(player) and player.animated_sprite_2d:
					player.animated_sprite_2d.play(idle_anim)
			)
			
		elif action == "back":
			var duration = custom_duration if custom_duration > 0.0 else 0.25
			if player.animated_sprite_2d: player.animated_sprite_2d.play(move_anim)
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(player, "global_position", target_pos, duration)
			tween.tween_callback(func(): 
				if is_instance_valid(player) and player.animated_sprite_2d:
					player.animated_sprite_2d.play(idle_anim)
			)
				
	# 🌟 單一 NPC 或 複數怪物/白貓 (cat, m1, m2...) 移動邏輯 (具備防連點覆蓋保護)
	else:
		var current_npc = current_actor_node
		var npc_sprite = _get_actor_sprite(current_npc)
		
		var is_moving_right = target_pos.x > current_npc.global_position.x
		var move_anim = custom_move_anim
		var idle_anim = custom_idle_anim
		var dir_suffix = "right" if is_moving_right else "left"
		
		if npc_sprite and npc_sprite.sprite_frames:
			var frames = npc_sprite.sprite_frames
			if move_anim == "":
				for candidate in ["move_" + dir_suffix, "walk_" + dir_suffix, "run_" + dir_suffix, "move", "walk", "run"]:
					if frames.has_animation(candidate):
						move_anim = candidate
						break
			if idle_anim == "":
				for candidate in ["idle_" + dir_suffix, "idle"]:
					if frames.has_animation(candidate):
						idle_anim = candidate
						break
						
		var tween = _create_safe_actor_tween(actor, current_npc, target_pos, idle_anim)
		
		# 確保角色身上的動畫播放器開啟，不會因為父節點 DISABLED 而卡住動畫幀
		if npc_sprite:
			npc_sprite.process_mode = Node.PROCESS_MODE_ALWAYS
			if move_anim != "":
				npc_sprite.play(move_anim)
			
		if action == "run":
			var duration = custom_duration if custom_duration > 0.0 else npc_run_time
			tween.tween_property(current_npc, "global_position", target_pos, duration)
			tween.parallel().tween_property(current_npc, "modulate:a", 0.0, npc_fade_time)
			tween.tween_callback(func(): 
				if is_instance_valid(current_npc):
					current_npc.visible = false
				if is_instance_valid(npc_sprite) and idle_anim != "":
					npc_sprite.play(idle_anim)
			)
		elif action == "walk":
			current_npc.visible = true
			current_npc.modulate.a = 1.0
			var duration = custom_duration if custom_duration > 0.0 else npc_walk_time
			tween.tween_property(current_npc, "global_position", target_pos, duration)
			tween.tween_callback(func():
				if is_instance_valid(npc_sprite) and idle_anim != "":
					npc_sprite.play(idle_anim)
			)
		elif action == "ambush":
			current_npc.visible = true
			current_npc.modulate.a = 1.0
			var duration = custom_duration if custom_duration > 0.0 else 0.35
			tween.tween_property(current_npc, "global_position", target_pos, duration)
			tween.tween_callback(func():
				if is_instance_valid(npc_sprite) and idle_anim != "":
					npc_sprite.play(idle_anim)
			)
		elif action == "knockback":
			# 💥 爆發擊退效果：受擊瞬間閃白光 + EXPO 爆發減速曲線震飛！
			current_npc.visible = true
			current_npc.modulate = Color(4.0, 4.0, 4.0, 1.0) # 受擊閃白光
			var duration = custom_duration if custom_duration > 0.0 else 0.25
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
			tween.tween_property(current_npc, "global_position", target_pos, duration)
			tween.parallel().tween_property(current_npc, "modulate", Color.WHITE, duration)
			tween.tween_callback(func():
				if is_instance_valid(npc_sprite) and idle_anim != "":
					npc_sprite.play(idle_anim)
			)

# 🔓 3. 劇本結束 ➡️ 解鎖阿尼，並清理殘留動畫、恢復場上角色 AI！
func _on_timeline_ended() -> void:
	if not is_active: return
	is_active = false
	_clear_all_cutscene_tweens(true) # 🌟 劇本結束瞬間，安全清光所有未完成的 Tween 並把角色補位到終點！
	
	var player = _get_player()
	if is_instance_valid(player) and player.is_in_dialogue:
		player.is_in_dialogue = false
		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
			
		if target_npc and is_instance_valid(target_npc) and target_npc.visible:
			target_npc.process_mode = Node.PROCESS_MODE_INHERIT
			_set_actor_ai_active(target_npc, true)
		for key in actors.keys():
			var actor_node = get_node_or_null(actors[key]) as Node2D
			if actor_node and is_instance_valid(actor_node) and actor_node.visible:
				actor_node.process_mode = Node.PROCESS_MODE_INHERIT
				_set_actor_ai_active(actor_node, true)
			
		var cam = get_viewport().get_camera_2d()
		if is_instance_valid(cam):
			cam.offset = Vector2.ZERO
			if cam.top_level:
				cam.top_level = false
				cam.position = Vector2.ZERO

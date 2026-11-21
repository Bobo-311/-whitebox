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

@export_group("📖 故事書幻燈片設定 (Undertale 風格黑底插圖)")
@export var storybook_images: Array[Texture2D] = []        # 🌟 按順序把 01.png ~ 08.png 拖進來！
@export var storybook_image_size: Vector2 = Vector2(960, 540) # 🌟 插圖顯示大小 (16:9，放在畫面正中偏上)
@export var storybook_offset_y: float = -90.0              # 🌟 插圖往上偏移量 (留出下方空間給對話框)

@export_group("🚪 劇本結束後自動跨地圖傳送 (選填)")
@export_file("*.tscn") var next_scene_after_cutscene: String = "" # 🌟 選取演完後要直接飛去的地圖 (如 AM002.tscn)
@export var next_spawn_marker_name: String = "From_Cabin"         # 🌟 去對面地圖時要站在哪根 Marker2D 定位針上
@export_enum("面向下 (Down):0", "面向上 (Up):1", "面向右 (Right):2", "面向左 (Left):3") 
var next_spawn_facing: int = 0                                    # 🌟 抵達新地圖時的初始面向

@export_group("📖 跨地圖記憶與角色去留設定")
@export var required_prerequisite: String = ""             # 🌟 必須先完成哪個劇本或旗標才能觸發？(如填 "got_key")
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
var _map_ready_for_trigger: bool = false # 🌟 過圖保護鎖：防止剛換地圖阿尼還沒瞬移到定位針時誤觸發！
var _cam_tween: Tween = null    # 🌟 記錄當前的鏡頭動畫，防止玩家按太快時兩個鏡頭動畫打架！
var _shake_tween: Tween = null  # 🌟 記錄鏡頭震動動畫，防止連續震動互搶
var _zoom_tween: Tween = null   # 🌟 記錄鏡頭縮放動畫，防止連續 zoom 互搶
var _actor_tweens: Dictionary = {}         # 🌟 記錄每個角色正在跑的移動 Tween (key: actor名稱 -> value: Tween)
var _actor_target_pos: Dictionary = {}     # 🌟 記錄每個角色這一步原本要走到的終點座標 (被跳過時瞬間補位！)
var _actor_target_idle: Dictionary = {}    # 🌟 記錄每個角色走完這一步後應該播放的待機動畫

# 📖 故事書動態 UI 節點紀錄
var _book_layer: CanvasLayer = null
var _book_bg: ColorRect = null
var _book_tex_rect: TextureRect = null
var _book_tween: Tween = null

@export var click_cooldown: float = 0.18   # 🌟 防連點冷卻秒數 (避免狂按空白鍵/滑鼠導致 Dialogic 與 Tween 崩潰)
var _last_advance_time: float = 0.0

# 🌟 輔助檢查：是否已滿足前置劇情條件？
func _is_prerequisite_met() -> bool:
	var req_flag: String = required_prerequisite.strip_edges()
	if req_flag != "" and DataManager.has_method("is_cutscene_completed"):
		return DataManager.is_cutscene_completed(req_flag)
	return true

func _ready() -> void:
	# 🌟 保險機制：進入新地圖時，確保阿尼不會因為上一張圖的 hide:player 而維持隱形！
	var init_p = _get_player()
	if is_instance_valid(init_p) and not init_p.visible:
		init_p.visible = true
		init_p.modulate.a = 1.0

	# 🌟 0. 前置條件檢查：如果還沒滿足前置條件（例如還沒去過小木屋拿鑰匙），直接關閉此導演的感應器！
	if not _is_prerequisite_met():
		monitoring = false
		set_process(false)
		# 確保地道門在還沒去過小木屋前是隱藏的
		if actors.has("door_at_floor"):
			var door_node = get_node_or_null(actors["door_at_floor"]) as Node2D
			if is_instance_valid(door_node):
				door_node.visible = false
		return

	# ==========================================
	# 🌟 0-B. 地道出口第 0 幀預先佈景：
	# ==========================================
	if actors.has("door_at_floor") and DataManager.has_method("is_cutscene_completed") and DataManager.is_cutscene_completed("got_key"):
		var door_node = get_node_or_null(actors["door_at_floor"]) as Node2D
		if is_instance_valid(door_node):
			door_node.visible = true
			door_node.modulate.a = 1.0
		call_deferred("_pre_stage_cabin_exit_cat")

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
					
		# (B-2) 🌟 如果是像「地道門 (door_at_floor)」這種演完應該留在場上的物件，重回地圖時自動保持顯示！
		if actors.has("door_at_floor") and not permanent_hide_actors.has("door_at_floor"):
			var door_node = get_node_or_null(actors["door_at_floor"]) as Node2D
			if door_node:
				door_node.visible = true
				door_node.modulate.a = 1.0
					
		# (C) 防呆：把場上其他原本就關眼睛隱形的埋伏怪也凍結 AI
		_freeze_hidden_actor(target_npc)
		for key in actors.keys():
			var actor_node = get_node_or_null(actors[key]) as Node2D
			_freeze_hidden_actor(actor_node)
		return

	# ==========================================
	# 🌟 2. 尚未看過此劇情的正常初始化
	# ==========================================
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)
	if not Dialogic.timeline_started.is_connected(_on_external_timeline_started):
		Dialogic.timeline_started.connect(_on_external_timeline_started)
	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)
		
	_freeze_hidden_actor(target_npc)
	for key in actors.keys():
		var actor_node = get_node_or_null(actors[key]) as Node2D
		_freeze_hidden_actor(actor_node)

	# 判斷觸發模式：進圖觸發 / 怪物全滅觸發 / 踩區域觸發
	if trigger_on_map_enter:
		monitoring = false
		set_process(false)
	elif trigger_on_enemies_cleared:
		monitoring = false
		set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		_setup_enemy_clear_trigger()
	else:
		set_process(false)
		monitoring = false
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
			
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().create_timer(0.2).timeout
		if not is_inside_tree() or has_triggered or not _is_prerequisite_met():
			return
		_map_ready_for_trigger = true
		monitoring = true
		
		await get_tree().physics_frame
		if not is_inside_tree() or has_triggered:
			return
		for body in get_overlapping_bodies():
			if body == _get_player():
				_auto_sync_cat_to_player(body, true)
				_on_body_entered(body)
				break

# 🌟 在轉場黑幕退去前，預先把地板門與白貓在 From_Cabin 旁擺好並解除隱藏！
func _pre_stage_cabin_exit_cat() -> void:
	await get_tree().process_frame
	var p = _get_player()
	if is_instance_valid(p) and global_position.distance_to(p.global_position) < 200.0:
		_auto_sync_cat_to_player(p, true)

# 🌟 輔助函數：自動尋找場上的白貓
func _find_cat_node() -> Node2D:
	var cat_node: Node2D = _get_actor_node("cat")
	if not cat_node and get_tree() and get_tree().current_scene:
		for candidate_name in ["white_cat", "WhiteCat", "White_cat", "Cat"]:
			cat_node = get_tree().current_scene.find_child(candidate_name, true, false) as Node2D
			if cat_node:
				break
	return cat_node

func _auto_sync_cat_to_player(player_body: Node2D, force_show: bool = false) -> void:
	if not is_instance_valid(player_body): return
	var cat_node: Node2D = _find_cat_node()
	if is_instance_valid(cat_node):
		if force_show or cat_node.global_position.distance_to(player_body.global_position) > 120.0 or not cat_node.visible:
			cat_node.global_position = player_body.global_position + Vector2(side_offset, 0)
			cat_node.visible = true
			cat_node.modulate.a = 1.0
			cat_node.process_mode = Node.PROCESS_MODE_INHERIT
			var sp = _get_actor_sprite(cat_node)
			if sp:
				sp.visible = true
				sp.modulate.a = 1.0
				sp.process_mode = Node.PROCESS_MODE_ALWAYS
				if sp.sprite_frames and sp.sprite_frames.has_animation("idle_left"):
					sp.play("idle_left")

func _exit_tree() -> void:
	_clear_all_cutscene_tweens(false)
	_destroy_storybook_ui()
	if Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.disconnect(_on_dialogic_signal)
	if Dialogic.timeline_started.is_connected(_on_external_timeline_started):
		Dialogic.timeline_started.disconnect(_on_external_timeline_started)
	if Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_timeline_ended)

func _on_external_timeline_started() -> void:
	if is_active or target_timeline == "":
		return
	if Dialogic.current_timeline and Dialogic.current_timeline.resource_path.get_file().get_basename() == target_timeline:
		is_active = true
		has_triggered = true
		_last_advance_time = Time.get_ticks_msec() / 1000.0

# ==========================================
# 📖 Undertale 風格故事書幻燈片 UI 系統 (100% 隔離光線版)
# ==========================================
func _ensure_storybook_ui() -> void:
	if is_instance_valid(_book_layer):
		return
	_book_layer = CanvasLayer.new()
	_book_layer.layer = 1
	add_child(_book_layer)
	
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if node != _book_layer and ("Dialogic" in node.name or "Layout" in node.name or node.layer == 1):
			if node.layer <= _book_layer.layer:
				node.layer = _book_layer.layer + 1
	
	var unshaded_mat := CanvasItemMaterial.new()
	unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	
	_book_bg = ColorRect.new()
	_book_bg.color = Color.BLACK
	_book_bg.material = unshaded_mat
	_book_bg.light_mask = 0
	_book_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_book_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book_bg.modulate.a = 0.0
	_book_layer.add_child(_book_bg)
	
	_book_tex_rect = TextureRect.new()
	_book_tex_rect.material = unshaded_mat
	_book_tex_rect.light_mask = 0
	_book_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_book_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_book_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_book_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book_tex_rect.set_anchors_preset(Control.PRESET_CENTER)
	_book_tex_rect.size = storybook_image_size
	_book_tex_rect.position = -storybook_image_size * 0.5 + Vector2(0, storybook_offset_y)
	_book_tex_rect.modulate.a = 0.0
	_book_layer.add_child(_book_tex_rect)

func _show_storybook_page(page_str: String, fade_time: float = 0.5) -> void:
	if _book_tween and _book_tween.is_valid():
		_book_tween.kill()
		
	if page_str == "hide" or page_str == "off" or page_str == "0":
		if not is_instance_valid(_book_layer):
			return
		var dur = fade_time if fade_time > 0.0 else 0.5
		_book_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_book_tween.tween_property(_book_tex_rect, "modulate:a", 0.0, dur)
		_book_tween.parallel().tween_property(_book_bg, "modulate:a", 0.0, dur)
		_book_tween.tween_callback(func():
			if is_instance_valid(_book_layer):
				_book_layer.visible = false
		)
		return
		
	var tex: Texture2D = null
	if page_str.is_valid_int():
		var idx = page_str.to_int() - 1
		if idx >= 0 and idx < storybook_images.size():
			tex = storybook_images[idx]
	elif ResourceLoader.exists(page_str):
		tex = load(page_str) as Texture2D
		
	if not tex:
		push_warning("【CutsceneDirector】找不到故事書圖片頁碼：" + page_str + "，請確認右侧 Inspector 的 Storybook Images 陣列已放入圖片！")
		return
		
	_ensure_storybook_ui()
	_book_layer.visible = true
	var dur = fade_time if fade_time > 0.0 else 0.45
	_book_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	if _book_bg.modulate.a < 0.95:
		_book_tex_rect.texture = tex
		_book_tex_rect.modulate.a = 0.0
		_book_tween.tween_property(_book_bg, "modulate:a", 1.0, dur)
		_book_tween.tween_property(_book_tex_rect, "modulate:a", 1.0, dur)
	else:
		_book_tween.tween_property(_book_tex_rect, "modulate:a", 0.0, dur * 0.45)
		_book_tween.tween_callback(func():
			if is_instance_valid(_book_tex_rect):
				_book_tex_rect.texture = tex
		)
		_book_tween.tween_property(_book_tex_rect, "modulate:a", 1.0, dur * 0.55)

func _destroy_storybook_ui() -> void:
	if _book_tween and _book_tween.is_valid():
		_book_tween.kill()
	_book_tween = null
	if is_instance_valid(_book_layer):
		_book_layer.queue_free()
	_book_layer = null
	_book_bg = null
	_book_tex_rect = null

func _input(event: InputEvent) -> void:
	if not is_active: return
	
	var is_click = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var is_key = event is InputEventKey and event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)
	var is_act = event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")
	
	if is_click or is_key or is_act:
		if event.is_echo():
			get_viewport().set_input_as_handled()
			return
		var now = Time.get_ticks_msec() / 1000.0
		if now - _last_advance_time < click_cooldown:
			get_viewport().set_input_as_handled()
			return
		_last_advance_time = now

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

func _create_safe_actor_tween(actor_key: String, actor_node: Node2D, new_target_pos: Vector2, idle_anim: String = "") -> Tween:
	_snap_and_kill_actor_tween(actor_key, actor_node)
	_actor_target_pos[actor_key] = new_target_pos
	_actor_target_idle[actor_key] = idle_anim
	
	var new_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_actor_tweens[actor_key] = new_tween
	return new_tween

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
	
func _setup_enemy_clear_trigger() -> void:
	_tracked_enemies.clear()
	
	for enemy in target_enemies:
		if is_instance_valid(enemy) and not _tracked_enemies.has(enemy):
			_tracked_enemies.append(enemy)
			
	if _tracked_enemies.is_empty():
		for key in permanent_hide_actors:
			if actors.has(key):
				var node = get_node_or_null(actors[key]) as Node2D
				if is_instance_valid(node) and not _tracked_enemies.has(node):
					_tracked_enemies.append(node)
					
	if _tracked_enemies.is_empty():
		for key in actors.keys():
			if key == "cat" or key == "npc": continue
			var node = get_node_or_null(actors[key]) as Node2D
			if is_instance_valid(node) and node != target_npc and not _tracked_enemies.has(node):
				_tracked_enemies.append(node)

	print("【CutsceneDirector: ", name, "】已綁定戰鬥全滅監聽，目標怪物數量：", _tracked_enemies.size())
	if _tracked_enemies.size() > 0:
		set_process(true)

func _process(_delta: float) -> void:
	if not trigger_on_enemies_cleared or has_triggered:
		set_process(false)
		return
		
	if not _battle_started:
		for enemy in _tracked_enemies:
			if is_instance_valid(enemy) and enemy.visible:
				_battle_started = true
				break
		return
		
	var player = _get_player()
	if player and player.is_in_dialogue:
		return
		
	var alive_count: int = 0
	for enemy in _tracked_enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree() and enemy.visible:
			var is_dead_flag = enemy.get("is_dead") if "is_dead" in enemy else false
			var current_hp = enemy.get("hp") if "hp" in enemy else 1
			if not is_dead_flag and current_hp > 0:
				alive_count += 1
				
	if alive_count == 0:
		set_process(false)
		print("【CutsceneDirector: ", name, "】偵測到怪物全滅！將於 ", clear_delay, " 秒後啟動劇本：", target_timeline)
		await get_tree().create_timer(clear_delay).timeout
		if is_inside_tree() and not has_triggered:
			start_cutscene()

func _freeze_hidden_actor(actor_node: Node2D) -> void:
	if actor_node and not actor_node.visible:
		actor_node.process_mode = Node.PROCESS_MODE_DISABLED
		var sprite = _get_actor_sprite(actor_node)
		if sprite:
			sprite.process_mode = Node.PROCESS_MODE_ALWAYS

func _get_player() -> Node2D:
	if is_instance_valid(DataManager.player_node):
		return DataManager.player_node
	if get_tree() and get_tree().current_scene:
		var p = get_tree().current_scene.find_child("player", true, false)
		if p:
			DataManager.player_node = p
		return p as Node2D
	return null

func _get_actor_node(actor_key: String) -> Node2D:
	if actor_key == "npc":
		return target_npc
	elif actors.has(actor_key):
		var n = get_node_or_null(actors[actor_key]) as Node2D
		if n: return n
	if actor_key == "cat" and get_tree() and get_tree().current_scene:
		for candidate_name in ["white_cat", "WhiteCat", "White_cat", "Cat"]:
			var c = get_tree().current_scene.find_child(candidate_name, true, false) as Node2D
			if c: return c
	return null

func _get_actor_sprite(actor_node: Node2D) -> AnimatedSprite2D:
	if not is_instance_valid(actor_node): return null
	if "animated_sprite_2d" in actor_node and actor_node.animated_sprite_2d is AnimatedSprite2D:
		return actor_node.animated_sprite_2d
	var sprite = actor_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not sprite:
		sprite = actor_node.find_child("*Sprite*", true, false) as AnimatedSprite2D
	return sprite

func _set_actor_ai_active(actor_node: Node2D, active: bool) -> void:
	if not actor_node or not is_instance_valid(actor_node): return
	if not actor_node.visible: return
	
	actor_node.set_physics_process(active)
	actor_node.set_process(active)
	if "velocity" in actor_node and not active:
		actor_node.velocity = Vector2.ZERO
	if "state_machine" in actor_node and actor_node.state_machine:
		actor_node.state_machine.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	elif actor_node.has_node("StateMachine"):
		actor_node.get_node("StateMachine").process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		
	var sprite = _get_actor_sprite(actor_node)
	if sprite:
		sprite.process_mode = Node.PROCESS_MODE_ALWAYS

# ==========================================
# 🎬 玩家踩進觸發區 ➡️ 開拍！
# ==========================================
func _on_body_entered(body: Node2D) -> void:
	if not _map_ready_for_trigger or DataManager.is_teleporting or Dialogic.current_timeline != null:
		return
	# 🌟 前置條件鎖：沒完成小木屋劇情前，絕對不觸發！
	if not _is_prerequisite_met():
		return
	if body == _get_player() and not has_triggered:
		start_cutscene(body)
			
func start_cutscene(player_body: Node2D = null) -> void:
	if has_triggered: 
		return
	if not _is_prerequisite_met():
		return
	if DataManager.has_method("is_cutscene_completed") and DataManager.is_cutscene_completed(target_timeline):
		return
		
	if not player_body:
		player_body = _get_player()
	if not player_body:
		push_warning("【CutsceneDirector】找不到 player 節點，無法鎖定玩家！")
		return
		
	has_triggered = true
	is_active = true
	_last_advance_time = Time.get_ticks_msec() / 1000.0
	
	if DataManager.has_method("mark_cutscene_completed"):
		DataManager.mark_cutscene_completed(target_timeline)
	
	player_body.is_in_dialogue = true
	if "velocity" in player_body:
		player_body.velocity = Vector2.ZERO
	if player_body.state_machine:
		player_body.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if player_body.animated_sprite_2d:
		player_body.animated_sprite_2d.play("idle_down")
	
	_set_actor_ai_active(target_npc, false)
	for key in actors.keys():
		_set_actor_ai_active(get_node_or_null(actors[key]) as Node2D, false)
		
	var layout = Dialogic.start(target_timeline)
	Dialogic.timeline_started.emit()
	
	if player_dch and player_body.has_node("BubbleMaker") and layout and layout.has_method("register_character"):
		layout.register_character(player_dch, player_body.get_node("BubbleMaker"))
		
	if npc_dch and target_npc and target_npc.has_node("BubbleMaker") and layout and layout.has_method("register_character"):
		layout.register_character(npc_dch, target_npc.get_node("BubbleMaker"))
		
# 🏃‍♂️ 2. 接收劇本暗號 ➡️ 指揮走位、運鏡與故事書翻頁
func _on_dialogic_signal(argument: String) -> void:
	if not is_active: return
	
	if argument == "fade_out_cinematic" or argument == "fade_in_cinematic":
		return
		
	if argument == "unlock_combat":
		print("【系統】收到解鎖戰鬥暗號！正式開啟攻擊！")
		if "combat_unlocked" in DataManager:
			DataManager.combat_unlocked = true
		var p = _get_player()
		if p and p.has_node("MagicBrush"):
			p.get_node("MagicBrush").visible = true
		return
		
	var parts = argument.split(":")
	if parts.size() < 2: return
	
	var action = parts[0].strip_edges()
	var actor = parts[1].strip_edges()
	var target_key = parts[2].strip_edges() if parts.size() >= 3 else ""
	
	# 📖 🌟 處理故事書幻燈片暗號
	if action == "book":
		var fade_dur: float = target_key.to_float() if target_key.is_valid_float() else 0.45
		_show_storybook_page(actor, fade_dur)
		return
	
	var custom_move_anim: String = ""
	var custom_idle_anim: String = ""
	var custom_duration: float = -1.0
	
	for i in range(3, parts.size()):
		var param = parts[i].strip_edges()
		if param == "": continue
		if param.is_valid_float():
			custom_duration = param.to_float()
		elif param.begins_with("idle") and custom_idle_anim == "":
			custom_idle_anim = param
		elif custom_move_anim == "":
			custom_move_anim = param
		elif custom_idle_anim == "":
			custom_idle_anim = param

	# 👻 專門用來隱藏與顯示角色的暗號
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
				sprite.visible = true
				sprite.modulate.a = 1.0
				sprite.process_mode = Node.PROCESS_MODE_ALWAYS
			if fade_time > 0.0:
				target_node.modulate.a = 0.0
				var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				tween.tween_property(target_node, "modulate:a", 1.0, fade_time)
			else:
				target_node.modulate.a = 1.0
		return

	if parts.size() < 3 and action != "shake" and action != "reset": return
	
	# 🎥 鏡頭運鏡邏輯
	if actor == "cam":
		var cam = get_viewport().get_camera_2d()
		var player = _get_player()
		if not cam: return
		
		if action == "pan":
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
			var zoom_val = target_key.to_float() if target_key.is_valid_float() else 1.0
			var duration = custom_duration if custom_duration > 0.0 else 0.5
			if _zoom_tween and _zoom_tween.is_valid() and _zoom_tween.is_running():
				_zoom_tween.kill()
			_zoom_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			_zoom_tween.tween_property(cam, "zoom", Vector2(zoom_val, zoom_val), duration)
			
		elif action == "shake":
			var strength: float = target_key.to_float() if target_key.is_valid_float() else 8.0
			var duration: float = custom_duration if custom_duration > 0.0 else 0.2
			var step_count: int = 5
			var step_time: float = duration / float(step_count)
			
			if _shake_tween and _shake_tween.is_valid() and _shake_tween.is_running():
				_shake_tween.kill()
				cam.offset = Vector2.ZERO
				
			_shake_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			for i in range(step_count):
				var current_str = strength * (1.0 - float(i) / float(step_count))
				var dir_x = 1.0 if i % 2 == 0 else -1.0
				var offset_vec = Vector2(dir_x * current_str, randf_range(-current_str * 0.5, current_str * 0.5))
				_shake_tween.tween_property(cam, "offset", offset_vec, step_time)
			_shake_tween.tween_property(cam, "offset", Vector2.ZERO, 0.02)
		return

	# 🎭 原地單純切換動畫、投擲、畫筆發光、光束秒殺邏輯
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
		var target_node = _get_player() if actor == "player" else _get_actor_node(actor)
		if is_instance_valid(target_node):
			var duration = custom_duration if custom_duration > 0.0 else 0.35
			var brush = target_node.get_node_or_null("MagicBrush") as Node2D
			var flash_target = brush if (brush and brush.visible) else target_node
			var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
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
		var projectile = _get_actor_node(actor)
		var victim = _get_actor_node(target_key)
		if is_instance_valid(projectile) and is_instance_valid(victim):
			_snap_and_kill_actor_tween(target_key, victim)
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
	# 🌟 移動前預處理：先把角色上一步未完成的 Tween 補位！
	# ==========================================
	var player_node = _get_player()
	var current_actor_node = player_node if actor == "player" else _get_actor_node(actor)
	if not is_instance_valid(current_actor_node): return
	
	_snap_and_kill_actor_tween(actor, current_actor_node)
	if (target_key == "player_right" or target_key == "player_left") and is_instance_valid(player_node):
		_snap_and_kill_actor_tween("player", player_node)

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

	# ⚡ 🌟 強化版 snap 瞬間定位指令：連被 DISABLED 或隱藏的白貓都會強制解鎖現形！
	if action == "snap":
		current_actor_node.global_position = target_pos
		current_actor_node.visible = true
		current_actor_node.modulate.a = 1.0
		current_actor_node.process_mode = Node.PROCESS_MODE_INHERIT
		_set_actor_ai_active(current_actor_node, false) # 演戲期間先暫停自主亂跑
		var sp = _get_actor_sprite(current_actor_node)
		if sp:
			sp.visible = true
			sp.modulate.a = 1.0
			sp.process_mode = Node.PROCESS_MODE_ALWAYS
			if custom_idle_anim != "" and sp.sprite_frames and sp.sprite_frames.has_animation(custom_idle_anim):
				sp.play(custom_idle_anim)
			elif custom_move_anim != "" and sp.sprite_frames and sp.sprite_frames.has_animation(custom_move_anim):
				sp.play(custom_move_anim)
		return

	# 🌟 阿尼移動邏輯
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
				
	# 🌟 單一 NPC 或 複數怪物/白貓 (cat, m1, m2...) 移動邏輯
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
		elif action == "jump":
			current_npc.visible = true
			current_npc.modulate.a = 1.0
			var duration = custom_duration if custom_duration > 0.0 else 0.6
			
			if is_instance_valid(npc_sprite) and move_anim != "":
				npc_sprite.stop()
				npc_sprite.play(move_anim)
				
			tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(current_npc, "global_position", target_pos, duration)
			tween.tween_callback(func():
				if is_instance_valid(npc_sprite) and idle_anim != "":
					npc_sprite.play(idle_anim)
				var cam = get_viewport().get_camera_2d()
				if is_instance_valid(cam):
					var land_shake = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
					for i in range(6):
						var s = 18.0 * (1.0 - float(i) / 6.0)
						var dir_x = 1.0 if i % 2 == 0 else -1.0
						land_shake.tween_property(cam, "offset", Vector2(dir_x * s, randf_range(-s, s * 0.5)), 0.04)
					land_shake.tween_property(cam, "offset", Vector2.ZERO, 0.02)
			)
		elif action == "knockback":
			current_npc.visible = true
			current_npc.modulate = Color(4.0, 4.0, 4.0, 1.0)
			var duration = custom_duration if custom_duration > 0.0 else 0.25
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
			tween.tween_property(current_npc, "global_position", target_pos, duration)
			tween.parallel().tween_property(current_npc, "modulate", Color.WHITE, duration)
			tween.tween_callback(func():
				if is_instance_valid(npc_sprite) and idle_anim != "":
					npc_sprite.play(idle_anim)
			)

# 🔓 3. 劇本結束 ➡️ 解鎖阿尼，並清理殘留動畫、故事書 UI 與恢復場上角色 AI！
func _on_timeline_ended() -> void:
	if not is_active: return
	is_active = false
	_clear_all_cutscene_tweens(true)
	_destroy_storybook_ui()
	
	var player = _get_player()
	if is_instance_valid(player):
		if next_scene_after_cutscene != "":
			var facing_vec := Vector2.DOWN
			match next_spawn_facing:
				1: facing_vec = Vector2.UP
				2: facing_vec = Vector2.RIGHT
				3: facing_vec = Vector2.LEFT
				
			print("【CutsceneDirector】劇情結束！維持隱形並透過密道傳送至：", next_scene_after_cutscene, " 定位點：", next_spawn_marker_name)
			SceneTransition.change_map(next_scene_after_cutscene, next_spawn_marker_name, facing_vec)
			return
			
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
		var auto_cat = _find_cat_node()
		if is_instance_valid(auto_cat) and auto_cat.visible:
			auto_cat.process_mode = Node.PROCESS_MODE_INHERIT
			_set_actor_ai_active(auto_cat, true)
			
		var cam = get_viewport().get_camera_2d()
		if is_instance_valid(cam):
			cam.offset = Vector2.ZERO
			if cam.top_level:
				cam.top_level = false
				cam.position = Vector2.ZERO

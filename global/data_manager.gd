extends Node

# ==========================================
# 🖱️ 全域滑鼠設定 (軟體游標 + 物理打擊感)
# ==========================================
const CURSOR_SIZE_RATIO := 0.85 # 一般與點擊游標共用的顯示比例

var cursor_normal = preload("res://雜/cursor_normal.png")
var cursor_click = preload("res://雜/cursor_click_no_cross.png")

var cursor_layer: CanvasLayer
var cursor_rect: TextureRect

# ==========================================
# 📻 廣播電台系統 (事件驅動)
# ==========================================
signal map_changed(new_map_name: String) # 廣播：玩家跨地圖了！UI 快更新地圖名字！
signal equipment_changed                 # 廣播：玩家換裝備了！玩家肉體快重新計算血量！
signal quick_slot_updated                # 廣播：道具數量變了！左下角快捷欄快更新數字！

# ==========================================
# 🧠 全域變數儲存區 (跨場景大腦記憶體)
# ==========================================
var current_map_name: String = "鐘塔" # 記錄玩家現在在哪張地圖，預設是鐘塔
var is_teleporting: bool = false # 記錄玩家是不是正在使用傳送門 (防呆用)

var total_gold: int = 0 # 玩家口袋裡的總財產
var player_node: Node2D = null # 一個變數用來「抓住」玩家實體，讓所有 UI 都能透過大腦找到玩家

# --- 存檔點 (篝火) 系統 ---
var last_save_position: Vector2 = Vector2.ZERO # 記錄玩家點擊畫架時腳踩的確切座標，死掉就在這裡重生
var saved_hp: float = 0     # 存檔時的小抄：玩家最大血量 (重載場景時用來把血補滿)

# --- 靈魂回收系統 (撿屍體機制) ---
var has_soul_on_ground: bool = false # 記錄地圖上現在有沒有掉落的靈魂
var soul_spawn_pos: Vector2 = Vector2.ZERO # 記錄靈魂該生成在哪個座標
var soul_stored_gold: int = 0 # 記錄那個靈魂身上帶了玩家多少錢
var save_map_path: String = "" # 記錄玩家最後是在哪張地圖存檔的
var soul_map_path: String = "" # 記錄玩家死掉、噴裝的那張地圖是哪一張

# ==========================================
# 📔 貼紙系統核心資料庫
# ==========================================
var equipped_stickers: Array[String] = ["", "", "", ""]
var owned_stickers: Array[String] = []

const STICKER_DB = {
	"001": {
		"name": "心連心",
		"texture_path": "res://Stickers/心連心.png",
		"type": "max_hp_boost",
		"value": 20
	},
	"004": {
		"name": "你真星啊",
		"texture_path": "res://Stickers/你真星啊.png",
		"type": "heal_on_kill",
		"value": 0.10
	},
	"006": {
		"name": "正中紅心",
		"texture_path": "res://Stickers/正中紅心.png",
		"type": "skill_dmg_multiplier",
		"value": 1.35
	},
	"008": {
		"name": "筆到絕境",
		"texture_path": "res://Stickers/筆到絕境.png",
		"type": "low_hp_atk_boost",
		"value": 1.35,
		"threshold": 0.35
	},
	"016": {
		"name": "真的好堡",
		"texture_path": "res://Stickers/真的好堡.png",
		"type": "heal_item_boost",
		"value": 10
	}
}

# ==========================================
# 🎒 道具與快捷欄系統 (全面升級版)
# ==========================================
const ITEM_DB = {
	"eraser": {
		"name": "藍色橡皮擦", "max_carry": 3, "duration": 30.0, "multiplier": 0.80,
		"description": "受到的傷害減少 20%，持續 30 秒。再次使用可刷新時間。",
		"story": "沾著藍墨的橡皮，能擦淡夢裡留下的傷痕。", "texture_path": "res://ItemsPack/Items/eraser.png"
	},
	"calyon": {
		"name": "紅色蠟筆", "max_carry": 3, "duration": 30.0, "multiplier": 1.25,
		"description": "近戰傷害增加 25%，持續 30 秒。再次使用可刷新時間。",
		"story": "筆尖殘留一道鮮紅，每次揮筆都把顏色壓得更深。", "texture_path": "res://ItemsPack/Items/calyon.png"
	},
	"ruler": {
		"name": "黃色的尺", "max_carry": 3, "duration": 30.0, "multiplier": 1.25,
		"description": "遠程傷害增加 25%，持續 30 秒。再次使用可刷新時間。",
		"story": "透過金黃刻度瞄準，墨彈會沿著筆直的光跡飛去。", "texture_path": "res://ItemsPack/Items/ruler.png"
	},
	"hp_paint": {
		"name": "顏料",
		"max_carry": 3, # 🌟 起手可喝 3 次
		"heal_amount": 35, # 🌟 每次回血量 (可依平衡調整)
		"is_auto_refill": true, # 🌟 標記為「元素瓶機制」：在畫架休息時無條件免費補滿！
		"description": "散發微光的顏料。\n恢復 35 HP（於畫架處自動補滿）",
		"story": "在畫架上发现的神秘颜料，饮用后能修补受损的色彩与生命力，每次在画架前休息都会重新凝结填满。",
		"texture_path": "res://雜/color_bottle.png" # ⚠️ 請換成藍色顏料的圖片路徑！
	},
	"potion_gugu": {
		"name": "咕咕嘎嘎药水",
		"max_carry": 2, 
		"heal_amount": 20, 
		"description": "不知道是什么，但听起来很好吃。\n恢复 20 HP",
		"story": "不知道是什么，但听起来很好吃。据说是某个在森林迷路的小孩发明的。",
		"texture_path": "res://ItemsPack/Items/99.png" 
	},
	"miracle_apple": {
		"name": "奇迹苹果",
		"max_carry": 1, 
		"heal_amount": 10, 
		"description": "又脆又甜的苹果。\n恢复 10 HP",
		"story": "森林里随处可见的野苹果，据说在极度饥饿时吃下，会发生微小的奇迹。",
		"texture_path": "res://ItemsPack/Items/64.png" 
	},
	"steak_bone": {
		"name": "烤带骨牛排",
		"max_carry": 1, 
		"heal_amount": 50, 
		"description": "香气四溢的带骨肉排。\n恢复 50 HP",
		"story": "表面烤得微焦，切开却是完美的粉红色。光是闻到味道就能让人涌现无限力量。",
		"texture_path": "res://ItemsPack/Items/74.png" 
	},
	"energy_drink": {
		"name": "蓝色提神水",
		"max_carry": 1, 
		"heal_amount": 5, 
		"description": "喝起来像气泡水。\n恢复 5 HP",
		"story": "标签上写着「未满十二岁请勿饮用」，但森林里根本没人在乎这种规定。",
		"texture_path": "res://ItemsPack/Items/63.png" 
	},
	"item_xibaluma": {
		"name": "飛速藥水",
		"max_carry": 1, 
		"heal_amount": 0, # 暫時不補血，純收藏或以後補速度
		"description": "神秘的道具。\n速度 +10",
		"story": "没人知道这是什么，但据说带着它会健步如飞。成分不明，请斟酌使用。",
		"texture_path": "res://ItemsPack/Items/28.png" 
	}
}

var inventory_items = {
	# 🌟 藍色顏料開局預設為 0 且尚未解鎖 (unlocked: false)，等第一次碰到畫架才獲得！
	"hp_paint": { "current_carry": 0, "reserve_amount": 0, "unlocked": false },
	"potion_gugu": { "current_carry": 2, "reserve_amount": 0 },
	"miracle_apple": { "current_carry": 1, "reserve_amount": 0 },
	"steak_bone": { "current_carry": 1, "reserve_amount": 0 },
	"energy_drink": { "current_carry": 1, "reserve_amount": 0 },
	"item_xibaluma": { "current_carry": 1, "reserve_amount": 0 }
}

const COMBAT_ITEMS := ["eraser", "calyon", "ruler"]
var combat_item_seconds: Dictionary = {}

func grant_combat_items() -> void:
	for id in COMBAT_ITEMS:
		if not inventory_items.has(id):
			inventory_items[id] = {"current_carry": 0, "reserve_amount": 0}
		var item: Dictionary = inventory_items[id]
		item["unlocked"] = true
		if item["current_carry"] < ITEM_DB[id]["max_carry"]:
			item["current_carry"] += 1
		else:
			item["reserve_amount"] += 1
		if not quick_slots.has(id):
			var empty := quick_slots.find("")
			if empty >= 0:
				quick_slots[empty] = id
	quick_slot_updated.emit()

func combat_item_multiplier(id: String) -> float:
	if combat_item_seconds.has(id):
		return ITEM_DB[id]["multiplier"]
	return 1.0

var quick_slots: Array[String] = ["", "", "", "", ""]
var current_slot_index: int = 0

# ==========================================
# 🎯 全域初始化 (開局設定預設滑鼠與劇本接收器)
# ==========================================
func _ready() -> void:
	# 🌟 1. 隱藏系統預設的硬體滑鼠
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# 🌟 2. 建立一個永遠在最上層 (Layer 128) 的畫布，專門用來畫我們的假滑鼠
	cursor_layer = CanvasLayer.new()
	cursor_layer.layer = 128 
	add_child(cursor_layer)
	
	# 🌟 3. 建立假滑鼠圖片
	cursor_rect = TextureRect.new()
	cursor_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_set_cursor_texture(cursor_normal)
	# ⚠️ 極度重要：設定為 IGNORE，假滑鼠才不會變成一面物理盾牌擋住你的 UI 按鈕！
	cursor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	
	# 如果箭頭不在圖片最左上角，可以在這裡設定偏移 (通常設 Vector2.ZERO 即可)
	# cursor_rect.position = Vector2(-5, -5) 
	
	cursor_layer.add_child(cursor_rect)
	
	if not Dialogic.signal_event.is_connected(_on_global_dialogic_signal):
		Dialogic.signal_event.connect(_on_global_dialogic_signal)

# ==========================================
# 🌟 全域硬體輸入攔截 (控制滑鼠點擊切換與特效)
# ==========================================
# 每幀更新：讓假滑鼠緊緊貼著真實的游標座標
func _process(delta: float) -> void:
	for id in combat_item_seconds.keys():
		combat_item_seconds[id] -= delta
		if combat_item_seconds[id] <= 0.0:
			combat_item_seconds.erase(id)
	_sync_buff_display()
	if is_instance_valid(cursor_rect):
		cursor_rect.global_position = get_viewport().get_mouse_position()

func _input(event: InputEvent) -> void:
	# 監聽滑鼠的點擊與放開
	if event is InputEventMouseButton:

		# ================== 左鍵與右鍵共用邏輯 ==================
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if is_instance_valid(cursor_rect):
					_set_cursor_texture(cursor_click)
					_play_cursor_bounce_effect()
			else:
				# 當按鍵放開時，必須確認另一邊也沒有被按著，才切回普通游標
				if is_instance_valid(cursor_rect) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
					_set_cursor_texture(cursor_normal)

func _set_cursor_texture(texture: Texture2D) -> void:
	cursor_rect.texture = texture
	cursor_rect.size = texture.get_size() * CURSOR_SIZE_RATIO

# 🌟 抽出來共用的游標 Q 彈特效
func _play_cursor_bounce_effect() -> void:
	var tween = create_tween()
	cursor_rect.pivot_offset = Vector2.ZERO # 確保從左上角縮放
	cursor_rect.scale = Vector2(0.75, 0.75) 
	tween.tween_property(cursor_rect, "scale", Vector2.ONE, 0.15)\
		 .set_trans(Tween.TRANS_BACK)\
		 .set_ease(Tween.EASE_OUT)

# ==========================================
# ⚙️ 系統與工具函數
# ==========================================
func update_map_name(new_name: String) -> void:
	current_map_name = new_name 
	map_changed.emit(current_map_name) 

func has_sticker(sticker_id: String) -> bool:
	return sticker_id in equipped_stickers 

func add_item_to_reserve(item_id: String, amount: int) -> void:
	if inventory_items.has(item_id):
		inventory_items[item_id]["reserve_amount"] += amount
	else:
		inventory_items[item_id] = {
			"current_carry": 0,
			"reserve_amount": amount
		}
	print("【大腦】獲得道具：", item_id, "，目前庫存總數：", inventory_items[item_id]["reserve_amount"])

func unlock_auto_refill_item(item_id: String) -> void:
	if not ITEM_DB.has(item_id):
		return
	var max_c: int = ITEM_DB[item_id]["max_carry"]
	if not inventory_items.has(item_id):
		inventory_items[item_id] = { "current_carry": max_c, "reserve_amount": 0, "unlocked": true }
	else:
		inventory_items[item_id]["unlocked"] = true
		inventory_items[item_id]["current_carry"] = max_c
		
	if not quick_slots.has(item_id):
		for i in range(quick_slots.size()):
			if quick_slots[i] == "":
				quick_slots[i] = item_id
				current_slot_index = i
				break
	print("【大腦】成功獲得並解鎖元素瓶道具：", item_id, "，已補滿至 ", max_c, " 次！")
	quick_slot_updated.emit()

func get_item_count(item_id: String) -> int:
	if inventory_items.has(item_id):
		return inventory_items[item_id]["current_carry"]
	return 0

func rotate_quick_slot(direction: int) -> void:
	var slots_count = quick_slots.size()
	for i in range(slots_count):
		current_slot_index = (current_slot_index + direction + slots_count) % slots_count
		if quick_slots[current_slot_index] != "":
			print("【系統】快捷欄切換至第 ", current_slot_index + 1, " 格：", quick_slots[current_slot_index])
			quick_slot_updated.emit() 
			return

# 🍎 使用道具 (所有道具用完皆保留並變灰)
func use_current_item() -> void:
	var item_id = quick_slots[current_slot_index]
	
	if item_id == "": 
		return
		
	if get_item_count(item_id) <= 0: 
		print("【系統】道具數量不足 (喀喀聲)")
		return
		
	if item_id in COMBAT_ITEMS:
		combat_item_seconds[item_id] = ITEM_DB[item_id]["duration"]
		_show_item_use(item_id)
	inventory_items[item_id]["current_carry"] -= 1
	print("【系統】使用了 ", item_id, "，身上剩餘：", inventory_items[item_id]["current_carry"])
	
	if player_node and ITEM_DB[item_id].has("heal_amount"):
		var heal_value = ITEM_DB[item_id]["heal_amount"]
		player_node.heal(heal_value)
		
	if inventory_items[item_id]["current_carry"] <= 0:
		print("【系統】道具用盡！留在快捷欄上顯示 0 數量並變灰。")
			
	quick_slot_updated.emit() 

# 🌟 升級版畫架補給：同時支援「元素瓶免費自動回滿 (hp_paint)」與「一般道具從倉庫調貨」！
func replenish_quick_slots() -> void:
	print("【系統】抵達畫架存檔點！開始補充顏料與調用倉庫物資...")
	var has_replenished = false
	
	for item_id in inventory_items.keys():
		if ITEM_DB.has(item_id) and ITEM_DB[item_id].get("is_auto_refill", false):
			if inventory_items[item_id].get("unlocked", false):
				var max_carry = ITEM_DB[item_id]["max_carry"]
				if inventory_items[item_id]["current_carry"] < max_carry:
					inventory_items[item_id]["current_carry"] = max_carry
					has_replenished = true
					print("【畫架共鳴】", ITEM_DB[item_id]["name"], " 已自動補滿至 ", max_carry, " 次！")
	
	for item_id in quick_slots:
		if item_id != "" and inventory_items.has(item_id) and ITEM_DB.has(item_id):
			if ITEM_DB[item_id].get("is_auto_refill", false):
				continue 
				
			var max_carry = ITEM_DB[item_id]["max_carry"]
			var current = inventory_items[item_id]["current_carry"]
			var reserve = inventory_items[item_id]["reserve_amount"]
			
			var need_amount = max_carry - current
			
			if need_amount > 0 and reserve > 0:
				var add_amount = min(need_amount, reserve)
				inventory_items[item_id]["current_carry"] += add_amount
				inventory_items[item_id]["reserve_amount"] -= add_amount
				has_replenished = true
				print("【補給成功】", item_id, " 補充了 ", add_amount, " 個。倉庫剩餘: ", inventory_items[item_id]["reserve_amount"])
				
	if has_replenished:
		quick_slot_updated.emit()

# ==========================================
# 💥 打擊感卡頓/頓幀系統 (Hitstop)
# ==========================================
func trigger_hitstop(duration: float = 0.08, freeze_scale: float = 0.05) -> void:
	Engine.time_scale = freeze_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func hitstop(duration: float = 0.08, time_scale: float = 0.05) -> void:
	trigger_hitstop(duration, time_scale)

# ==========================================
# 💥 近戰處決專用 (Hitstop + 動態縮放)
# ==========================================
func trigger_execution_hitstop(duration: float = 0.2, slow_scale: float = 0.2) -> void:
	Engine.time_scale = slow_scale
	
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_zoom_pulse"):
		camera.apply_zoom_pulse(1.06) 
		
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
		
# ==========================================
# 📖 劇情觸發紀錄 (跨地圖永久保存)
# ==========================================
var completed_cutscenes: Array[String] = []

# 檢查某段劇本是否已經看過
func is_cutscene_completed(timeline_id: String) -> bool:
	if timeline_id == "": return false
	return completed_cutscenes.has(timeline_id)

# 將劇本標記為已看過
func mark_cutscene_completed(timeline_id: String) -> void:
	if timeline_id != "" and not completed_cutscenes.has(timeline_id):
		completed_cutscenes.append(timeline_id)
		
# 🌟 戰鬥能力總開關：只要看過 "A012" 劇本，或是手動設為 true，就會永久解鎖戰鬥！
var combat_unlocked: bool = false

func can_combat() -> bool:
	if combat_unlocked:
		return true
	# 如果已經完成 A012 劇情，自動視為已解鎖戰鬥！
	if has_method("is_cutscene_completed") and is_cutscene_completed("A012"):
		return true
	return false

# ==========================================
# 🎯 全域劇本暗號接收器 (在任何劇本發 signal 都能改寫大腦資料！)
# ==========================================
func _on_global_dialogic_signal(arg: String) -> void:
	# 1. 支援手動標記任務完成：例如在 A014D 劇本寫 [signal arg="complete:got_cargo"]
	if arg.begins_with("complete:"):
		var flag_name = arg.split(":")[1].strip_edges()
		mark_cutscene_completed(flag_name)
		print("【大腦】收到劇本暗號，已登記任務進度：", flag_name)
		
	# 2. 支援在劇本中直接贈送貼紙：例如在 A014E 寫 [signal arg="give_sticker:001"]
	elif arg.begins_with("give_sticker:"):
		var sticker_id = arg.split(":")[1].strip_edges()
		if not owned_stickers.has(sticker_id):
			owned_stickers.append(sticker_id)
			print("【大腦】從劇情獲得新貼紙：", sticker_id)
			
	elif arg.begins_with("unlock_item:"):
		var item_id = arg.split(":")[1].strip_edges()
		unlock_auto_refill_item(item_id)

const ITEM_FX_COLORS := {"eraser": Color("#79cfff"), "calyon": Color("#ff8187"), "ruler": Color("#ffd665")}
const ITEM_FX_TEXT := {"eraser": "受傷減免", "calyon": "近戰強化", "ruler": "遠程強化"}
var buff_stack: VBoxContainer
var buff_seconds_labels := {}

func _ensure_buff_stack() -> bool:
	if not is_instance_valid(player_node):
		return false
	var hud := player_node.get_node_or_null("PlayerHUD") as CanvasLayer
	if not hud:
		return false
	if is_instance_valid(buff_stack) and buff_stack.get_parent() == hud:
		return true
	if is_instance_valid(buff_stack):
		buff_stack.hide()
		buff_stack.queue_free()
	buff_seconds_labels.clear()
	buff_stack = VBoxContainer.new()
	buff_stack.name = "ActiveItemEffects"
	buff_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(buff_stack)
	buff_stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	buff_stack.offset_left = -20
	buff_stack.offset_right = -20
	buff_stack.offset_top = -24
	buff_stack.offset_bottom = -24
	buff_stack.alignment = BoxContainer.ALIGNMENT_END
	buff_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buff_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return true

func _sync_buff_display() -> void:
	if combat_item_seconds.is_empty() and buff_seconds_labels.is_empty():
		return
	if not _ensure_buff_stack():
		return
	for id in COMBAT_ITEMS:
		if combat_item_seconds.has(id):
			if not buff_seconds_labels.has(id):
				buff_seconds_labels[id] = _add_buff_row(id)
			var label: Label = buff_seconds_labels[id]
			label.text = "%d 秒" % ceili(combat_item_seconds[id])
		elif buff_seconds_labels.has(id):
			var old_row := buff_stack.get_node(NodePath(id))
			buff_stack.remove_child(old_row)
			old_row.queue_free()
			buff_seconds_labels.erase(id)

func _add_buff_row(id: String) -> Label:
	var panel := PanelContainer.new()
	panel.name = id
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink: Color = ITEM_FX_COLORS[id]
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#211d30ed")
	style.border_color = ink
	style.border_width_left = 3
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	buff_stack.add_child(panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load(ITEM_DB[id].texture_path)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)
	row.add_child(icon)
	var title := Label.new()
	title.text = ITEM_FX_TEXT[id]
	title.modulate = ink
	row.add_child(title)
	var remaining := Label.new()
	remaining.custom_minimum_size.x = 46
	remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(remaining)
	return remaining

func _show_item_use(id: String) -> void:
	_sync_buff_display()
	if not is_instance_valid(player_node):
		return
	var hud := player_node.get_node_or_null("PlayerHUD") as CanvasLayer
	if not hud or not hud.visible:
		return
	var pop := Sprite2D.new()
	pop.texture = load(ITEM_DB[id].texture_path)
	pop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pop.z_index = 10
	player_node.add_child(pop)
	var height := 36.0
	if "ink_switch_badge_offset" in player_node:
		height = absf(player_node.ink_switch_badge_offset.y)
	pop.position = Vector2(0, -height)
	var icon_scale := Vector2.ONE * (32.0 / maxf(pop.texture.get_width(), pop.texture.get_height()))
	pop.scale = icon_scale * 0.55
	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "scale", icon_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(pop, "position:y", -height - 22.0, 0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pop, "modulate:a", 0.0, 0.25).set_delay(0.48)
	tween.chain().tween_callback(pop.queue_free)

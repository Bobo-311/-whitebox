extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerProgress V7｜玩家永久資料管理器
# Godot 4.5.1
# Autoload：PlayerProgress
# STEP 10.7.7-C
# ============================================================
# 主要職責：
# 1. 建立及保護初始玩家資料。
# 2. 保存及還原金幣、背包、道具解鎖。
# 3. 保存及還原五格快捷欄與選取位置。
# 4. 保存及還原已取得貼紙。
# 5. 保存及還原四格貼紙裝備。
# 6. 支援商店及劇情取得的貼紙。
# 7. 驗證貼紙所有權及禁止重複裝備。
# 8. 保護已永久取得的貼紙。
# 9. 相容舊版存檔。
# 10. V7：正式結束玩家存檔工作階段。
#
# 不直接讀寫 JSON。
# 不修改商店交易規則。
# 不保存暫時性道具增益。
# ============================================================

# 1. 對外訊號
signal gold_restored(slot_id: int, amount: int)
signal inventory_restored(slot_id: int)
signal quick_slots_restored(slot_id: int)
signal owned_stickers_restored(slot_id: int)
signal equipped_stickers_restored(slot_id: int)
signal progress_restore_failed(slot_id: int, reason: String)

# 2. 基本規格
const QUICK_SLOT_COUNT: int = 5
const STICKER_SLOT_COUNT: int = 4
const MAX_SAFE_INTEGER: int = 9007199254740991

# 3. 存檔欄位名稱
const STATS_FIELD: String = "stats"
const INVENTORY_FIELD: String = "inventory"
const EQUIPMENT_FIELD: String = "equipment"
const SKILLS_FIELD: String = "unlocked_skills"
const GOLD_FIELD: String = "total_gold"
const ITEMS_FIELD: String = "items"
const OWNED_STICKERS_FIELD: String = "owned_stickers"
const QUICK_SLOTS_FIELD: String = "quick_slots"
const QUICK_INDEX_FIELD: String = "current_slot_index"
const EQUIPPED_STICKERS_FIELD: String = "equipped_stickers"

# 4. 藍色顏料劇情相容設定
const HP_PAINT_ID: String = "hp_paint"
const HP_PAINT_TIMELINE: String = "A006B"

# 5. 除錯設定
@export_group("除錯設定")
@export var debug_log: bool = true

# 6. 初始玩家資料
var _initial_player_data: Dictionary = {}
var _initialized: bool = false

# 7. 正式工作階段
var _loaded_slot_id: int = 0
var _gold_data_valid: bool = true
var _inventory_data_valid: bool = true
var _quick_slot_data_valid: bool = true
var _owned_stickers_data_valid: bool = true
var _equipped_stickers_data_valid: bool = true

# ============================================================
# 8. 初始化
# 必須位於 DataManager、SaveManager、StoryProgress 之後。
# ============================================================
func _ready() -> void:
	if SaveManager.current_slot_id != 0:
		push_error("【PlayerProgress】初始化時已有存檔工作階段")
		return
	var initial_data: Dictionary = capture_runtime_data()
	if initial_data.is_empty():
		push_error("【PlayerProgress】初始玩家資料建立失敗")
		return
	_initial_player_data = initial_data.duplicate(true)
	_initialized = true

	if not SaveManager.slot_created.is_connected(_on_slot_created):
		SaveManager.slot_created.connect(_on_slot_created)
	if not SaveManager.slot_loaded.is_connected(_on_slot_loaded):
		SaveManager.slot_loaded.connect(_on_slot_loaded)
	if not SaveManager.session_closed.is_connected(_on_session_closed):
		SaveManager.session_closed.connect(_on_session_closed)

	# 不監聽 slot_saved 進行還原，避免正常保存時重設玩家。
	_log("V7 玩家永久資料管理器初始化完成")
	_log("初始金幣：" + str(_initial_player_data[STATS_FIELD][GOLD_FIELD]))
	_log("初始道具種類：" + str(_initial_player_data[INVENTORY_FIELD][ITEMS_FIELD].size()))
	_log("快捷欄數量：" + str(QUICK_SLOT_COUNT))
	_log("貼紙裝備欄數量：" + str(STICKER_SLOT_COUNT))
	_log("初始已取得貼紙數量：" + str(_initial_player_data[INVENTORY_FIELD][OWNED_STICKERS_FIELD].size()))

# 9. 查詢初始化狀態
func is_initialized() -> bool:
	return _initialized

# 10. 取得初始玩家資料深層副本
func get_initial_player_data() -> Dictionary:
	if not _initialized:
		return {}
	return _initial_player_data.duplicate(true)

# 11. 取得目前正式工作階段
func get_loaded_slot_id() -> int:
	return _loaded_slot_id

# ============================================================
# 12. 重設運行時玩家資料
# 使用啟動遊戲時建立的初始快照。
# ============================================================
func _reset_runtime_player_data() -> void:
	if not _initialized:
		return
	var initial_stats: Dictionary = _initial_player_data[STATS_FIELD]
	var initial_inventory: Dictionary = _initial_player_data[INVENTORY_FIELD]
	var initial_equipment: Dictionary = _initial_player_data[EQUIPMENT_FIELD]

	DataManager.total_gold = int(initial_stats[GOLD_FIELD])
	var initial_items: Dictionary = initial_inventory[ITEMS_FIELD]
	DataManager.inventory_items = initial_items.duplicate(true)
	DataManager.quick_slots.assign(initial_equipment[QUICK_SLOTS_FIELD])
	DataManager.current_slot_index = int(initial_equipment[QUICK_INDEX_FIELD])
	DataManager.combat_item_seconds.clear()
	DataManager.owned_stickers.assign(initial_inventory[OWNED_STICKERS_FIELD])
	DataManager.equipped_stickers.assign(initial_equipment[EQUIPPED_STICKERS_FIELD])

# 13. 建立全新遊戲
func _on_slot_created(slot_id: int) -> void:
	_loaded_slot_id = 0
	_gold_data_valid = true
	_inventory_data_valid = true
	_quick_slot_data_valid = true
	_owned_stickers_data_valid = true
	_equipped_stickers_data_valid = true
	_reset_runtime_player_data()
	DataManager.quick_slot_updated.emit()
	DataManager.equipment_changed.emit()
	_log("Slot %02d 新夢境，金幣、背包、快捷欄及貼紙已重設" % slot_id)

# ============================================================
# 14. 正式讀檔還原
# 先驗證所有永久資料，再統一套用至 DataManager。
# ============================================================
func _on_slot_loaded(slot_id: int) -> void:
	_loaded_slot_id = 0
	_gold_data_valid = true
	_inventory_data_valid = true
	_quick_slot_data_valid = true
	_owned_stickers_data_valid = true
	_equipped_stickers_data_valid = true
	_reset_runtime_player_data()
	var save_data: Dictionary = SaveManager.get_current_data()

	# A. 主要資料區塊。
	if typeof(save_data.get("player")) != TYPE_DICTIONARY:
		_restore_fail(slot_id, "player 資料區塊格式異常")
		return
	var player_data: Dictionary = save_data["player"]
	for field in [STATS_FIELD, INVENTORY_FIELD, EQUIPMENT_FIELD]:
		if typeof(player_data.get(field)) != TYPE_DICTIONARY:
			_restore_fail(slot_id, field + " 資料區塊格式異常")
			return
	var stats: Dictionary = player_data[STATS_FIELD]
	var inventory: Dictionary = player_data[INVENTORY_FIELD]
	var equipment: Dictionary = player_data[EQUIPMENT_FIELD]

	# B. 金幣。
	var saved_gold: Variant = stats.get(
		GOLD_FIELD, _initial_player_data[STATS_FIELD][GOLD_FIELD]
	)
	if not _is_non_negative_integer(saved_gold):
		_restore_fail(slot_id, "存檔金幣不是有效的非負整數")
		return
	if not stats.has(GOLD_FIELD):
		_log("Slot %02d 為舊版玩家資料，使用初始金幣" % slot_id)

	# C. 背包。
	var saved_items: Dictionary = {}
	if inventory.has(ITEMS_FIELD):
		if typeof(inventory[ITEMS_FIELD]) != TYPE_DICTIONARY:
			_restore_fail(slot_id, "存檔背包不是 Dictionary")
			return
		saved_items = inventory[ITEMS_FIELD]
		var inventory_error: String = _validate_inventory_items(saved_items)
		if not inventory_error.is_empty():
			_restore_fail(slot_id, inventory_error)
			return
	else:
		_log("Slot %02d 為舊版背包資料，使用初始背包" % slot_id)

	# D. 正式顏料解鎖資格。
	var paint_story_completed: bool = _has_saved_hp_paint_story(save_data)

	# E. 建立背包還原資料。
	var restored_items: Dictionary = build_restored_inventory(
		saved_items, paint_story_completed
	)
	if restored_items.is_empty():
		_restore_fail(slot_id, "無法建立合法的背包還原資料")
		return

	# F. 建立快捷欄還原資料。
	var restored_quick_slots: Dictionary = build_restored_quick_slots(
		equipment, restored_items
	)
	if restored_quick_slots.is_empty():
		_restore_fail(slot_id, "無法建立合法的快捷欄還原資料")
		return
	if not equipment.has(QUICK_SLOTS_FIELD):
		_log("Slot %02d 為舊版快捷欄資料，使用預設配置" % slot_id)

	# G. 建立貼紙收藏還原資料。
	var restored_owned: Dictionary = build_restored_owned_stickers(inventory)
	if restored_owned.is_empty():
		_restore_fail(slot_id, "無法建立合法的已取得貼紙資料")
		return
	if not inventory.has(OWNED_STICKERS_FIELD):
		_log("Slot %02d 為舊版貼紙資料，使用初始收藏" % slot_id)

	# G-2. 建立四格貼紙裝備。
	var restored_equipped: Dictionary = build_restored_equipped_stickers(
		equipment, restored_owned[OWNED_STICKERS_FIELD]
	)
	if restored_equipped.is_empty():
		_restore_fail(slot_id, "無法建立合法的貼紙裝備資料")
		return
	if not equipment.has(EQUIPPED_STICKERS_FIELD):
		_log("Slot %02d 為舊版貼紙裝備資料，使用初始配置" % slot_id)

	# H. 所有資料通過驗證，統一還原。
	DataManager.total_gold = int(saved_gold)
	DataManager.inventory_items = restored_items.duplicate(true)
	DataManager.quick_slots.assign(restored_quick_slots[QUICK_SLOTS_FIELD])
	DataManager.current_slot_index = int(restored_quick_slots[QUICK_INDEX_FIELD])
	DataManager.owned_stickers.assign(restored_owned[OWNED_STICKERS_FIELD])
	DataManager.equipped_stickers.assign(restored_equipped[EQUIPPED_STICKERS_FIELD])

	# I. 建立正式工作階段並通知相關 UI。
	_loaded_slot_id = slot_id
	DataManager.quick_slot_updated.emit()
	DataManager.equipment_changed.emit()
	gold_restored.emit(slot_id, DataManager.total_gold)
	inventory_restored.emit(slot_id)
	quick_slots_restored.emit(slot_id)
	owned_stickers_restored.emit(slot_id)
	equipped_stickers_restored.emit(slot_id)

	# J. 還原紀錄。
	_log_gold_restored(slot_id)
	_log("Slot %02d 背包還原成功" % slot_id)
	_log("目前道具種類：" + str(DataManager.inventory_items.size()))
	var paint: Dictionary = DataManager.inventory_items.get(HP_PAINT_ID, {})
	_log("藍色顏料解鎖：" + str(paint.get("unlocked", false)))
	_log("藍色顏料隨身數量：" + str(paint.get("current_carry", 0)))
	_log("Slot %02d 快捷欄還原成功" % slot_id)
	_log("目前快捷欄配置：" + str(DataManager.quick_slots))
	_log("目前選取編號：" + str(DataManager.current_slot_index))
	_log("目前選取欄位：第 %d 格" % (DataManager.current_slot_index + 1))
	_log("Slot %02d 已取得貼紙還原成功" % slot_id)
	_log("目前已取得貼紙：" + str(DataManager.owned_stickers))
	_log("目前已取得貼紙數量：" + str(DataManager.owned_stickers.size()))
	_log("Slot %02d 貼紙裝備還原成功" % slot_id)
	_log("目前貼紙裝備配置：" + str(DataManager.equipped_stickers))

# 15. 查詢正式保存的顏料劇情資格
func _has_saved_hp_paint_story(save_data: Dictionary) -> bool:
	if typeof(save_data.get("world")) != TYPE_DICTIONARY:
		return false
	var world: Dictionary = save_data["world"]
	var completed: Variant = world.get("completed_cutscenes", [])
	if typeof(completed) != TYPE_ARRAY:
		return false
	return completed.has(HP_PAINT_TIMELINE)

# ============================================================
# 16. 建立合法背包還原資料
# 不修改運行時及磁碟資料。
# ============================================================
func build_restored_inventory(
	saved_items: Dictionary,
	paint_story_completed: bool
) -> Dictionary:
	if not _initialized:
		return {}
	if not _validate_inventory_items(saved_items).is_empty():
		return {}
	var initial_items: Dictionary = _initial_player_data[INVENTORY_FIELD][ITEMS_FIELD]
	var result: Dictionary = initial_items.duplicate(true)

	# 使用正式保存資料覆蓋初始道具。
	for raw_id in saved_items:
		var item_id: String = String(raw_id)
		var saved_stock: Dictionary = saved_items[item_id]
		var base_stock: Dictionary = result.get(item_id, {})
		var stock: Dictionary = base_stock.duplicate(true)
		stock.merge(saved_stock.duplicate(true), true)
		stock["current_carry"] = int(stock["current_carry"])
		stock["reserve_amount"] = int(stock["reserve_amount"])
		result[item_id] = stock

	# 相容 A006B 永久解鎖資格。
	if result.has(HP_PAINT_ID):
		var paint: Dictionary = result[HP_PAINT_ID]
		if paint_story_completed:
			if not bool(paint.get("unlocked", false)):
				paint["unlocked"] = true
				paint["current_carry"] = int(DataManager.ITEM_DB[HP_PAINT_ID]["max_carry"])
		result[HP_PAINT_ID] = paint
	if not _validate_inventory_items(result).is_empty():
		return {}
	return result

# ============================================================
# 17. 建立合法快捷欄還原資料
# 保留原始欄位位置及零數量道具。
# ============================================================
func build_restored_quick_slots(
	saved_equipment: Dictionary,
	items: Dictionary
) -> Dictionary:
	if not _initialized:
		return {}
	if not _validate_inventory_items(items).is_empty():
		return {}
	var has_slots: bool = saved_equipment.has(QUICK_SLOTS_FIELD)
	var has_index: bool = saved_equipment.has(QUICK_INDEX_FIELD)

	# 拒絕不完整配置。
	if has_slots != has_index:
		return {}

	# 正式保存的配置。
	if has_slots and has_index:
		var raw_slots: Variant = saved_equipment[QUICK_SLOTS_FIELD]
		var raw_index: Variant = saved_equipment[QUICK_INDEX_FIELD]
		var validation_error: String = get_quick_slot_validation_error(
			raw_slots, raw_index, items
		)
		if not validation_error.is_empty():
			return {}
		var restored_slots: Array[String] = []
		restored_slots.assign(raw_slots)
		return {
			QUICK_SLOTS_FIELD: restored_slots,
			QUICK_INDEX_FIELD: int(raw_index)
		}

	# 舊版存檔使用初始配置。
	var initial_equipment: Dictionary = _initial_player_data[EQUIPMENT_FIELD]
	var default_slots: Array[String] = []
	default_slots.assign(initial_equipment[QUICK_SLOTS_FIELD])
	var default_index: int = int(initial_equipment[QUICK_INDEX_FIELD])
	var paint: Dictionary = items.get(HP_PAINT_ID, {})
	if bool(paint.get("unlocked", false)):
		if not default_slots.has(HP_PAINT_ID):
			var empty_index: int = default_slots.find("")
			if empty_index >= 0:
				default_slots[empty_index] = HP_PAINT_ID
				default_index = empty_index
	var default_error: String = get_quick_slot_validation_error(
		default_slots, default_index, items
	)
	if not default_error.is_empty():
		return {}
	return {
		QUICK_SLOTS_FIELD: default_slots,
		QUICK_INDEX_FIELD: default_index
	}

# ============================================================
# 18. 建立已取得貼紙還原資料
# 空陣列合法；空 Dictionary 代表建立失敗。
# ============================================================
func build_restored_owned_stickers(saved_inventory: Dictionary) -> Dictionary:
	if not _initialized:
		return {}
	var initial_inventory: Dictionary = _initial_player_data[INVENTORY_FIELD]
	var raw_owned: Variant = saved_inventory.get(
		OWNED_STICKERS_FIELD, initial_inventory[OWNED_STICKERS_FIELD]
	)
	var validation_error: String = _validate_owned_stickers(raw_owned)
	if not validation_error.is_empty():
		push_warning("【PlayerProgress】貼紙還原資料異常：" + validation_error)
		return {}
	var restored_owned: Array[String] = []
	restored_owned.assign(raw_owned)
	return {
		OWNED_STICKERS_FIELD: restored_owned
	}

# 19. 保留舊版顏料快捷欄相容接口
func _restore_default_hp_paint_slot() -> void:
	var paint: Dictionary = DataManager.inventory_items.get(HP_PAINT_ID, {})
	if not bool(paint.get("unlocked", false)):
		return
	if DataManager.quick_slots.has(HP_PAINT_ID):
		return
	var empty_index: int = DataManager.quick_slots.find("")
	if empty_index < 0:
		return
	DataManager.quick_slots[empty_index] = HP_PAINT_ID
	DataManager.current_slot_index = empty_index

# ============================================================
# 20. 驗證永久金幣保存資格
# ============================================================
func can_save_gold() -> bool:
	if not _initialized:
		return false
	if not _gold_data_valid:
		push_warning("【PlayerProgress】金幣資料異常，禁止保存")
		return false
	if _loaded_slot_id <= 0:
		return false
	if SaveManager.current_slot_id != _loaded_slot_id:
		push_warning("【PlayerProgress】玩家資料工作階段不一致")
		return false
	if SaveManager.get_slot_state(_loaded_slot_id) != SaveManager.SlotState.READY:
		return false
	return true

# 21. 驗證背包保存資格
func can_save_inventory() -> bool:
	if not can_save_gold():
		return false
	if not _inventory_data_valid:
		push_warning("【PlayerProgress】背包資料異常，禁止保存")
		return false
	return true

# 22. 驗證快捷欄保存資格
func can_save_quick_slots() -> bool:
	if not can_save_inventory():
		return false
	if not _quick_slot_data_valid:
		push_warning("【PlayerProgress】快捷欄資料異常，禁止保存")
		return false
	return true

# 23. 驗證貼紙收藏保存資格
func can_save_owned_stickers() -> bool:
	if not can_save_quick_slots():
		return false
	if not _owned_stickers_data_valid:
		push_warning("【PlayerProgress】貼紙資料異常，禁止保存")
		return false
	return true

# 24. 驗證候選資料所屬工作階段
func _validate_candidate_slot(candidate: Dictionary) -> bool:
	var candidate_slot: Variant = candidate.get("slot_id")
	if not _is_non_negative_integer(candidate_slot):
		push_warning("【PlayerProgress】候選存檔編號異常")
		return false
	if int(candidate_slot) != _loaded_slot_id:
		push_warning("【PlayerProgress】禁止跨欄位保存玩家資料")
		return false
	return true

# ============================================================
# 25. 加入永久金幣候選資料
# ============================================================
func append_gold_to_candidate(candidate: Dictionary) -> bool:
	if not can_save_gold():
		return false
	if not _validate_candidate_slot(candidate):
		return false
	if not _is_non_negative_integer(DataManager.total_gold):
		push_warning("【PlayerProgress】運行時金幣數值異常")
		return false
	if typeof(candidate.get("player")) != TYPE_DICTIONARY:
		return false
	var player_data: Dictionary = candidate["player"]
	if typeof(player_data.get(STATS_FIELD)) != TYPE_DICTIONARY:
		return false
	var stats: Dictionary = player_data[STATS_FIELD]
	if stats.has(GOLD_FIELD):
		if not _is_non_negative_integer(stats[GOLD_FIELD]):
			push_warning("【PlayerProgress】候選資料存在異常金幣")
			return false
	stats[GOLD_FIELD] = DataManager.total_gold
	player_data[STATS_FIELD] = stats
	candidate["player"] = player_data
	_log("Slot %02d 金幣資料已準備：%d，等待正式寫入" % [
		_loaded_slot_id, DataManager.total_gold
	])
	return true

# ============================================================
# 26. 加入永久背包候選資料
# 只更新 inventory.items。
# ============================================================
func append_inventory_to_candidate(candidate: Dictionary) -> bool:
	if not can_save_inventory():
		return false
	if not _validate_candidate_slot(candidate):
		return false
	if typeof(candidate.get("player")) != TYPE_DICTIONARY:
		return false
	var player_data: Dictionary = candidate["player"]
	if typeof(player_data.get(INVENTORY_FIELD)) != TYPE_DICTIONARY:
		return false
	var inventory: Dictionary = player_data[INVENTORY_FIELD]

	# 保護舊存檔。
	if inventory.has(ITEMS_FIELD):
		if typeof(inventory[ITEMS_FIELD]) != TYPE_DICTIONARY:
			return false
		var old_items: Dictionary = inventory[ITEMS_FIELD]
		var old_error: String = _validate_inventory_items(old_items)
		if not old_error.is_empty():
			push_warning("【PlayerProgress】既有背包資料異常：" + old_error)
			return false

	var current_items: Dictionary = DataManager.inventory_items.duplicate(true)
	var validation_error: String = _validate_inventory_items(current_items)
	if not validation_error.is_empty():
		push_warning("【PlayerProgress】運行時背包資料異常：" + validation_error)
		return false

	# 保護永久顏料解鎖資格。
	if _has_saved_hp_paint_story(candidate):
		var paint: Dictionary = current_items.get(HP_PAINT_ID, {})
		if not bool(paint.get("unlocked", false)):
			push_warning("【PlayerProgress】A006B 顏料解鎖狀態不一致")
			return false

	inventory[ITEMS_FIELD] = current_items
	player_data[INVENTORY_FIELD] = inventory
	candidate["player"] = player_data
	_log("Slot %02d 背包資料已準備，道具種類：%d" % [
		_loaded_slot_id, current_items.size()
	])
	return true

# ============================================================
# 27. 加入永久快捷欄候選資料
# 必須在加入背包資料後執行。
# ============================================================
func append_quick_slots_to_candidate(candidate: Dictionary) -> bool:
	if not can_save_quick_slots():
		return false
	if not _validate_candidate_slot(candidate):
		return false
	if typeof(candidate.get("player")) != TYPE_DICTIONARY:
		return false
	var player_data: Dictionary = candidate["player"]
	if typeof(player_data.get(INVENTORY_FIELD)) != TYPE_DICTIONARY:
		return false
	if typeof(player_data.get(EQUIPMENT_FIELD)) != TYPE_DICTIONARY:
		return false
	var inventory: Dictionary = player_data[INVENTORY_FIELD]
	var equipment: Dictionary = player_data[EQUIPMENT_FIELD]
	if typeof(inventory.get(ITEMS_FIELD)) != TYPE_DICTIONARY:
		return false
	var items: Dictionary = inventory[ITEMS_FIELD]
	if not _validate_inventory_items(items).is_empty():
		return false

	# 以舊存檔自己的背包驗證舊快捷欄。
	var previous_save: Dictionary = SaveManager.get_current_data()
	var previous_player: Dictionary = previous_save.get("player", {})
	var previous_inventory: Dictionary = previous_player.get(INVENTORY_FIELD, {})
	var previous_items: Variant = previous_inventory.get(ITEMS_FIELD, {})
	if typeof(previous_items) != TYPE_DICTIONARY:
		return false
	var previous_restored_items: Dictionary = build_restored_inventory(
		previous_items, _has_saved_hp_paint_story(previous_save)
	)
	if previous_restored_items.is_empty():
		return false
	var old_configuration: Dictionary = build_restored_quick_slots(
		equipment, previous_restored_items
	)
	if old_configuration.is_empty():
		push_warning("【PlayerProgress】既有快捷欄資料異常")
		return false

	# 收集目前快捷欄配置。
	var current_slots: Array[String] = DataManager.quick_slots.duplicate()
	var current_index: int = DataManager.current_slot_index
	var validation_error: String = get_quick_slot_validation_error(
		current_slots, current_index, items
	)
	if not validation_error.is_empty():
		push_warning("【PlayerProgress】運行時快捷欄資料異常：" + validation_error)
		return false
	equipment[QUICK_SLOTS_FIELD] = current_slots.duplicate()
	equipment[QUICK_INDEX_FIELD] = current_index
	player_data[EQUIPMENT_FIELD] = equipment
	candidate["player"] = player_data
	_log("Slot %02d 快捷欄資料已準備，等待正式寫入" % _loaded_slot_id)
	_log("快捷欄配置：" + str(current_slots))
	_log("選取編號：" + str(current_index))
	return true

# ============================================================
# 28. 加入永久貼紙收藏
# 商店與劇情取得來源共用 owned_stickers。
# ============================================================
func append_owned_stickers_to_candidate(candidate: Dictionary) -> bool:
	if not can_save_owned_stickers():
		return false
	if not _validate_candidate_slot(candidate):
		return false
	if typeof(candidate.get("player")) != TYPE_DICTIONARY:
		return false
	var player_data: Dictionary = candidate["player"]
	if typeof(player_data.get(INVENTORY_FIELD)) != TYPE_DICTIONARY:
		return false
	var inventory: Dictionary = player_data[INVENTORY_FIELD]
	var current_owned: Array[String] = DataManager.owned_stickers.duplicate()
	var current_error: String = _validate_owned_stickers(current_owned)
	if not current_error.is_empty():
		push_warning("【PlayerProgress】運行時貼紙資料異常：" + current_error)
		return false

	# 禁止已永久取得的貼紙意外遺失。
	if inventory.has(OWNED_STICKERS_FIELD):
		var previous_owned: Variant = inventory[OWNED_STICKERS_FIELD]
		var previous_error: String = _validate_owned_stickers(previous_owned)
		if not previous_error.is_empty():
			push_warning("【PlayerProgress】既有貼紙資料異常：" + previous_error)
			return false
		for sticker_id in previous_owned:
			if not current_owned.has(sticker_id):
				push_warning("【PlayerProgress】已永久保存的貼紙意外遺失：" + String(sticker_id))
				return false
	inventory[OWNED_STICKERS_FIELD] = current_owned.duplicate()
	player_data[INVENTORY_FIELD] = inventory
	candidate["player"] = player_data
	_log("Slot %02d 已取得貼紙資料已準備，等待正式寫入" % _loaded_slot_id)
	_log("貼紙收藏：" + str(current_owned))
	_log("貼紙收藏數量：" + str(current_owned.size()))
	return true

# ============================================================
# 29. 收集完整玩家資料快照
# ============================================================
func capture_runtime_data() -> Dictionary:
	var player_data: Dictionary = {
		STATS_FIELD: {
			GOLD_FIELD: DataManager.total_gold
		},
		INVENTORY_FIELD: {
			ITEMS_FIELD: DataManager.inventory_items.duplicate(true),
			OWNED_STICKERS_FIELD: DataManager.owned_stickers.duplicate()
		},
		EQUIPMENT_FIELD: {
			QUICK_SLOTS_FIELD: DataManager.quick_slots.duplicate(),
			QUICK_INDEX_FIELD: DataManager.current_slot_index,
			EQUIPPED_STICKERS_FIELD: DataManager.equipped_stickers.duplicate()
		},
		SKILLS_FIELD: []
	}
	var validation_error: String = get_validation_error(player_data)
	if not validation_error.is_empty():
		push_warning("【PlayerProgress】玩家資料收集失敗：" + validation_error)
		return {}
	return player_data

# 30. 驗證安全非負整數
func _is_non_negative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= 0 and value <= MAX_SAFE_INTEGER
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	if not is_finite(number):
		return false
	if number < 0.0:
		return false
	if number > float(MAX_SAFE_INTEGER):
		return false
	return number == floorf(number)

# ============================================================
# 31. 公開驗證接口
# 保留既有獨立測試使用的函式。
# ============================================================
func validate_player_data(data: Dictionary) -> bool:
	return get_validation_error(data).is_empty()

func validate_inventory_items(items: Dictionary) -> bool:
	return _validate_inventory_items(items).is_empty()

func validate_quick_slot_configuration(
	raw_slots: Variant,
	raw_index: Variant,
	items: Dictionary
) -> bool:
	return get_quick_slot_validation_error(raw_slots, raw_index, items).is_empty()

func validate_owned_stickers(raw_data: Variant) -> bool:
	return _validate_owned_stickers(raw_data).is_empty()

func get_owned_stickers_validation_error(raw_data: Variant) -> String:
	return _validate_owned_stickers(raw_data)

# 32. 驗證完整快捷欄配置
func get_quick_slot_validation_error(
	raw_slots: Variant,
	raw_index: Variant,
	items: Dictionary
) -> String:
	var quick_error: String = _validate_quick_slots(raw_slots, items)
	if not quick_error.is_empty():
		return quick_error
	if not _is_non_negative_integer(raw_index):
		return "快捷欄選取編號格式錯誤"
	if int(raw_index) >= QUICK_SLOT_COUNT:
		return "快捷欄選取編號超出範圍"
	return ""

# ============================================================
# 33. 驗證完整玩家資料
# 舊存檔缺少新版欄位時，使用各自還原接口。
# ============================================================
func get_validation_error(data: Dictionary) -> String:
	for field in [STATS_FIELD, INVENTORY_FIELD, EQUIPMENT_FIELD]:
		if not data.has(field):
			return "缺少資料區塊：" + field
		if typeof(data[field]) != TYPE_DICTIONARY:
			return "資料區塊格式錯誤：" + field

	var stats: Dictionary = data[STATS_FIELD]
	var inventory: Dictionary = data[INVENTORY_FIELD]
	var equipment: Dictionary = data[EQUIPMENT_FIELD]

	if not stats.has(GOLD_FIELD):
		return "缺少金幣資料"
	if not _is_non_negative_integer(stats[GOLD_FIELD]):
		return "金幣必須為有效的非負整數"

	if typeof(inventory.get(ITEMS_FIELD)) != TYPE_DICTIONARY:
		return "背包資料格式錯誤"
	var items: Dictionary = inventory[ITEMS_FIELD]
	var inventory_error: String = _validate_inventory_items(items)
	if not inventory_error.is_empty():
		return inventory_error

	var owned_stickers: Variant = inventory.get(OWNED_STICKERS_FIELD)
	var owned_error: String = _validate_owned_stickers(owned_stickers)
	if not owned_error.is_empty():
		return owned_error

	var quick_error: String = get_quick_slot_validation_error(
		equipment.get(QUICK_SLOTS_FIELD),
		equipment.get(QUICK_INDEX_FIELD),
		items
	)
	if not quick_error.is_empty():
		return quick_error

	var equipped_stickers: Variant = equipment.get(EQUIPPED_STICKERS_FIELD)
	var equipped_error: String = _validate_equipped_stickers(
		equipped_stickers, owned_stickers
	)
	if not equipped_error.is_empty():
		return equipped_error

	# Schema 1 預留欄位，不實作技能解鎖功能。
	var skills: Variant = data.get(SKILLS_FIELD)
	if typeof(skills) != TYPE_ARRAY:
		return "技能資料格式錯誤"
	var seen_skills: Dictionary = {}
	for skill_id in skills:
		if typeof(skill_id) != TYPE_STRING:
			return "技能 ID 格式錯誤"
		if String(skill_id).strip_edges().is_empty():
			return "技能 ID 不可為空"
		if seen_skills.has(skill_id):
			return "存在重複技能 ID"
		seen_skills[skill_id] = true
	return ""

# ============================================================
# 34. 驗證背包道具
# ============================================================
func _validate_inventory_items(items: Dictionary) -> String:
	for raw_id in items:
		if typeof(raw_id) != TYPE_STRING:
			return "背包存在無效的道具 ID"
		var item_id: String = String(raw_id)
		if not DataManager.ITEM_DB.has(item_id):
			return "未登記的道具：" + item_id
		var raw_stock: Variant = items[item_id]
		if typeof(raw_stock) != TYPE_DICTIONARY:
			return "道具資料格式錯誤：" + item_id
		var stock: Dictionary = raw_stock
		if not stock.has("current_carry"):
			return "缺少隨身數量：" + item_id
		if not stock.has("reserve_amount"):
			return "缺少庫存數量：" + item_id
		if not _is_non_negative_integer(stock["current_carry"]):
			return "隨身數量無效：" + item_id
		if not _is_non_negative_integer(stock["reserve_amount"]):
			return "庫存數量無效：" + item_id
		var max_carry: int = int(DataManager.ITEM_DB[item_id]["max_carry"])
		if int(stock["current_carry"]) > max_carry:
			return "隨身數量超出上限：" + item_id
		if stock.has("unlocked"):
			if typeof(stock["unlocked"]) != TYPE_BOOL:
				return "道具解鎖狀態無效：" + item_id
	return ""

# 35. 驗證已取得貼紙
# 使用 STICKER_DB，不寫死可取得的貼紙種類。
func _validate_owned_stickers(raw_data: Variant) -> String:
	if typeof(raw_data) != TYPE_ARRAY:
		return "已取得貼紙資料不是陣列"
	var seen: Dictionary = {}
	for raw_id in raw_data:
		if typeof(raw_id) != TYPE_STRING:
			return "貼紙 ID 格式錯誤"
		var sticker_id: String = String(raw_id)
		if sticker_id.strip_edges().is_empty():
			return "貼紙 ID 不可為空"
		if not DataManager.STICKER_DB.has(sticker_id):
			return "未登記的貼紙：" + sticker_id
		if seen.has(sticker_id):
			return "存在重複的已取得貼紙：" + sticker_id
		seen[sticker_id] = true
	return ""

# 36. 驗證快捷欄
# 道具用完仍然允許保留在原本欄位。
func _validate_quick_slots(raw_data: Variant, items: Dictionary) -> String:
	if typeof(raw_data) != TYPE_ARRAY:
		return "快捷欄資料不是陣列"
	if raw_data.size() != QUICK_SLOT_COUNT:
		return "快捷欄數量不正確"
	var seen: Dictionary = {}
	for raw_id in raw_data:
		if typeof(raw_id) != TYPE_STRING:
			return "快捷欄道具 ID 格式錯誤"
		var item_id: String = String(raw_id)
		if item_id.is_empty():
			continue
		if not DataManager.ITEM_DB.has(item_id):
			return "快捷欄存在未登記道具：" + item_id
		if not items.has(item_id):
			return "快捷欄道具不存在於背包：" + item_id
		if seen.has(item_id):
			return "快捷欄存在重複道具：" + item_id
		seen[item_id] = true
	return ""

# 37. 驗證四格貼紙裝備
func _validate_equipped_stickers(
	raw_data: Variant,
	owned_stickers: Array
) -> String:
	if typeof(raw_data) != TYPE_ARRAY:
		return "已裝備貼紙資料不是陣列"
	if raw_data.size() != STICKER_SLOT_COUNT:
		return "貼紙裝備欄數量不正確"
	var seen: Dictionary = {}
	for raw_id in raw_data:
		if typeof(raw_id) != TYPE_STRING:
			return "裝備貼紙 ID 格式錯誤"
		var sticker_id: String = String(raw_id)
		if sticker_id.is_empty():
			continue
		if not DataManager.STICKER_DB.has(sticker_id):
			return "裝備了未登記的貼紙：" + sticker_id
		if not owned_stickers.has(sticker_id):
			return "裝備了尚未取得的貼紙：" + sticker_id
		if seen.has(sticker_id):
			return "重複裝備相同貼紙：" + sticker_id
		seen[sticker_id] = true
	return ""

# 38. 輸出目前玩家資料快照
func print_runtime_snapshot() -> void:
	if not OS.is_debug_build():
		return
	var data: Dictionary = capture_runtime_data()
	if data.is_empty():
		push_warning("【PlayerProgress】無法輸出玩家資料")
		return
	print("")
	print("========== PlayerProgress Snapshot ==========")
	print(JSON.stringify(data, "\t"))
	print("=============================================")

# 39. 金幣還原輸出
func _log_gold_restored(slot_id: int) -> void:
	_log("Slot %02d 金幣還原成功：%d" % [
		slot_id, DataManager.total_gold
	])

# 40. 統一還原失敗處理
func _restore_fail(slot_id: int, reason: String) -> void:
	_loaded_slot_id = 0
	_gold_data_valid = false
	_inventory_data_valid = false
	_quick_slot_data_valid = false
	_owned_stickers_data_valid = false
	_equipped_stickers_data_valid = false
	DataManager.quick_slot_updated.emit()
	DataManager.equipment_changed.emit()
	push_error("【PlayerProgress】Slot %02d 玩家資料還原失敗：%s" % [
		slot_id, reason
	])
	progress_restore_failed.emit(slot_id, reason)

# 41. 統一除錯輸出
func _log(message: String) -> void:
	if debug_log:
		print("【PlayerProgress】" + message)

# ============================================================
# 42. 建立四格貼紙裝備還原資料
# ============================================================
func build_restored_equipped_stickers(
	saved_equipment: Dictionary,
	owned_stickers: Variant
) -> Dictionary:
	if not _initialized:
		return {}
	var initial_equipment: Dictionary = _initial_player_data[EQUIPMENT_FIELD]
	var raw_slots: Variant = saved_equipment.get(
		EQUIPPED_STICKERS_FIELD, initial_equipment[EQUIPPED_STICKERS_FIELD]
	)
	var error: String = get_equipped_stickers_validation_error(
		raw_slots, owned_stickers
	)
	if not error.is_empty():
		return {}
	var result: Array[String] = []
	result.assign(raw_slots)
	return {
		EQUIPPED_STICKERS_FIELD: result
	}

# 43. 貼紙裝備合法性公開接口
func get_equipped_stickers_validation_error(
	raw_slots: Variant,
	owned_stickers: Variant
) -> String:
	var owned_error: String = _validate_owned_stickers(owned_stickers)
	if not owned_error.is_empty():
		return owned_error
	return _validate_equipped_stickers(raw_slots, owned_stickers)

func validate_equipped_stickers(
	raw_slots: Variant,
	owned_stickers: Variant
) -> bool:
	return get_equipped_stickers_validation_error(raw_slots, owned_stickers).is_empty()

# 44. 驗證貼紙裝備保存資格
func can_save_equipped_stickers() -> bool:
	return can_save_owned_stickers() and _equipped_stickers_data_valid

# ============================================================
# 45. 加入四格永久貼紙裝備
# 必須在加入貼紙收藏後執行。
# 不排序、不壓縮、不修改貼紙所有權。
# ============================================================
func append_equipped_stickers_to_candidate(candidate: Dictionary) -> bool:
	if not can_save_equipped_stickers():
		return false
	if not _validate_candidate_slot(candidate):
		return false
	if typeof(candidate.get("player")) != TYPE_DICTIONARY:
		return false
	var player_data: Dictionary = candidate["player"]
	if typeof(player_data.get(INVENTORY_FIELD)) != TYPE_DICTIONARY:
		return false
	if typeof(player_data.get(EQUIPMENT_FIELD)) != TYPE_DICTIONARY:
		return false
	var inventory: Dictionary = player_data[INVENTORY_FIELD]
	var equipment: Dictionary = player_data[EQUIPMENT_FIELD]
	var owned: Variant = inventory.get(OWNED_STICKERS_FIELD)

	# A. 驗證目前四格裝備。
	var current_slots: Array[String] = DataManager.equipped_stickers.duplicate()
	var error: String = get_equipped_stickers_validation_error(current_slots, owned)
	if not error.is_empty():
		push_warning("【PlayerProgress】運行時貼紙裝備資料異常：" + error)
		return false

	# B. 確認候選資料已包含完整的貼紙所有權。
	if not validate_owned_stickers(DataManager.owned_stickers):
		return false
	if owned.size() != DataManager.owned_stickers.size():
		return false
	for sticker_id in DataManager.owned_stickers:
		if not owned.has(sticker_id):
			return false

	# C. 使用舊存檔自己的收藏驗證既有裝備。
	var previous_save: Dictionary = SaveManager.get_current_data()
	if typeof(previous_save.get("player")) != TYPE_DICTIONARY:
		return false
	var previous_player: Dictionary = previous_save["player"]
	if typeof(previous_player.get(INVENTORY_FIELD)) != TYPE_DICTIONARY:
		return false
	if typeof(previous_player.get(EQUIPMENT_FIELD)) != TYPE_DICTIONARY:
		return false
	var previous_owned: Dictionary = build_restored_owned_stickers(
		previous_player[INVENTORY_FIELD]
	)
	if previous_owned.is_empty():
		return false
	var previous_equipped: Dictionary = build_restored_equipped_stickers(
		previous_player[EQUIPMENT_FIELD],
		previous_owned[OWNED_STICKERS_FIELD]
	)
	if previous_equipped.is_empty():
		push_warning("【PlayerProgress】既有貼紙裝備資料異常")
		return false

	# D. 保存目前四格裝備。
	equipment[EQUIPPED_STICKERS_FIELD] = current_slots.duplicate()
	player_data[EQUIPMENT_FIELD] = equipment
	candidate["player"] = player_data
	_log("Slot %02d 貼紙裝備資料已準備，等待正式寫入" % _loaded_slot_id)
	_log("貼紙裝備配置：" + str(current_slots))
	return true

# ============================================================
# 46. V7：正式結束玩家工作階段
#
# 返回主選單時：
# 1. 解除永久資料保存資格。
# 2. 還原所有初始玩家資料。
# 3. 清除暫時性道具效果。
# 4. 發送 UI 更新通知。
#
# 不寫入 JSON，不刪除存檔。
# ============================================================
func _on_session_closed(slot_id: int) -> void:
	_loaded_slot_id = 0
	_gold_data_valid = true
	_inventory_data_valid = true
	_quick_slot_data_valid = true
	_owned_stickers_data_valid = true
	_equipped_stickers_data_valid = true
	_reset_runtime_player_data()
	DataManager.quick_slot_updated.emit()
	DataManager.equipment_changed.emit()
	_log("Slot %02d 玩家工作階段已結束" % slot_id)
	_log("目前金幣：" + str(DataManager.total_gold))
	_log("目前快捷欄：" + str(DataManager.quick_slots))
	_log("目前已取得貼紙：" + str(DataManager.owned_stickers))
	_log("目前貼紙裝備：" + str(DataManager.equipped_stickers))
	_log("暫時性道具增益已清除")

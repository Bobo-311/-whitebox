extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# StoryProgress V3.3｜劇情與任務永久進度管理器
# Godot 4.5.1 / Dialogic 2.0-Alpha-21
# Autoload：StoryProgress
# STEP 10.7.7-C
# ============================================================
# 主要職責：
# 1. 隔離四格存檔的劇情資料。
# 2. 還原永久劇情、任務及事件旗標。
# 3. 保存正式劇情完成紀錄。
# 4. 管理 A006B 藍色顏料永久解鎖。
# 5. 管理永久戰鬥能力解鎖。
# 6. V3.3：結束劇情工作階段。
#
# 不直接操作 JSON 檔案。
# 不負責劇情演出、NPC 控制或玩家永久背包。
# ============================================================

# 1. 對外訊號
signal progress_restored(slot_id: int)
signal cutscene_saved(slot_id: int, timeline_id: String)
signal progress_saved(slot_id: int, category: String)
signal progress_save_failed(slot_id: int, reason: String)

# 2. 存檔欄位
const SAVE_FIELD: String = "completed_cutscenes"
const VARIABLES_FIELD: String = "dialogic_variables"
const COMBAT_FIELD: String = "combat_unlocked"
const FLAGS_FIELD: String = "story_flags"

# 3. Dialogic 永久任務變數
const MERCHANT_VARIABLE: String = "merchant_quest"
const MERCHANT_DEFAULT: int = 0

# 4. AM001 初始劇情
const OPENING_MAP_PATH: String = "res://Maps/AM001.tscn"
const OPENING_DIRECTOR_PATH: String = "CutsceneDirector"
const OPENING_COMMIT_SIGNAL: String = "story_commit:AM001_opening"

# 5. 正式永久進度暗號
const CUTSCENE_COMMIT_PREFIX: String = "story_commit:"
const MERCHANT_COMMIT_SIGNAL: String = "story_commit:merchant_quest"
const COMBAT_COMMIT_SIGNAL: String = "story_commit:combat_unlocked"
const FLAG_COMMIT_PREFIX: String = "story_commit:flag:"

# 6. A006B 初見畫架
const FIRST_EASEL_TIMELINE: String = "A006B"
const FIRST_EASEL_COMMIT_SIGNAL: String = "story_commit:A006B"
const FIRST_EASEL_MAP_PATH: String = "res://Maps/AM002.tscn"
const FIRST_EASEL_MAP_ID: String = "am002"
const FIRST_EASEL_ID: String = "easel_am002_01"
const FIRST_EASEL_ITEM_ID: String = "hp_paint"

# 7. CutsceneDirector 正式劇情登記表
const REGISTERED_CUTSCENES: Dictionary = {
	"A008": "res://Maps/AM002.tscn",
	"A005": "res://Maps/AM002.tscn"
}

# 8. 除錯設定
@export_group("除錯設定")
@export var debug_log: bool = true

# 9. 正式工作階段
var _loaded_slot_id: int = 0
var _is_saving: bool = false
var _progress_valid: bool = true

# ============================================================
# 10. 初始化及訊號綁定
# ============================================================
func _ready() -> void:
	if not SaveManager.slot_created.is_connected(_on_slot_created):
		SaveManager.slot_created.connect(_on_slot_created)
	if not SaveManager.slot_loaded.is_connected(_on_slot_loaded):
		SaveManager.slot_loaded.connect(_on_slot_loaded)
	if not SaveManager.session_closed.is_connected(_on_session_closed):
		SaveManager.session_closed.connect(_on_session_closed)
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)
	_log("V3.3 劇情進度管理器初始化完成")

# ============================================================
# 11. 重設運行時劇情資料
# ============================================================
func _reset_runtime_progress() -> void:
	DataManager.completed_cutscenes.clear()
	DataManager.combat_unlocked = false
	Dialogic.VAR.merchant_quest = MERCHANT_DEFAULT
	_reset_runtime_first_easel_item()

# 12. 重設上一格存檔的藍色顏料
func _reset_runtime_first_easel_item() -> void:
	DataManager.inventory_items[FIRST_EASEL_ITEM_ID] = {
		"current_carry": 0,
		"reserve_amount": 0,
		"unlocked": false
	}
	var selected_paint: bool = false
	var current_index: int = DataManager.current_slot_index
	if current_index >= 0 and current_index < DataManager.quick_slots.size():
		selected_paint = (
			DataManager.quick_slots[current_index] == FIRST_EASEL_ITEM_ID
		)
	for index in range(DataManager.quick_slots.size()):
		if DataManager.quick_slots[index] == FIRST_EASEL_ITEM_ID:
			DataManager.quick_slots[index] = ""

	# 原本正在選取顏料時，選取第一個非空欄位。
	if selected_paint:
		DataManager.current_slot_index = 0
		for index in range(DataManager.quick_slots.size()):
			if DataManager.quick_slots[index] != "":
				DataManager.current_slot_index = index
				break
	DataManager.quick_slot_updated.emit()

# 13. 根據 A006B 永久劇情還原顏料資格
func _restore_first_easel_item(completed_ids: Array) -> void:
	if not completed_ids.has(FIRST_EASEL_TIMELINE):
		_log("藍色顏料尚未解鎖")
		return
	DataManager.unlock_auto_refill_item(FIRST_EASEL_ITEM_ID)
	_log("已還原藍色顏料永久解鎖狀態")

# 14. 建立全新遊戲
func _on_slot_created(slot_id: int) -> void:
	_loaded_slot_id = 0
	_progress_valid = true
	_reset_runtime_progress()
	_log("Slot %02d 新夢境，劇情及顏料資料已重設" % slot_id)

# ============================================================
# 15. 正式讀檔還原
# 所有劇情資料通過驗證後才建立正式工作階段。
# ============================================================
func _on_slot_loaded(slot_id: int) -> void:
	_loaded_slot_id = 0
	_progress_valid = true
	_reset_runtime_progress()
	var save_data: Dictionary = SaveManager.get_current_data()

	if typeof(save_data.get("world")) != TYPE_DICTIONARY:
		_progress_valid = false
		push_error("【StoryProgress】world 資料格式異常")
		return
	var world: Dictionary = save_data["world"]

	# A. 驗證永久完成劇情。
	var completed_data: Variant = _read_completed_cutscenes(save_data)
	if completed_data == null:
		_progress_valid = false

	# B. 驗證永久事件旗標。
	var flags_data: Variant = _read_id_array(world.get(FLAGS_FIELD, []))
	if flags_data == null:
		_progress_valid = false

	# C. 驗證商人任務。
	var merchant_value: Variant = _read_merchant_quest(world)
	if merchant_value == null:
		_progress_valid = false

	# D. 驗證戰鬥解鎖。
	var combat_value: Variant = world.get(COMBAT_FIELD, false)
	if typeof(combat_value) != TYPE_BOOL:
		_progress_valid = false

	# E. 拒絕異常資料。
	if not _progress_valid:
		push_error("【StoryProgress】Slot %02d 劇情資料異常，禁止保存" % slot_id)
		return

	# F. 還原劇情及事件。
	for timeline_id in completed_data:
		DataManager.mark_cutscene_completed(String(timeline_id))
	for flag_id in flags_data:
		DataManager.mark_cutscene_completed(String(flag_id))

	# G. 還原任務、戰鬥及顏料。
	Dialogic.VAR.merchant_quest = int(merchant_value)
	DataManager.combat_unlocked = bool(combat_value)
	_restore_first_easel_item(completed_data)

	# H. 建立正式工作階段。
	_loaded_slot_id = slot_id
	progress_restored.emit(slot_id)
	_log("已還原 Slot %02d 劇情進度" % slot_id)
	_log("永久完成劇情：" + str(completed_data))
	_log("永久事件旗標：" + str(flags_data))
	_log("商人任務進度：" + str(Dialogic.VAR.merchant_quest))
	_log("永久戰鬥解鎖：" + str(DataManager.combat_unlocked))
	_log("藍色顏料永久解鎖：" + str(completed_data.has(FIRST_EASEL_TIMELINE)))

# ============================================================
# 16. 驗證劇情及事件 ID 陣列
# ============================================================
func _read_id_array(raw_data: Variant) -> Variant:
	if typeof(raw_data) != TYPE_ARRAY:
		return null
	var result: Array[String] = []
	for value in raw_data:
		if typeof(value) != TYPE_STRING:
			return null
		var entry_id: String = String(value).strip_edges()
		if entry_id.is_empty():
			return null
		if not result.has(entry_id):
			result.append(entry_id)
	return result

# 17. 讀取永久完成劇情
func _read_completed_cutscenes(save_data: Dictionary) -> Variant:
	if typeof(save_data.get("world")) != TYPE_DICTIONARY:
		return null
	var world: Dictionary = save_data["world"]
	return _read_id_array(world.get(SAVE_FIELD, []))

# 18. 驗證整數資料
func _is_valid_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	if not is_finite(number):
		return false
	if absf(number) > 9007199254740991.0:
		return false
	return number == floorf(number)

# 19. 讀取商人任務永久進度
func _read_merchant_quest(world: Dictionary) -> Variant:
	var variables_data: Variant = world.get(VARIABLES_FIELD, {})
	if typeof(variables_data) != TYPE_DICTIONARY:
		return null
	var value: Variant = variables_data.get(MERCHANT_VARIABLE, MERCHANT_DEFAULT)
	if not _is_valid_integer(value):
		return null
	return int(value)

# ============================================================
# 20. 接收 Dialogic 正式保存暗號
# A006B 仍由 SavePoint 確認完整演出後保存。
# ============================================================
func _on_dialogic_signal(argument: String) -> void:
	match argument:
		OPENING_COMMIT_SIGNAL:
			_commit_opening_cutscene()
			return
		MERCHANT_COMMIT_SIGNAL:
			commit_merchant_quest()
			return
		COMBAT_COMMIT_SIGNAL:
			commit_combat_unlock()
			return
		FIRST_EASEL_COMMIT_SIGNAL:
			return

	if argument.begins_with(FLAG_COMMIT_PREFIX):
		var flag_id: String = argument.trim_prefix(FLAG_COMMIT_PREFIX).strip_edges()
		commit_story_flag(flag_id)
		return

	if argument.begins_with(CUTSCENE_COMMIT_PREFIX):
		var timeline_id: String = argument.trim_prefix(CUTSCENE_COMMIT_PREFIX).strip_edges()
		_commit_registered_cutscene(timeline_id)

# ============================================================
# 21. AM001 初始劇情保存
# ============================================================
func _commit_opening_cutscene() -> void:
	var current_map: Node = get_tree().current_scene
	if not is_instance_valid(current_map):
		return
	if current_map.scene_file_path != OPENING_MAP_PATH:
		push_warning("【StoryProgress】開場完成暗號不屬於 AM001")
		return
	var director: CutsceneDirector = (
		current_map.get_node_or_null(OPENING_DIRECTOR_PATH) as CutsceneDirector
	)
	if not is_instance_valid(director):
		push_error("【StoryProgress】找不到 AM001 CutsceneDirector")
		return
	if not director.is_active:
		push_warning("【StoryProgress】開場劇情未處於播放狀態")
		return
	if not director.trigger_on_map_enter:
		push_warning("【StoryProgress】指定導演不是地圖開場劇情")
		return
	if not director.next_scene_after_cutscene.is_empty():
		push_warning("【StoryProgress】跨地圖劇情暫不允許獨立保存")
		return
	var timeline_id: String = director.target_timeline.strip_edges()
	if timeline_id != "A001":
		push_error("【StoryProgress】AM001 開場劇本 ID 不正確")
		return
	_save_completed_cutscene(timeline_id)

# 22. 尋找目前正在演出的指定導演
func _find_active_director(
	map_root: Node,
	timeline_id: String
) -> CutsceneDirector:
	if not is_instance_valid(map_root):
		return null
	var result: CutsceneDirector = null
	for node in map_root.find_children("*", "", true, false):
		var director: CutsceneDirector = node as CutsceneDirector
		if not is_instance_valid(director):
			continue
		if director.is_queued_for_deletion():
			continue
		if director.target_timeline.strip_edges() != timeline_id:
			continue
		if not director.is_active:
			continue
		if is_instance_valid(result):
			push_error("【StoryProgress】存在多個正在演出的同 ID 導演：" + timeline_id)
			return null
		result = director
	return result

# 23. 驗證永久劇情前置條件
func _has_saved_prerequisite(director: CutsceneDirector) -> bool:
	var required_id: String = director.required_prerequisite.strip_edges()
	if required_id.is_empty():
		return true
	var save_data: Dictionary = SaveManager.get_current_data()
	if typeof(save_data.get("world")) != TYPE_DICTIONARY:
		return false
	var world: Dictionary = save_data["world"]
	var completed_ids: Variant = _read_id_array(world.get(SAVE_FIELD, []))
	var flags: Variant = _read_id_array(world.get(FLAGS_FIELD, []))
	if completed_ids == null or flags == null:
		return false
	return completed_ids.has(required_id) or flags.has(required_id)

# ============================================================
# 24. 正式保存已登記劇情
# ============================================================
func _commit_registered_cutscene(timeline_id: String) -> void:
	if not REGISTERED_CUTSCENES.has(timeline_id):
		push_warning("【StoryProgress】尚未登記永久保存的劇情：" + timeline_id)
		return
	var current_map: Node = get_tree().current_scene
	if not is_instance_valid(current_map):
		return
	var expected_map_path: String = String(REGISTERED_CUTSCENES[timeline_id])
	if current_map.scene_file_path != expected_map_path:
		push_warning("【StoryProgress】劇情保存地圖不相符：" + timeline_id)
		return
	if Dialogic.current_timeline == null:
		push_warning("【StoryProgress】目前沒有播放中的劇本")
		return
	var director: CutsceneDirector = _find_active_director(current_map, timeline_id)
	if not is_instance_valid(director):
		push_warning("【StoryProgress】找不到有效的演出導演：" + timeline_id)
		return
	if not director.next_scene_after_cutscene.is_empty():
		push_warning("【StoryProgress】跨地圖劇情尚未完成存檔整合：" + timeline_id)
		return
	if not _can_save_progress():
		return
	if not _has_saved_prerequisite(director):
		push_warning("【StoryProgress】劇情前置條件尚未永久保存：" + timeline_id)
		return
	_log("已確認正式劇情完成暗號：" + timeline_id)
	_save_completed_cutscene(timeline_id)

# ============================================================
# 25. 正式保存 A006B 初見畫架劇情
# 由 SavePoint 確認劇情完整結束後呼叫。
# ============================================================
func commit_first_easel(source: Node) -> bool:
	if not is_instance_valid(source):
		return _fail("初見畫架來源不存在")
	if source.is_queued_for_deletion():
		return _fail("初見畫架正在卸載")

	var current_map: Node = get_tree().current_scene
	if not is_instance_valid(current_map):
		return _fail("找不到目前地圖")
	if not current_map.is_ancestor_of(source):
		return _fail("畫架不屬於目前地圖")
	if current_map.scene_file_path != FIRST_EASEL_MAP_PATH:
		return _fail("A006B 所屬地圖不正確")
	if not ("map_id" in source and "easel_id" in source):
		return _fail("來源缺少正式畫架身分")
	if String(source.get("map_id")) != FIRST_EASEL_MAP_ID:
		return _fail("A006B 地圖 ID 不正確")
	if String(source.get("easel_id")) != FIRST_EASEL_ID:
		return _fail("A006B 畫架 ID 不正確")

	var marker: Marker2D = CheckpointManager.get_current_spawn_marker(
		FIRST_EASEL_MAP_ID, FIRST_EASEL_ID
	)
	if not is_instance_valid(marker):
		return _fail("初見畫架定位點不存在")
	if not source.has_method("can_commit_first_easel"):
		return _fail("畫架缺少劇情完成驗證接口")
	if not bool(source.call("can_commit_first_easel")):
		return _fail("A006B 尚未完整演出")
	if not _can_save_progress():
		return false
	if not _save_completed_cutscene(FIRST_EASEL_TIMELINE):
		return false

	# 永久劇情保存成功後才正式解鎖道具。
	DataManager.unlock_auto_refill_item(FIRST_EASEL_ITEM_ID)
	_log("A006B 初見畫架劇情永久保存成功")
	_log("藍色顏料已永久解鎖")
	return true

# 26. 保存經過確認的完成劇情
func _save_completed_cutscene(timeline_id: String) -> bool:
	timeline_id = timeline_id.strip_edges()
	if timeline_id.is_empty():
		return false
	var success: bool = _commit_progress(SAVE_FIELD, timeline_id)
	if success:
		DataManager.mark_cutscene_completed(timeline_id)
	return success

# 27. 保存商人任務
func commit_merchant_quest() -> bool:
	var current_value: Variant = Dialogic.VAR.merchant_quest
	if not _is_valid_integer(current_value):
		return _fail("商人任務變數不是有效整數")
	return _commit_progress(VARIABLES_FIELD, int(current_value))

# 28. 保存永久戰鬥解鎖
func commit_combat_unlock() -> bool:
	if not DataManager.can_combat():
		_log("戰鬥能力尚未解鎖，略過永久保存")
		return false
	var success: bool = _commit_progress(COMBAT_FIELD, true)
	if success:
		DataManager.combat_unlocked = true
	return success

# 29. 保存永久事件旗標
func commit_story_flag(flag_id: String) -> bool:
	flag_id = flag_id.strip_edges()
	if flag_id.is_empty():
		return _fail("永久事件旗標不可為空")
	if not DataManager.is_cutscene_completed(flag_id):
		_log("事件尚未完成，略過保存：" + flag_id)
		return false
	return _commit_progress(FLAGS_FIELD, flag_id)

# ============================================================
# 30. 驗證正式保存工作階段
# F6 獨立測試及主選單不得寫入正式存檔。
# ============================================================
func _can_save_progress() -> bool:
	if _is_saving:
		return false
	if not _progress_valid:
		return _fail("劇情資料格式異常，禁止覆蓋")
	if _loaded_slot_id <= 0:
		_log("目前未載入正式存檔，略過保存")
		return false
	if SaveManager.current_slot_id != _loaded_slot_id:
		return _fail("目前存檔與劇情工作階段不一致")
	if SaveManager.get_slot_state(_loaded_slot_id) != SaveManager.SlotState.READY:
		return _fail("目前存檔不是可安全更新的狀態")
	return true

# 31. 驗證既有世界永久資料
func _validate_world_progress(world: Dictionary) -> bool:
	if _read_id_array(world.get(SAVE_FIELD, [])) == null:
		return false
	if _read_id_array(world.get(FLAGS_FIELD, [])) == null:
		return false
	if _read_merchant_quest(world) == null:
		return false
	if typeof(world.get(COMBAT_FIELD, false)) != TYPE_BOOL:
		return false
	return true

# ============================================================
# 32. 共用永久進度保存
# 只更新指定的世界資料，不覆蓋玩家背包或裝備。
# ============================================================
func _commit_progress(category: String, value: Variant) -> bool:
	if not _can_save_progress():
		return false
	var candidate: Dictionary = SaveManager.get_current_data()
	if typeof(candidate.get("world")) != TYPE_DICTIONARY:
		return _fail("world 資料格式異常")
	var world: Dictionary = candidate["world"]
	if not _validate_world_progress(world):
		_progress_valid = false
		return _fail("既有劇情資料格式異常")
	var previous_world: Dictionary = world.duplicate(true)

	# 更新指定永久資料。
	match category:
		SAVE_FIELD:
			if typeof(value) != TYPE_STRING:
				return _fail("劇情 ID 格式錯誤")
			var completed_ids: Array[String] = []
			completed_ids.assign(_read_id_array(world.get(SAVE_FIELD, [])))
			var timeline_id: String = String(value)
			if not completed_ids.has(timeline_id):
				completed_ids.append(timeline_id)
			world[SAVE_FIELD] = completed_ids

		VARIABLES_FIELD:
			if not _is_valid_integer(value):
				return _fail("任務數值格式錯誤")
			var variables_data: Dictionary = world.get(VARIABLES_FIELD, {})
			variables_data[MERCHANT_VARIABLE] = int(value)
			world[VARIABLES_FIELD] = variables_data

		COMBAT_FIELD:
			if typeof(value) != TYPE_BOOL:
				return _fail("戰鬥解鎖格式錯誤")
			world[COMBAT_FIELD] = value

		FLAGS_FIELD:
			if typeof(value) != TYPE_STRING:
				return _fail("事件旗標格式錯誤")
			var flags: Array[String] = []
			flags.assign(_read_id_array(world.get(FLAGS_FIELD, [])))
			var flag_id: String = String(value)
			if not flags.has(flag_id):
				flags.append(flag_id)
			world[FLAGS_FIELD] = flags

		_:
			return _fail("未知的劇情保存類型：" + category)

	# 避免重複寫入相同資料。
	if world == previous_world:
		_log("資料沒有變更，略過重複寫入：" + category)
		return true

	candidate["world"] = world
	_is_saving = true
	var success: bool = SaveManager.save_current_data(candidate)
	_is_saving = false
	if not success:
		return _fail("SaveManager 寫入劇情進度失敗")

	if category == SAVE_FIELD:
		cutscene_saved.emit(_loaded_slot_id, String(value))
		_log("Slot %02d 劇情永久保存成功：%s" % [
			_loaded_slot_id, String(value)
		])
		_log("目前永久完成劇情：" + str(world.get(SAVE_FIELD, [])))

	progress_saved.emit(_loaded_slot_id, category)
	_log("Slot %02d 永久進度保存成功：%s = %s" % [
		_loaded_slot_id, category, str(value)
	])
	return true

# 33. 統一除錯輸出
func _log(message: String) -> void:
	if debug_log:
		print("【StoryProgress】" + message)

# 34. 統一錯誤處理
func _fail(reason: String) -> bool:
	push_error("【StoryProgress】Slot %02d 保存失敗：%s" % [
		_loaded_slot_id, reason
	])
	progress_save_failed.emit(_loaded_slot_id, reason)
	return false

# ============================================================
# 35. V3.3：正式結束劇情工作階段
# 清除運行時資料，不清除已永久保存的劇情。
# ============================================================
func _on_session_closed(slot_id: int) -> void:
	_loaded_slot_id = 0
	_is_saving = false
	_progress_valid = true
	_reset_runtime_progress()
	_log("Slot %02d 劇情工作階段已結束" % slot_id)
	_log("永久劇情運行時資料已清除")
	_log("商人任務變數已重設")
	_log("戰鬥解鎖狀態已重設")

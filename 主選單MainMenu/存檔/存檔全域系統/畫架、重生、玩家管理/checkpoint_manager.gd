
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# CheckpointManager V8｜畫架與世界永久資料整合管理器
# Godot 4.5.1
# Autoload：CheckpointManager
# STEP 10.8.6
# ============================================================
# 主要職責：
# 1. 管理正式地圖及畫架 ID。
# 2. 解析場景及出生定位點。
# 3. 驗證目前地圖、畫架及正式存檔工作階段。
# 4. 更新正式檢查點及存檔摘要。
# 5. 保存永久金幣、背包及快捷欄。
# 6. 保存貼紙收藏及貼紙裝備。
# 7. 保存 Boss、捷徑及唯一性道具紀錄。
# 8. 保留其他劇情及永久世界資料。
# 9. 防止重複存檔及轉場衝突。
# 10. 寫入失敗時還原本次額外補給。
#
# V8 正式保存順序：
# 金幣 → 背包 → 快捷欄 → 貼紙收藏
# → 貼紙裝備 → 世界永久狀態
# 最後統一交由 SaveManager 寫入一次。
#
# 不修改 Schema Version 1。
# 不修改既有畫架登記及定位規則。
# 不直接控制 Boss、門鎖及特殊道具。
# 不覆蓋 StoryProgress 管理的永久劇情資料。
# ============================================================

# ============================================================
# 1. 初始出生點及正式畫架 ID
# ============================================================
const INITIAL_MAP_ID: String = "first_land_sakura_garden"
const INITIAL_EASEL_ID: String = "easel_start_01"
const AM002_MAP_ID: String = "am002"
const AM002_EASEL_01_ID: String = "easel_am002_01"

# ============================================================
# 2. 地圖及檢查點登記表
# ============================================================
const MAP_REGISTRY: Dictionary = {
	"first_land_sakura_garden": {
		"scene_path": "res://Maps/AM001.tscn",
		"checkpoints": {
			"easel_start_01": {
				"spawn_name": "NewGameSpawnPoint",
				"is_initial": true
			}
		}
	},
	"am002": {
		"scene_path": "res://Maps/AM002.tscn",
		"checkpoints": {
			"easel_am002_01": {
				"spawn_name": "CheckpointSpawn_AM002_01",
				"is_initial": false
			}
		}
	}
}

# ============================================================
# 3. 對外訊號
# ============================================================
signal checkpoint_saved(slot_id: int, map_id: String, easel_id: String)

# ============================================================
# 4. Inspector 設定
# ============================================================
@export_group("除錯設定")
@export var debug_log: bool = true

# ============================================================
# 5. 內部操作狀態
# ============================================================
var _is_saving: bool = false

# ============================================================
# 6. 初始化
# ============================================================
func _ready() -> void:
	if debug_log:
		print("【CheckpointManager】V8 畫架與世界資料管理器初始化完成")
		print("【CheckpointManager】已登記地圖數量：", MAP_REGISTRY.size())
		print("【CheckpointManager】已登記定位點數量：", get_checkpoint_count())

# ============================================================
# 7. 檢查地圖是否存在
# ============================================================
func has_map(map_id: String) -> bool:
	return MAP_REGISTRY.has(map_id)

# ============================================================
# 8. 檢查畫架是否屬於指定地圖
# ============================================================
func has_checkpoint(map_id: String, easel_id: String) -> bool:
	if not has_map(map_id):
		return false

	var map_data: Dictionary = MAP_REGISTRY[map_id]
	var checkpoints: Dictionary = map_data["checkpoints"]

	return checkpoints.has(easel_id)

# ============================================================
# 9. 解析地圖場景路徑
# ============================================================
func resolve_map_scene(map_id: String) -> String:
	if not has_map(map_id):
		return ""

	var map_data: Dictionary = MAP_REGISTRY[map_id]
	return String(map_data["scene_path"])

# ============================================================
# 10. 解析完整檢查點資料
# 回傳新的 Dictionary，避免污染原始登記表。
# ============================================================
func resolve_checkpoint(map_id: String, easel_id: String) -> Dictionary:
	if not has_checkpoint(map_id, easel_id):
		return {}

	var map_data: Dictionary = MAP_REGISTRY[map_id]
	var checkpoints: Dictionary = map_data["checkpoints"]
	var checkpoint: Dictionary = checkpoints[easel_id]

	return {
		"map_id": map_id,
		"easel_id": easel_id,
		"scene_path": String(map_data["scene_path"]),
		"spawn_name": String(checkpoint["spawn_name"]),
		"is_initial": bool(checkpoint["is_initial"])
	}

# ============================================================
# 11. 解析出生點名稱
# ============================================================
func resolve_spawn_name(map_id: String, easel_id: String) -> String:
	var checkpoint: Dictionary = resolve_checkpoint(map_id, easel_id)

	if checkpoint.is_empty():
		return ""

	return String(checkpoint["spawn_name"])

# ============================================================
# 12. 取得新遊戲初始出生點
# ============================================================
func get_initial_checkpoint() -> Dictionary:
	return resolve_checkpoint(INITIAL_MAP_ID, INITIAL_EASEL_ID)

# ============================================================
# 13. 驗證檢查點場景資源
# ============================================================
func validate_checkpoint(map_id: String, easel_id: String) -> bool:
	var checkpoint: Dictionary = resolve_checkpoint(map_id, easel_id)

	if checkpoint.is_empty():
		return false

	var scene_path: String = checkpoint["scene_path"]
	var spawn_name: String = checkpoint["spawn_name"]

	if scene_path.is_empty():
		return false

	if spawn_name.is_empty():
		return false

	return ResourceLoader.exists(scene_path, "PackedScene")

# ============================================================
# 14. 統計全部定位點
# ============================================================
func get_checkpoint_count() -> int:
	var total: int = 0

	for map_id in MAP_REGISTRY:
		var map_data: Dictionary = MAP_REGISTRY[map_id]
		var checkpoints: Dictionary = map_data["checkpoints"]
		total += checkpoints.size()

	return total

# ============================================================
# 15. 尋找目前地圖中的正式出生點
# ============================================================
func get_current_spawn_marker(map_id: String, easel_id: String) -> Marker2D:
	var checkpoint: Dictionary = resolve_checkpoint(map_id, easel_id)

	if checkpoint.is_empty():
		return null

	var current_map: Node = get_tree().current_scene

	if not is_instance_valid(current_map):
		return null

	if current_map.scene_file_path != String(checkpoint["scene_path"]):
		return null

	var spawn_name: String = checkpoint["spawn_name"]
	var matches: Array[Node] = current_map.find_children(
		spawn_name,
		"",
		true,
		false
	)

	if matches.size() != 1:
		return null

	return matches[0] as Marker2D

# ============================================================
# 16. 正式保存畫架檢查點
#
# V8 新增保存欄位：
# world.defeated_bosses
# world.opened_shortcuts
# world.collected_unique_items
#
# 所有資料驗證完成後才執行正式 JSON 寫入。
# ============================================================
func save_checkpoint(map_id: String, easel_id: String) -> bool:
	# A. 防止重複保存及轉場衝突。
	if _is_saving:
		return false

	if SceneTransition.is_transitioning:
		return _fail("場景正在切換")

	# B. 驗證正式存檔及各管理器工作階段。
	var slot_id: int = SaveManager.current_slot_id

	if slot_id <= 0:
		return _fail("目前沒有正式存檔工作階段")

	if SaveManager.get_slot_state(slot_id) != SaveManager.SlotState.READY:
		return _fail("目前存檔無法安全更新")

	if not PlayerProgress.can_save_gold():
		return _fail("玩家金幣工作階段尚未準備完成")

	if not PlayerProgress.can_save_inventory():
		return _fail("玩家背包工作階段尚未準備完成")

	if not PlayerProgress.can_save_quick_slots():
		return _fail("玩家快捷欄工作階段尚未準備完成")

	if not PlayerProgress.can_save_owned_stickers():
		return _fail("玩家貼紙收藏工作階段尚未準備完成")

	if not PlayerProgress.can_save_equipped_stickers():
		return _fail("玩家貼紙裝備工作階段尚未準備完成")

	# V8：正式世界資料工作階段驗證。
	if not WorldProgress.can_save_world():
		return _fail("世界永久資料工作階段尚未準備完成")

	# C. 驗證地圖及畫架。
	var checkpoint: Dictionary = resolve_checkpoint(map_id, easel_id)

	if checkpoint.is_empty():
		return _fail("地圖或畫架尚未正式登記")

	if bool(checkpoint["is_initial"]):
		return _fail("初始出生點不可作為正式畫架存檔")

	# D. 驗證實際出生定位點。
	var marker: Marker2D = get_current_spawn_marker(map_id, easel_id)

	if not is_instance_valid(marker):
		return _fail("目前地圖找不到合法且唯一的畫架定位點")

	# E. 取得正式存檔完整深層副本。
	var candidate: Dictionary = SaveManager.get_current_data().duplicate(true)

	if typeof(candidate.get("checkpoint")) != TYPE_DICTIONARY:
		return _fail("checkpoint 資料格式異常")

	if typeof(candidate.get("meta")) != TYPE_DICTIONARY:
		return _fail("meta 資料格式異常")

	# V8：驗證既有世界資料。
	if not WorldProgress.validate_world_data(candidate.get("world")):
		return _fail("既有世界永久資料格式異常")

	# F. 更新畫架資料。
	var checkpoint_data: Dictionary = candidate["checkpoint"]
	checkpoint_data["map_id"] = map_id
	checkpoint_data["easel_id"] = easel_id
	candidate["checkpoint"] = checkpoint_data

	# G. 更新存檔摘要。
	var meta: Dictionary = candidate["meta"]
	meta["map_display_name"] = DataManager.current_map_name
	candidate["meta"] = meta

	# H. 驗證補給前背包並保存還原副本。
	var inventory_before_refill: Dictionary = DataManager.inventory_items.duplicate(true)

	if not PlayerProgress.validate_inventory_items(inventory_before_refill):
		return _fail("補給前的玩家背包資料異常")

	# I. 驗證快捷欄。
	if not PlayerProgress.validate_quick_slot_configuration(
		DataManager.quick_slots,
		DataManager.current_slot_index,
		inventory_before_refill
	):
		return _fail("補給前的玩家快捷欄資料異常")

	# J. 驗證貼紙收藏。
	if not PlayerProgress.validate_owned_stickers(DataManager.owned_stickers):
		return _fail("玩家已取得貼紙資料異常")

	# K. 驗證貼紙裝備。
	if not PlayerProgress.validate_equipped_stickers(
		DataManager.equipped_stickers,
		DataManager.owned_stickers
	):
		return _fail("玩家貼紙裝備資料異常")

	# L. 鎖定操作及正式保存前補給。
	_is_saving = true
	DataManager.replenish_quick_slots()

	if SaveManager.current_slot_id != slot_id:
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"補給後發現存檔工作階段已變更"
		)

	# M. 加入玩家永久金幣。
	if not PlayerProgress.append_gold_to_candidate(candidate):
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"玩家永久金幣資料驗證失敗"
		)

	# N. 加入補給完成後的背包。
	if not PlayerProgress.append_inventory_to_candidate(candidate):
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"玩家永久背包資料驗證失敗"
		)

	# O. 加入永久快捷欄。
	if not PlayerProgress.append_quick_slots_to_candidate(candidate):
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"玩家永久快捷欄資料驗證失敗"
		)

	# P. 加入已取得貼紙。
	if not PlayerProgress.append_owned_stickers_to_candidate(candidate):
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"玩家永久貼紙收藏資料驗證失敗"
		)

	# Q. 加入已裝備貼紙。
	# 必須在貼紙收藏加入後執行。
	if not PlayerProgress.append_equipped_stickers_to_candidate(candidate):
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"玩家永久貼紙裝備資料驗證失敗"
		)

	# R. V8：加入世界永久狀態。
	# 不在此另外寫入 JSON。
	# 保留 StoryProgress 管理的其他世界欄位。
	if not WorldProgress.append_world_to_candidate(candidate):
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"世界永久資料驗證失敗"
		)

	# S. 正式寫入前最後確認。
	if SaveManager.current_slot_id != slot_id:
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"正式寫入前發現存檔工作階段已變更"
		)

	if not WorldProgress.can_save_world():
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"正式寫入前世界工作階段已失效"
		)

	if SceneTransition.is_transitioning:
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"正式寫入前發現場景正在切換"
		)

	# T. 記錄本次準備正式寫入的資料。
	var saved_gold: int = int(candidate["player"]["stats"]["total_gold"])
	var saved_items: Dictionary = candidate["player"]["inventory"]["items"]
	var saved_slots: Array = candidate["player"]["equipment"]["quick_slots"]
	var saved_index: int = int(candidate["player"]["equipment"]["current_slot_index"])
	var saved_owned_stickers: Array = candidate["player"]["inventory"]["owned_stickers"]
	var saved_equipped_stickers: Array = candidate["player"]["equipment"]["equipped_stickers"]

	var saved_world: Dictionary = candidate["world"]
	var saved_bosses: Dictionary = saved_world["defeated_bosses"]
	var saved_shortcuts: Dictionary = saved_world["opened_shortcuts"]
	var saved_unique_items: Dictionary = saved_world["collected_unique_items"]

	# U. 統一正式寫入。
	# 沿用既有暫存檔、備份及 JSON 驗證機制。
	var success: bool = SaveManager.save_current_data(candidate)

	if not success:
		return _rollback_inventory_and_fail(
			slot_id,
			inventory_before_refill,
			"SaveManager 寫入失敗"
		)

	# V. 正式寫入成功。
	# 只有 SaveManager 回傳成功才輸出永久保存紀錄。
	if debug_log:
		print("【CheckpointManager】Slot %02d 畫架存檔成功" % slot_id)
		print("【CheckpointManager】地圖 ID：", map_id)
		print("【CheckpointManager】畫架 ID：", easel_id)
		print("【CheckpointManager】出生點：", checkpoint["spawn_name"])

		print("【CheckpointManager】永久金幣保存成功：", saved_gold)

		print("【CheckpointManager】永久背包保存成功")
		print("【CheckpointManager】已保存道具種類：", saved_items.size())
		print("【CheckpointManager】背包正式保存內容：")
		print(JSON.stringify(saved_items, "\t"))

		print("【CheckpointManager】永久快捷欄保存成功")
		print("【CheckpointManager】已保存快捷欄：", saved_slots)
		print("【CheckpointManager】已保存選取編號：", saved_index)
		print("【CheckpointManager】已保存選取欄位：第 %d 格" % (saved_index + 1))

		print("【CheckpointManager】永久貼紙收藏保存成功")
		print("【CheckpointManager】已保存貼紙：", saved_owned_stickers)
		print("【CheckpointManager】已保存貼紙數量：", saved_owned_stickers.size())

		print("【CheckpointManager】永久貼紙裝備保存成功")
		print("【CheckpointManager】已保存貼紙裝備：", saved_equipped_stickers)

		# V8：世界永久狀態正式保存紀錄。
		print("【CheckpointManager】世界永久資料保存成功")
		print("【CheckpointManager】已擊敗 Boss 數量：", saved_bosses.size())
		print("【CheckpointManager】已擊敗 Boss 紀錄：", saved_bosses)
		print("【CheckpointManager】已開啟捷徑數量：", saved_shortcuts.size())
		print("【CheckpointManager】已開啟捷徑紀錄：", saved_shortcuts)
		print("【CheckpointManager】已取得唯一性道具數量：", saved_unique_items.size())
		print("【CheckpointManager】已取得唯一性道具紀錄：", saved_unique_items)

	checkpoint_saved.emit(slot_id, map_id, easel_id)
	_is_saving = false

	return true

# ============================================================
# 17. 背包補給還原及失敗處理
# 不撤銷原本商店交易及世界運行時事件。
# 只還原本次正式保存所增加的額外補給。
# ============================================================
func _rollback_inventory_and_fail(
	slot_id: int,
	previous_inventory: Dictionary,
	reason: String
) -> bool:
	if SaveManager.current_slot_id == slot_id:
		DataManager.inventory_items = previous_inventory.duplicate(true)
		DataManager.quick_slot_updated.emit()

		if debug_log:
			print("【CheckpointManager】已還原本次額外背包補給")

	_is_saving = false

	return _fail(reason)

# ============================================================
# 18. 統一失敗處理
# ============================================================
func _fail(reason: String) -> bool:
	push_warning("【CheckpointManager】畫架存檔失敗：" + reason)
	return false

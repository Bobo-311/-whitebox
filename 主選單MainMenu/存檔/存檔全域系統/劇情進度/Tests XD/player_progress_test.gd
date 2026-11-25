extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerProgressTest V1｜玩家資料架構獨立驗收
#
# Godot 4.5.1
#
# STEP 10.7.1-A
#
# ============================================================
# 測試目的
# ============================================================
#
# 1. 確認 PlayerProgress 正常初始化
# 2. 確認新遊戲預設資料正確
# 3. 確認運行時玩家資料可正常收集
# 4. 確認深層副本不會污染原始資料
# 5. 確認異常金幣資料能被拒絕
# 6. 確認異常道具數量能被拒絕
# 7. 確認異常快捷欄能被拒絕
# 8. 確認異常貼紙裝備能被拒絕
# 9. 確認 JSON 序列化相容性
#
# ============================================================
# 安全規則
# ============================================================
#
# 不建立正式存檔。
# 不讀取正式存檔。
# 不刪除正式存檔。
# 不寫入 JSON 檔案。
# 不修改 DataManager 運行時資料。
# 不觸發任何正式劇情。
#
# 所有異常資料均透過 Dictionary 副本模擬。
#
# ============================================================


# ============================================================
# 1. 測試統計
# ============================================================

var _passed: int = 0

var _failed: int = 0


# ============================================================
# 2. 測試入口
# ============================================================

func _ready() -> void:

	if not OS.is_debug_build():

		return

	call_deferred("_run_tests")


# ============================================================
# 3. 執行所有測試
# ============================================================

func _run_tests() -> void:

	print("")
	print("========== PlayerProgress Test ==========")

	if SaveManager.current_slot_id != 0:

		push_error(
			"【測試停止】目前已有正式存檔工作階段"
		)

		return

	_check(
		PlayerProgress.is_initialized(),
		"A1 PlayerProgress 初始化完成"
	)

	if not PlayerProgress.is_initialized():

		return

	var initial_data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	var runtime_data: Dictionary = (
		PlayerProgress.capture_runtime_data()
	)

	_check(
		not initial_data.is_empty(),
		"A2 初始玩家資料存在"
	)

	_check(
		not runtime_data.is_empty(),
		"A3 運行時玩家資料存在"
	)

	if initial_data.is_empty() or runtime_data.is_empty():

		_print_result()

		return

	if not PlayerProgress.validate_player_data(initial_data):

		push_error("【測試停止】初始資料格式異常")

		return

	if not PlayerProgress.validate_player_data(runtime_data):

		push_error("【測試停止】運行時資料格式異常")

		return

	_test_initial_data()

	_test_runtime_data()

	_test_copy_protection()

	_test_invalid_gold()

	_test_invalid_inventory()

	_test_invalid_equipment()

	_test_json_serialization()

	_print_result()


# ============================================================
# 4. 測試 B｜全新遊戲初始資料
# ============================================================

func _test_initial_data() -> void:

	print("")
	print("---------- 測試 B ----------")

	var data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	var stats: Dictionary = data["stats"]

	var inventory: Dictionary = data["inventory"]

	var items: Dictionary = inventory["items"]

	var equipment: Dictionary = data["equipment"]

	_check(
		stats["total_gold"] == 0,
		"B1 初始金幣為 0"
	)

	_check(
		items.has("hp_paint"),
		"B2 藍色顏料資料存在"
	)

	_check(
		items.get("hp_paint", {}).get(
			"unlocked",
			true
		) == false,
		"B3 藍色顏料尚未解鎖"
	)

	_check(
		items.get("hp_paint", {}).get(
			"current_carry",
			-1
		) == 0,
		"B4 藍色顏料初始數量為 0"
	)

	_check(
		equipment["quick_slots"].size() == 5,
		"B5 道具快捷欄為五格"
	)

	_check(
		equipment["equipped_stickers"].size() == 4,
		"B6 貼紙裝備欄為四格"
	)

	_check(
		inventory["owned_stickers"].is_empty(),
		"B7 初始尚未取得貼紙"
	)

	_check(
		PlayerProgress.validate_player_data(data),
		"B8 初始玩家資料通過完整驗證"
	)


# ============================================================
# 5. 測試 C｜目前運行時玩家資料
# ============================================================

func _test_runtime_data() -> void:

	print("")
	print("---------- 測試 C ----------")

	var data: Dictionary = (
		PlayerProgress.capture_runtime_data()
	)

	_check(
		data["stats"]["total_gold"]
		== DataManager.total_gold,
		"C1 金幣資料收集正常"
	)

	_check(
		data["inventory"]["items"]
		== DataManager.inventory_items,
		"C2 背包資料收集正常"
	)

	_check(
		data["equipment"]["quick_slots"]
		== DataManager.quick_slots,
		"C3 快捷欄資料收集正常"
	)

	_check(
		data["inventory"]["owned_stickers"]
		== DataManager.owned_stickers,
		"C4 已取得貼紙資料收集正常"
	)

	_check(
		data["equipment"]["equipped_stickers"]
		== DataManager.equipped_stickers,
		"C5 裝備貼紙資料收集正常"
	)


# ============================================================
# 6. 測試 D｜深層副本資料保護
#
# 修改取得的副本，
# 確認不會影響 DataManager 或初始資料。
# ============================================================

func _test_copy_protection() -> void:

	print("")
	print("---------- 測試 D ----------")

	var data: Dictionary = (
		PlayerProgress.capture_runtime_data()
	)

	var original_gold: int = DataManager.total_gold

	var original_paint: int = (
		DataManager.inventory_items["hp_paint"]["current_carry"]
	)

	# 故意修改副本。
	data["stats"]["total_gold"] = 999999

	data["inventory"]["items"]["hp_paint"]["current_carry"] = 99

	data["equipment"]["quick_slots"][0] = "hp_paint"

	_check(
		DataManager.total_gold == original_gold,
		"D1 金幣原始資料未受污染"
	)

	_check(
		DataManager.inventory_items["hp_paint"]["current_carry"]
		== original_paint,
		"D2 背包原始資料未受污染"
	)

	_check(
		DataManager.quick_slots[0] == "",
		"D3 快捷欄原始資料未受污染"
	)

	var initial_copy: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	initial_copy["stats"]["total_gold"] = 888888

	var fresh_copy: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	_check(
		fresh_copy["stats"]["total_gold"] == 0,
		"D4 初始玩家資料未受污染"
	)


# ============================================================
# 7. 測試 E｜異常金幣防護
# ============================================================

func _test_invalid_gold() -> void:

	print("")
	print("---------- 測試 E ----------")

	var data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	data["stats"]["total_gold"] = -100

	_check(
		not PlayerProgress.validate_player_data(data),
		"E1 正確拒絕負數金幣"
	)

	data["stats"]["total_gold"] = 10.5

	_check(
		not PlayerProgress.validate_player_data(data),
		"E2 正確拒絕小數金幣"
	)

	data["stats"]["total_gold"] = "100"

	_check(
		not PlayerProgress.validate_player_data(data),
		"E3 正確拒絕文字金幣"
	)

	data["stats"]["total_gold"] = 100.0

	_check(
		PlayerProgress.validate_player_data(data),
		"E4 正確接受 JSON 整數型浮點數"
	)


# ============================================================
# 8. 測試 F｜異常背包防護
# ============================================================

func _test_invalid_inventory() -> void:

	print("")
	print("---------- 測試 F ----------")

	var data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	data["inventory"]["items"]["hp_paint"]["current_carry"] = -1

	_check(
		not PlayerProgress.validate_player_data(data),
		"F1 正確拒絕負數道具"
	)

	data["inventory"]["items"]["hp_paint"]["current_carry"] = 999

	_check(
		not PlayerProgress.validate_player_data(data),
		"F2 正確拒絕超出隨身上限"
	)

	data["inventory"]["items"]["hp_paint"]["current_carry"] = 0

	data["inventory"]["items"]["hp_paint"]["unlocked"] = "true"

	_check(
		not PlayerProgress.validate_player_data(data),
		"F3 正確拒絕異常解鎖格式"
	)

	data["inventory"]["items"]["hp_paint"]["unlocked"] = false

	data["inventory"]["items"]["unknown_item"] = {

		"current_carry": 1,

		"reserve_amount": 0
	}

	_check(
		not PlayerProgress.validate_player_data(data),
		"F4 正確拒絕未登記道具"
	)


# ============================================================
# 9. 測試 G｜異常裝備資料防護
# ============================================================

func _test_invalid_equipment() -> void:

	print("")
	print("---------- 測試 G ----------")

	var data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	data["equipment"]["quick_slots"] = [
		"",
		""
	]

	_check(
		not PlayerProgress.validate_player_data(data),
		"G1 正確拒絕錯誤快捷欄數量"
	)

	data["equipment"]["quick_slots"] = [
		"potion_gugu",
		"potion_gugu",
		"",
		"",
		""
	]

	_check(
		not PlayerProgress.validate_player_data(data),
		"G2 正確拒絕重複裝備道具"
	)

	data["equipment"]["quick_slots"] = [
		"",
		"",
		"",
		"",
		""
	]

	data["equipment"]["current_slot_index"] = 5

	_check(
		not PlayerProgress.validate_player_data(data),
		"G3 正確拒絕超出範圍的快捷欄"
	)

	data["equipment"]["current_slot_index"] = 0

	data["equipment"]["equipped_stickers"] = [
		"001",
		"",
		"",
		""
	]

	_check(
		not PlayerProgress.validate_player_data(data),
		"G4 正確拒絕尚未取得的貼紙"
	)

	data["inventory"]["owned_stickers"] = [
		"001"
	]

	_check(
		PlayerProgress.validate_player_data(data),
		"G5 已取得的合法貼紙可正常裝備"
	)

	data["equipment"]["equipped_stickers"] = [
		"001",
		"001",
		"",
		""
	]

	_check(
		not PlayerProgress.validate_player_data(data),
		"G6 正確拒絕重複裝備貼紙"
	)


# ============================================================
# 10. 測試 H｜JSON 序列化相容性
#
# 此處只在記憶體中進行：
#
# Dictionary → JSON 字串 → Dictionary
#
# 不會建立任何實體 JSON 檔案。
# ============================================================

func _test_json_serialization() -> void:

	print("")
	print("---------- 測試 H ----------")

	var data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	var json_text: String = JSON.stringify(data)

	var parser := JSON.new()

	var result: Error = parser.parse(json_text)

	_check(
		result == OK,
		"H1 玩家資料可正常轉換及解析 JSON"
	)

	if result != OK:

		return

	if typeof(parser.data) != TYPE_DICTIONARY:

		_check(
			false,
			"H2 JSON 解析結果格式錯誤"
		)

		return

	var restored: Dictionary = parser.data

	_check(
		PlayerProgress.validate_player_data(restored),
		"H2 JSON 還原資料通過完整驗證"
	)

	_check(
		restored["stats"]["total_gold"] == 0,
		"H3 JSON 金幣資料正確"
	)

	_check(
		restored["inventory"]["items"]["hp_paint"]["unlocked"]
		== false,
		"H4 JSON 顏料解鎖狀態正確"
	)


# ============================================================
# 11. 統一測試結果
# ============================================================

func _check(
	condition: bool,
	description: String
) -> void:

	if condition:

		_passed += 1

		print(
			"【PASS】",
			description
		)

	else:

		_failed += 1

		push_error(
			"【FAIL】" + description
		)


# ============================================================
# 12. 最終驗收結果
# ============================================================

func _print_result() -> void:

	print("")
	print("========== 測試結果 ==========")

	print("通過項目：", _passed)

	print("失敗項目：", _failed)

	if _failed == 0:

		print("========== 全部測試通過 ==========")

	else:

		push_error(
			"【PlayerProgressTest】存在未通過項目"
		)

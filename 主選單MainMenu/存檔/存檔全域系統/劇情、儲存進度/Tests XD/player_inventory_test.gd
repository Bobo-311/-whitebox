extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerInventoryTest V1｜玩家背包獨立驗收測試
#
# Godot 4.5.1
# STEP 10.7.3
#
# ============================================================
# 測試目的
# ============================================================
#
# 1. 驗證全新遊戲初始背包
# 2. 驗證舊存檔相容
# 3. 驗證 A006B 顏料永久解鎖相容
# 4. 驗證道具隨身與庫存數量
# 5. 驗證新增道具資料
# 6. 驗證 JSON 數字轉換
# 7. 驗證異常背包資料防護
# 8. 驗證初始資料及輸入資料不受污染
#
# ============================================================
# 安全規則
# ============================================================
#
# 本測試僅供 F6 開發測試。
#
# 不建立正式存檔。
# 不刪除正式存檔。
# 不寫入 JSON 檔案。
# 不修改 DataManager 運行時背包。
# 不播放任何 Dialogic 劇情。
#
# 所有測試皆使用獨立 Dictionary 副本。
# ============================================================


# ============================================================
# 1. 測試結果統計
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
	print("========== PlayerInventory Test ==========")

	if SaveManager.current_slot_id != 0:

		push_error(
			"【測試停止】目前已有正式存檔工作階段"
		)

		return

	if not PlayerProgress.is_initialized():

		push_error(
			"【測試停止】PlayerProgress 尚未初始化"
		)

		return

	var original_inventory: Dictionary = (
		DataManager.inventory_items.duplicate(true)
	)

	var original_initial_data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	_test_initial_inventory()

	_test_legacy_inventory()

	_test_hp_paint_story()

	_test_saved_inventory()

	_test_json_conversion()

	_test_invalid_inventory()

	_test_data_protection()

	# 最終確認正式運行時資料沒有被修改。
	print("")
	print("---------- 測試 H ----------")

	_check(
		DataManager.inventory_items == original_inventory,
		"H1 正式運行時背包未受到污染"
	)

	_check(
		PlayerProgress.get_initial_player_data()
		== original_initial_data,
		"H2 初始玩家資料未受到污染"
	)

	_print_result()


# ============================================================
# 4. 測試 A｜初始背包
# ============================================================

func _test_initial_inventory() -> void:

	print("")
	print("---------- 測試 A ----------")

	var initial: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	var items: Dictionary = (
		initial["inventory"]["items"]
	)

	_check(
		items.has("hp_paint"),
		"A1 初始藍色顏料資料存在"
	)

	_check(
		items["hp_paint"]["unlocked"] == false,
		"A2 初始顏料尚未解鎖"
	)

	_check(
		items["hp_paint"]["current_carry"] == 0,
		"A3 初始顏料數量為零"
	)

	_check(
		items["potion_gugu"]["current_carry"] == 2,
		"A4 初始咕咕嘎嘎藥水數量正確"
	)

	_check(
		PlayerProgress.validate_inventory_items(items),
		"A5 初始背包通過完整驗證"
	)


# ============================================================
# 5. 測試 B｜舊存檔相容
# ============================================================

func _test_legacy_inventory() -> void:

	print("")
	print("---------- 測試 B ----------")

	var restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			{},
			false
		)
	)

	_check(
		not restored.is_empty(),
		"B1 空白舊背包可正常還原"
	)

	_check(
		restored["hp_paint"]["unlocked"] == false,
		"B2 舊版新遊戲不會提前解鎖顏料"
	)

	_check(
		restored["miracle_apple"]["current_carry"] == 1,
		"B3 舊存檔可取得初始道具"
	)


# ============================================================
# 6. 測試 C｜A006B 顏料解鎖相容
# ============================================================

func _test_hp_paint_story() -> void:

	print("")
	print("---------- 測試 C ----------")

	var legacy_restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			{},
			true
		)
	)

	var max_paint: int = int(
		DataManager.ITEM_DB["hp_paint"]["max_carry"]
	)

	_check(
		legacy_restored["hp_paint"]["unlocked"],
		"C1 A006B 舊存檔顏料解鎖正確"
	)

	_check(
		legacy_restored["hp_paint"]["current_carry"]
		== max_paint,
		"C2 A006B 舊存檔顏料數量正確"
	)

	# 已保存正式背包的存檔，
	# 不應因為讀檔而無條件補滿。
	var saved_items: Dictionary = {

		"hp_paint": {

			"current_carry": 1,

			"reserve_amount": 0,

			"unlocked": true
		}
	}

	var restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			saved_items,
			true
		)
	)

	_check(
		restored["hp_paint"]["unlocked"],
		"C3 正式背包保留顏料解鎖"
	)

	_check(
		restored["hp_paint"]["current_carry"] == 1,
		"C4 正式背包保留實際顏料次數"
	)


# ============================================================
# 7. 測試 D｜正式背包資料還原
# ============================================================

func _test_saved_inventory() -> void:

	print("")
	print("---------- 測試 D ----------")

	var saved_items: Dictionary = {

		"potion_gugu": {

			"current_carry": 1,

			"reserve_amount": 8
		},

		"eraser": {

			"current_carry": 2,

			"reserve_amount": 5,

			"unlocked": true
		},

		"calyon": {

			"current_carry": 1,

			"reserve_amount": 3,

			"unlocked": true
		},

		"ruler": {

			"current_carry": 0,

			"reserve_amount": 4,

			"unlocked": true
		}
	}

	var restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			saved_items,
			false
		)
	)

	_check(
		restored["potion_gugu"]["current_carry"] == 1,
		"D1 隨身數量正常還原"
	)

	_check(
		restored["potion_gugu"]["reserve_amount"] == 8,
		"D2 倉庫數量正常還原"
	)

	_check(
		restored.has("eraser"),
		"D3 藍色橡皮擦正常還原"
	)

	_check(
		restored.has("calyon"),
		"D4 紅色蠟筆正常還原"
	)

	_check(
		restored.has("ruler"),
		"D5 黃色尺正常還原"
	)

	_check(
		restored["ruler"]["current_carry"] == 0,
		"D6 用完的道具仍保留零數量"
	)

	_check(
		restored["eraser"]["unlocked"],
		"D7 新增道具解鎖狀態正確"
	)


# ============================================================
# 8. 測試 E｜JSON 數值相容
#
# 只在記憶體內進行 JSON 轉換。
# 不建立任何實體檔案。
# ============================================================

func _test_json_conversion() -> void:

	print("")
	print("---------- 測試 E ----------")

	var source: Dictionary = {

		"potion_gugu": {

			"current_carry": 1,

			"reserve_amount": 10
		}
	}

	var json_text: String = JSON.stringify(source)

	var parsed: Variant = JSON.parse_string(
		json_text
	)

	_check(
		typeof(parsed) == TYPE_DICTIONARY,
		"E1 背包可正常轉換及解析 JSON"
	)

	if typeof(parsed) != TYPE_DICTIONARY:

		return

	var restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			parsed,
			false
		)
	)

	_check(
		restored["potion_gugu"]["reserve_amount"] == 10,
		"E2 JSON 背包數量正確"
	)

	_check(
		typeof(
			restored["potion_gugu"]["reserve_amount"]
		) == TYPE_INT,
		"E3 JSON 還原後庫存統一為整數"
	)


# ============================================================
# 9. 測試 F｜異常背包防護
# ============================================================

func _test_invalid_inventory() -> void:

	print("")
	print("---------- 測試 F ----------")

	var negative_items: Dictionary = {

		"potion_gugu": {

			"current_carry": -1,

			"reserve_amount": 0
		}
	}

	_check(
		not PlayerProgress.validate_inventory_items(
			negative_items
		),
		"F1 正確拒絕負數道具"
	)

	var overflow_items: Dictionary = {

		"potion_gugu": {

			"current_carry": 999,

			"reserve_amount": 0
		}
	}

	_check(
		not PlayerProgress.validate_inventory_items(
			overflow_items
		),
		"F2 正確拒絕超出隨身上限"
	)

	var unknown_items: Dictionary = {

		"unknown_test_item": {

			"current_carry": 1,

			"reserve_amount": 0
		}
	}

	_check(
		not PlayerProgress.validate_inventory_items(
			unknown_items
		),
		"F3 正確拒絕未登記道具"
	)

	var invalid_unlock: Dictionary = {

		"hp_paint": {

			"current_carry": 1,

			"reserve_amount": 0,

			"unlocked": "true"
		}
	}

	_check(
		not PlayerProgress.validate_inventory_items(
			invalid_unlock
		),
		"F4 正確拒絕錯誤解鎖格式"
	)

	_check(
		PlayerProgress.build_restored_inventory(
			negative_items,
			false
		).is_empty(),
		"F5 異常背包不會被視為正常資料"
	)


# ============================================================
# 10. 測試 G｜資料副本保護
# ============================================================

func _test_data_protection() -> void:

	print("")
	print("---------- 測試 G ----------")

	var source: Dictionary = {

		"potion_gugu": {

			"current_carry": 1,

			"reserve_amount": 5
		}
	}

	var restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			source,
			false
		)
	)

	restored["potion_gugu"]["reserve_amount"] = 999

	_check(
		source["potion_gugu"]["reserve_amount"] == 5,
		"G1 原始輸入背包未受到污染"
	)

	var restored_again: Dictionary = (
		PlayerProgress.build_restored_inventory(
			{},
			false
		)
	)

	_check(
		restored_again["potion_gugu"]["reserve_amount"] == 0,
		"G2 不同背包還原結果彼此獨立"
	)

	var paint_restored: Dictionary = (
		PlayerProgress.build_restored_inventory(
			{},
			true
		)
	)

	paint_restored["hp_paint"]["current_carry"] = 0

	var initial: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	_check(
		initial["inventory"]["items"]["hp_paint"]["unlocked"]
		== false,
		"G3 顏料相容處理不污染初始資料"
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
			"[PASS] " + description
		)

	else:

		_failed += 1

		push_error(
			"[FAIL] " + description
		)


# ============================================================
# 12. 輸出最終結果
# ============================================================

func _print_result() -> void:

	print("")
	print("========== 測試結果 ==========")

	print(
		"通過項目：",
		_passed
	)

	print(
		"失敗項目：",
		_failed
	)

	if _failed == 0:

		print(
			"========== 全部測試通過 =========="
		)

	else:

		push_error(
			"【PlayerInventoryTest】存在未通過的測試"
		)

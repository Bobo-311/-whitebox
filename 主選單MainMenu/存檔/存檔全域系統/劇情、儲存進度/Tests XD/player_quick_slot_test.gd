extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerQuickSlotTest V1｜快捷欄永久資料驗收
#
# Godot 4.5.1
# STEP 10.7.4
#
# ============================================================
# 測試目的
# ============================================================
#
# 1. 驗證快捷欄管理器初始化
# 2. 驗證舊版存檔相容
# 3. 驗證 A006B 顏料相容
# 4. 驗證自訂快捷欄配置
# 5. 驗證目前選取編號
# 6. 驗證零數量道具保留裝備
# 7. 驗證異常快捷欄資料拒絕
# 8. 驗證資料副本隔離
# 9. 驗證 JSON 轉換及還原
# 10. 驗證 F6 無正式存檔工作階段時的保存保護
#
# ============================================================
# 安全規則
# ============================================================
#
# 本測試不建立正式存檔。
# 不呼叫正式存檔寫入。
# 不修改 DataManager 的運行時玩家資料。
# 不刪除任何 JSON 或備份檔案。
#
# 使用 F6 執行本場景。
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
# 3. 執行完整測試
# ============================================================

func _run_tests() -> void:

	print("")
	print("========== PlayerQuickSlot Test ==========")

	# 必須在沒有正式存檔工作階段時執行。

	if SaveManager.current_slot_id != 0:

		push_error(
			"【快捷欄測試】已有正式存檔工作階段，停止測試"
		)

		return

	if not PlayerProgress.is_initialized():

		_check(
			false,
			"A1 PlayerProgress 初始化完成"
		)

		_print_result()

		return

	# 保存運行時快照。
	# 最後確認測試沒有修改運行中的玩家資料。

	var runtime_before: Dictionary = (
		PlayerProgress.capture_runtime_data()
	)

	var initial: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	var items: Dictionary = (
		initial["inventory"]["items"].duplicate(true)
	)

	# 模擬已完成 A006B 的合法背包。

	var unlocked_items: Dictionary = (
		PlayerProgress.build_restored_inventory(
			{},
			true
		)
	)

	# ========================================================
	# 測試 A：初始化及初始資料
	# ========================================================

	print("")
	print("---------- 測試 A ----------")

	_check(
		PlayerProgress.is_initialized(),
		"A1 PlayerProgress 初始化完成"
	)

	_check(
		initial["equipment"]["quick_slots"].size() == 5,
		"A2 初始快捷欄為五格"
	)

	_check(
		initial["equipment"]["current_slot_index"] == 0,
		"A3 初始快捷欄選取編號為 0"
	)

	_check(
		initial["equipment"]["quick_slots"] == [
			"", "", "", "", ""
		],
		"A4 初始快捷欄沒有其他存檔的道具"
	)

	# ========================================================
	# 測試 B：舊版存檔相容
	# ========================================================

	print("")
	print("---------- 測試 B ----------")

	var legacy_locked: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			{},
			items
		)
	)

	_check(
		not legacy_locked.is_empty(),
		"B1 舊版未解鎖顏料存檔可以還原"
	)

	_check(
		legacy_locked.get("quick_slots", []) == [
			"", "", "", "", ""
		],
		"B2 未解鎖顏料時維持空白快捷欄"
	)

	var legacy_unlocked: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			{},
			unlocked_items
		)
	)

	_check(
		not legacy_unlocked.is_empty(),
		"B3 已完成 A006B 的舊存檔可以還原"
	)

	_check(
		legacy_unlocked.get("quick_slots", []) == [
			"hp_paint", "", "", "", ""
		],
		"B4 舊存檔自動裝備藍色顏料"
	)

	_check(
		legacy_unlocked.get("current_slot_index", -1) == 0,
		"B5 舊存檔正確選取第一格"
	)

	# ========================================================
	# 測試 C：正式快捷欄還原
	# ========================================================

	print("")
	print("---------- 測試 C ----------")

	var saved_equipment: Dictionary = {

		"quick_slots": [
			"hp_paint",
			"potion_gugu",
			"",
			"miracle_apple",
			""
		],

		"current_slot_index": 3
	}

	var restored: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			saved_equipment,
			unlocked_items
		)
	)

	_check(
		not restored.is_empty(),
		"C1 正式快捷欄資料可以還原"
	)

	_check(
		restored.get("quick_slots", []) == (
			saved_equipment["quick_slots"]
		),
		"C2 道具排列及空白位置完整保留"
	)

	_check(
		restored.get("current_slot_index", -1) == 3,
		"C3 正確還原目前選取編號"
	)

	# 玩家主動卸下藍色顏料。

	var unequipped_paint: Dictionary = {

		"quick_slots": [
			"",
			"potion_gugu",
			"",
			"",
			""
		],

		"current_slot_index": 1
	}

	var restored_unequipped: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			unequipped_paint,
			unlocked_items
		)
	)

	_check(
		restored_unequipped.get("quick_slots", []) == (
			unequipped_paint["quick_slots"]
		),
		"C4 不強制重新裝備已卸下的顏料"
	)

	# 模擬玩家選擇空白快捷欄。

	var selected_empty: Dictionary = (
		saved_equipment.duplicate(true)
	)

	selected_empty["current_slot_index"] = 2

	var restored_empty: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			selected_empty,
			unlocked_items
		)
	)

	_check(
		restored_empty.get("current_slot_index", -1) == 2,
		"C5 合法空白欄位選取編號可以還原"
	)

	# ========================================================
	# 測試 D：零數量道具
	# ========================================================

	print("")
	print("---------- 測試 D ----------")

	var empty_stock_items: Dictionary = (
		unlocked_items.duplicate(true)
	)

	empty_stock_items["potion_gugu"]["current_carry"] = 0

	empty_stock_items["potion_gugu"]["reserve_amount"] = 0

	var zero_stock_result: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			saved_equipment,
			empty_stock_items
		)
	)

	_check(
		not zero_stock_result.is_empty(),
		"D1 零數量道具仍允許裝備"
	)

	_check(
		zero_stock_result.get("quick_slots", []) == (
			saved_equipment["quick_slots"]
		),
		"D2 道具用盡後不遺失快捷欄配置"
	)

	# ========================================================
	# 測試 E：異常資料拒絕
	# ========================================================

	print("")
	print("---------- 測試 E ----------")

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			"invalid",
			0,
			items
		),
		"E1 正確拒絕非陣列快捷欄"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", ""],
			0,
			items
		),
		"E2 正確拒絕快捷欄數量不足"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", "", "", "", "", ""],
			0,
			items
		),
		"E3 正確拒絕快捷欄數量過多"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", 123, "", "", ""],
			0,
			items
		),
		"E4 正確拒絕非文字道具 ID"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["invalid_item", "", "", "", ""],
			0,
			items
		),
		"E5 正確拒絕未登記道具"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["eraser", "", "", "", ""],
			0,
			items
		),
		"E6 正確拒絕不存在於背包的道具"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["potion_gugu", "potion_gugu", "", "", ""],
			0,
			items
		),
		"E7 正確拒絕重複裝備道具"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", "", "", "", ""],
			-1,
			items
		),
		"E8 正確拒絕負數選取編號"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", "", "", "", ""],
			5,
			items
		),
		"E9 正確拒絕超出範圍的選取編號"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", "", "", "", ""],
			1.5,
			items
		),
		"E10 正確拒絕小數選取編號"
	)

	_check(
		not PlayerProgress.validate_quick_slot_configuration(
			["", "", "", "", ""],
			"1",
			items
		),
		"E11 正確拒絕文字選取編號"
	)

	_check(
		PlayerProgress.build_restored_quick_slots(
			{"quick_slots": ["", "", "", "", ""]},
			items
		).is_empty(),
		"E12 正確拒絕缺少選取編號的資料"
	)

	_check(
		PlayerProgress.build_restored_quick_slots(
			{"current_slot_index": 0},
			items
		).is_empty(),
		"E13 正確拒絕缺少快捷欄的資料"
	)

	# ========================================================
	# 測試 F：資料副本隔離
	# ========================================================

	print("")
	print("---------- 測試 F ----------")

	var isolated_result: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			saved_equipment,
			unlocked_items
		)
	)

	if not isolated_result.is_empty():

		isolated_result["quick_slots"][1] = ""

	_check(
		saved_equipment["quick_slots"][1] == "potion_gugu",
		"F1 還原副本不污染原始存檔配置"
	)

	var second_result: Dictionary = (
		PlayerProgress.build_restored_quick_slots(
			saved_equipment,
			unlocked_items
		)
	)

	_check(
		second_result.get("quick_slots", []) == (
			saved_equipment["quick_slots"]
		),
		"F2 多次還原不受前一次副本修改影響"
	)

	var initial_after: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	_check(
		initial_after["equipment"]["quick_slots"] == [
			"", "", "", "", ""
		],
		"F3 初始快捷欄資料未受污染"
	)

	# ========================================================
	# 測試 G：JSON 轉換及還原
	# ========================================================

	print("")
	print("---------- 測試 G ----------")

	var json_text: String = (
		JSON.stringify(saved_equipment)
	)

	var parsed: Variant = (
		JSON.parse_string(json_text)
	)

	_check(
		typeof(parsed) == TYPE_DICTIONARY,
		"G1 快捷欄資料可以正常轉換及解析 JSON"
	)

	if typeof(parsed) == TYPE_DICTIONARY:

		var json_restored: Dictionary = (
			PlayerProgress.build_restored_quick_slots(
				parsed,
				unlocked_items
			)
		)

		_check(
			json_restored.get("quick_slots", []) == (
				saved_equipment["quick_slots"]
			),
			"G2 JSON 還原快捷欄配置正確"
		)

		_check(
			json_restored.get("current_slot_index", -1) == 3,
			"G3 JSON 還原選取編號正確"
		)

		_check(
			typeof(
				json_restored.get("current_slot_index")
			) == TYPE_INT,
			"G4 選取編號還原為真正的 int"
		)

	else:

		_check(false, "G2 JSON 還原快捷欄配置正確")

		_check(false, "G3 JSON 還原選取編號正確")

		_check(false, "G4 選取編號還原為真正的 int")

	# ========================================================
	# 測試 H：F6 保存保護及運行時資料隔離
	# ========================================================

	print("")
	print("---------- 測試 H ----------")

	_check(
		not PlayerProgress.can_save_quick_slots(),
		"H1 F6 模式禁止正式保存快捷欄"
	)

	_check(
		PlayerProgress.get_loaded_slot_id() == 0,
		"H2 未建立正式玩家工作階段"
	)

	_check(
		PlayerProgress.capture_runtime_data() == runtime_before,
		"H3 測試未修改運行時玩家資料"
	)

	# ========================================================
	# 全部測試完成
	# ========================================================

	_print_result()


# ============================================================
# 4. 單項測試結果
# ============================================================

func _check(
	condition: bool,
	message: String
) -> void:

	if condition:

		_passed += 1

		print("[PASS] " + message)

	else:

		_failed += 1

		push_error("[FAIL] " + message)


# ============================================================
# 5. 統一測試結果
# ============================================================

func _print_result() -> void:

	print("")
	print("========== 測試結果 ==========")

	print("通過項目：", _passed)

	print("失敗項目：", _failed)

	if _failed == 0 and _passed > 0:

		print(
			"========== 全部測試通過 =========="
		)

	else:

		print(
			"========== 測試未通過 =========="
		)

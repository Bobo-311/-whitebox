
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# WorldProgress Test V1｜世界永久資料核心驗收
# Godot 4.5.1
# STEP 10.8.4
# ============================================================
# 執行方式：
# 開啟 world_progress_test.tscn 後按 F6。
#
# 測試原則：
# - 不建立正式存檔。
# - 不修改正式 JSON。
# - 不刪除任何檔案。
# - 不實例化遊戲地圖。
# - 不觸發正式劇情。
# - 不登記真實 Boss 或地圖進度。
#
# 測試使用獨立 Dictionary 模擬世界資料。
# ============================================================

# ============================================================
# 1. 測試統計
# ============================================================

var _passed_count: int = 0
var _failed_count: int = 0

# ============================================================
# 2. 執行所有測試
# ============================================================

func _ready() -> void:
	if not OS.is_debug_build():
		return

	call_deferred("_run_tests")

func _run_tests() -> void:
	print("")
	print("========== WorldProgress Test V1 ==========")

	# 防止在正式遊戲工作階段執行獨立測試。
	if SaveManager.current_slot_id != 0:
		push_error(
			"【WorldProgressTest】目前已有正式存檔工作階段，停止測試"
		)
		return

	_test_initial_data()
	_test_world_ids()
	_test_world_validation()
	_test_restore_data()
	_test_candidate_merge()
	_test_session_protection()

	_print_result()

# ============================================================
# 3. 測試 A｜初始世界資料
# 預期：4 項
# ============================================================

func _test_initial_data() -> void:
	print("")
	print("---------- 測試 A：初始世界資料 ----------")

	var data: Dictionary = (
		WorldProgress.build_initial_world_data()
	)

	_check(
		data.size() == 3,
		"A1 初始世界具有三種管理欄位"
	)

	_check(
		data.get("defeated_bosses", null) == {},
		"A2 初始 Boss 紀錄為空"
	)

	_check(
		data.get("opened_shortcuts", null) == {},
		"A3 初始捷徑紀錄為空"
	)

	_check(
		data.get("collected_unique_items", null) == {},
		"A4 初始唯一性道具紀錄為空"
	)

# ============================================================
# 4. 測試 B｜世界 ID 格式
# 預期：8 項
# ============================================================

func _test_world_ids() -> void:
	print("")
	print("---------- 測試 B：世界 ID 格式 ----------")

	_check(
		WorldProgress.is_valid_world_id("boss_test_01"),
		"B1 接受合法 Boss ID"
	)

	_check(
		WorldProgress.is_valid_world_id("garden_shortcut_01"),
		"B2 接受合法捷徑 ID"
	)

	_check(
		not WorldProgress.is_valid_world_id(""),
		"B3 拒絕空白 ID"
	)

	_check(
		not WorldProgress.is_valid_world_id("Boss_Test"),
		"B4 拒絕不符合命名規格的大寫 ID"
	)

	_check(
		not WorldProgress.is_valid_world_id("01_boss"),
		"B5 拒絕以數字開頭的 ID"
	)

	_check(
		not WorldProgress.is_valid_world_id("boss test"),
		"B6 拒絕包含空格的 ID"
	)

	_check(
		not WorldProgress.is_valid_world_id(123),
		"B7 拒絕非字串 ID"
	)

	_check(
		not WorldProgress.is_valid_world_id("a".repeat(97)),
		"B8 拒絕超長 ID"
	)

# ============================================================
# 5. 測試 C｜世界資料格式
# 預期：7 項
# ============================================================

func _test_world_validation() -> void:
	print("")
	print("---------- 測試 C：世界資料格式 ----------")

	_check(
		WorldProgress.validate_world_data({}),
		"C1 相容舊版空白世界資料"
	)

	_check(
		WorldProgress.validate_world_data({
			"defeated_bosses": {
				"boss_test_01": true
			}
		}),
		"C2 接受合法永久完成紀錄"
	)

	_check(
		not WorldProgress.validate_world_data([]),
		"C3 拒絕非 Dictionary 世界資料"
	)

	_check(
		not WorldProgress.validate_world_data({
			"defeated_bosses": []
		}),
		"C4 拒絕錯誤欄位類型"
	)

	_check(
		not WorldProgress.validate_world_data({
			"opened_shortcuts": {
				"invalid id": true
			}
		}),
		"C5 拒絕無效狀態 ID"
	)

	_check(
		not WorldProgress.validate_world_data({
			"collected_unique_items": {
				"item_test": 1
			}
		}),
		"C6 拒絕非布林狀態值"
	)

	_check(
		not WorldProgress.validate_world_data({
			"defeated_bosses": {
				"boss_test_01": false
			}
		}),
		"C7 拒絕不符合稀疏保存規格的 false 紀錄"
	)

# ============================================================
# 6. 測試 D｜世界資料還原與副本保護
# 預期：5 項
# ============================================================

func _test_restore_data() -> void:
	print("")
	print("---------- 測試 D：世界資料還原 ----------")

	var source: Dictionary = {
		"defeated_bosses": {
			"boss_test_01": true
		},
		"opened_shortcuts": {
			"shortcut_test_01": true
		},
		"completed_cutscenes": ["A001"]
	}

	var restored: Dictionary = (
		WorldProgress.build_restored_world_data(source)
	)

	_check(
		restored.size() == 3,
		"D1 還原完整三種世界管理欄位"
	)

	_check(
		restored.get("defeated_bosses", {}).has("boss_test_01"),
		"D2 已擊敗 Boss 正確還原"
	)

	_check(
		restored.get("opened_shortcuts", {}).has("shortcut_test_01"),
		"D3 已開啟捷徑正確還原"
	)

	_check(
		not restored.has("completed_cutscenes"),
		"D4 不接管其他管理器的劇情資料"
	)

	restored["defeated_bosses"]["boss_test_02"] = true

	_check(
		not source["defeated_bosses"].has("boss_test_02"),
		"D5 修改還原副本不污染原始資料"
	)

# ============================================================
# 7. 測試 E｜正式候選資料整合
# 預期：8 項
# ============================================================

func _test_candidate_merge() -> void:
	print("")
	print("---------- 測試 E：候選資料整合 ----------")

	var existing: Dictionary = {
		"defeated_bosses": {
			"boss_test_01": true
		},
		"opened_shortcuts": {},
		"collected_unique_items": {},
		"completed_cutscenes": ["A001", "A005"],
		"quest_states": {
			"quest_test": 2
		},
		"npc_flags": {
			"npc_test": true
		},
		"other_future_data": {
			"test_value": 10
		}
	}

	var runtime: Dictionary = (
		WorldProgress.build_initial_world_data()
	)

	runtime["defeated_bosses"]["boss_test_01"] = true
	runtime["defeated_bosses"]["boss_test_02"] = true
	runtime["opened_shortcuts"]["shortcut_test_01"] = true
	runtime["collected_unique_items"]["item_test_01"] = true

	var merged: Dictionary = (
		WorldProgress.build_merged_world_data(existing, runtime)
	)

	_check(
		merged.get("defeated_bosses", {}).size() == 2,
		"E1 正確整合新舊 Boss 紀錄"
	)

	_check(
		merged.get("opened_shortcuts", {}).has("shortcut_test_01"),
		"E2 正確整合捷徑紀錄"
	)

	_check(
		merged.get("collected_unique_items", {}).has("item_test_01"),
		"E3 正確整合唯一性道具紀錄"
	)

	_check(
		merged.get("completed_cutscenes", []) == ["A001", "A005"],
		"E4 保留原本劇情紀錄"
	)

	_check(
		merged.get("quest_states", {}) == existing["quest_states"],
		"E5 保留原本任務資料"
	)

	_check(
		merged.get("npc_flags", {}) == existing["npc_flags"],
		"E6 保留原本 NPC 資料"
	)

	_check(
		merged.get("other_future_data", {}) == existing["other_future_data"],
		"E7 保留其他未知世界欄位"
	)

	# 模擬已保存 Boss 紀錄遭到意外移除。
	runtime["defeated_bosses"].erase("boss_test_01")

	var invalid_merge: Dictionary = (
		WorldProgress.build_merged_world_data(existing, runtime)
	)

	_check(
		invalid_merge.is_empty(),
		"E8 拒絕移除已完成的永久紀錄"
	)

# ============================================================
# 8. 測試 F｜工作階段保護
# 預期：5 項
# ============================================================

func _test_session_protection() -> void:
	print("")
	print("---------- 測試 F：工作階段保護 ----------")

	_check(
		WorldProgress.is_initialized(),
		"F1 WorldProgress 已正常初始化"
	)

	_check(
		WorldProgress.get_loaded_slot_id() == 0,
		"F2 初始沒有正式世界工作階段"
	)

	_check(
		not WorldProgress.can_save_world(),
		"F3 未讀檔時禁止正式世界保存"
	)

	_check(
		not WorldProgress.is_boss_defeated("boss_test_01"),
		"F4 獨立資料測試未污染正式運行時狀態"
	)

	_check(
		WorldProgress.capture_runtime_world().is_empty(),
		"F5 未建立工作階段時不提供舊世界資料"
	)

# ============================================================
# 9. 統一驗收紀錄
# ============================================================

func _check(
	condition: bool,
	description: String
) -> void:
	if condition:
		_passed_count += 1
		print("[PASS] " + description)
	else:
		_failed_count += 1
		print("[FAIL] " + description)

# ============================================================
# 10. 最終驗收結果
# ============================================================

func _print_result() -> void:
	print("")
	print("========== WorldProgress Test Result ==========")
	print("通過項目：", _passed_count)
	print("失敗項目：", _failed_count)

	if _failed_count == 0 and _passed_count == 37:
		print("========== 全部測試通過 ==========")
		print("【WorldProgressTest】本次測試未寫入正式 JSON")
	else:
		push_error(
			"【WorldProgressTest】世界永久資料核心驗收失敗"
		)

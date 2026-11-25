extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerEquippedStickersTest V1
# Godot 4.5.1
# STEP 10.7.6
# ============================================================
# 測試範圍：
# A. 系統初始化：4 項
# B. 舊版存檔相容：4 項
# C. 合法貼紙裝備還原：4 項
# D. 異常裝備資料拒絕：12 項
# E. 資料副本隔離：4 項
# F. JSON 序列化及還原：4 項
# G. F6 正式存檔保護：3 項
#
# 合計：35 項
# 不修改正式存檔及玩家運行時裝備。
# ============================================================

var _passed: int = 0
var _failed: int = 0

# ============================================================
# 1. 啟動測試
# ============================================================
func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("")
	print("========== PlayerEquippedStickers Test ==========")

	if SaveManager.current_slot_id != 0:
		push_error("【測試】存在正式存檔工作階段，停止測試")
		return

	_test_initialization()

	if not PlayerProgress.is_initialized():
		_print_result()
		return

	_test_legacy_save()
	_test_valid_equipment()
	_test_invalid_equipment()
	_test_isolation()
	_test_json()
	_test_save_protection()
	_print_result()

# ============================================================
# 2. 測試 A：系統初始化（4 項）
# ============================================================
func _test_initialization() -> void:
	print("")
	print("---------- 測試 A：系統初始化 ----------")

	_check(
		PlayerProgress.is_initialized(),
		"A1 PlayerProgress 初始化成功"
	)
	_check(
		PlayerProgress.get_loaded_slot_id() == 0,
		"A2 F6 尚未建立正式工作階段"
	)

	if not PlayerProgress.is_initialized():
		return

	var initial: Dictionary = PlayerProgress.get_initial_player_data()

	_check(
		initial["equipment"]["equipped_stickers"] == ["", "", "", ""],
		"A3 初始裝備為四格空白"
	)
	_check(
		PlayerProgress.validate_player_data(initial),
		"A4 初始玩家資料合法"
	)

# ============================================================
# 3. 測試 B：舊版存檔相容（4 項）
# ============================================================
func _test_legacy_save() -> void:
	print("")
	print("---------- 測試 B：舊版存檔 ----------")

	var legacy: Dictionary = {}
	var restored_empty: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		legacy, []
	)

	_check(
		restored_empty.get("equipped_stickers", []) == ["", "", "", ""],
		"B1 舊版空白收藏正確還原"
	)

	var restored_owned: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		legacy, ["001", "004", "006"]
	)

	_check(
		restored_owned.get("equipped_stickers", []) == ["", "", "", ""],
		"B2 擁有貼紙但沒有裝備資料時保持未裝備"
	)

	var explicit_empty: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		{"equipped_stickers": ["", "", "", ""]},
		["001", "004"]
	)

	_check(
		explicit_empty.get("equipped_stickers", []) == ["", "", "", ""],
		"B3 正式保存的空白裝備正確還原"
	)
	_check(
		legacy.is_empty(),
		"B4 舊版原始資料未遭修改"
	)

# ============================================================
# 4. 測試 C：合法裝備（4 項）
# ============================================================
func _test_valid_equipment() -> void:
	print("")
	print("---------- 測試 C：合法裝備 ----------")

	_check(
		PlayerProgress.validate_equipped_stickers(
			["", "", "", ""], []
		),
		"C1 接受四格空白裝備"
	)
	_check(
		PlayerProgress.validate_equipped_stickers(
			["001", "", "004", "006"],
			["001", "004", "006"]
		),
		"C2 接受包含空白格的合法裝備"
	)

	var restored: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		{"equipped_stickers": ["001", "", "004", "006"]},
		["001", "004", "006"]
	)

	_check(
		restored.get("equipped_stickers", []) == ["001", "", "004", "006"],
		"C3 裝備位置及空白格完整保留"
	)
	_check(
		PlayerProgress.validate_equipped_stickers(
			["001", "004", "006", "008"],
			["001", "004", "006", "008"]
		),
		"C4 接受四格全部裝滿"
	)

# ============================================================
# 5. 測試 D：異常裝備資料（12 項）
# ============================================================
func _test_invalid_equipment() -> void:
	print("")
	print("---------- 測試 D：異常資料 ----------")

	var owned: Array[String] = ["001", "004", "006"]

	_check(
		not PlayerProgress.validate_equipped_stickers("001", owned),
		"D1 拒絕文字型裝備資料"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers({"slot": "001"}, owned),
		"D2 拒絕 Dictionary 型裝備"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(null, owned),
		"D3 拒絕 null 裝備資料"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(["001", "", ""], owned),
		"D4 拒絕少於四格"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(["001", "", "", "", ""], owned),
		"D5 拒絕超過四格"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers([1, "", "", ""], owned),
		"D6 拒絕數字型貼紙 ID"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers([" ", "", "", ""], owned),
		"D7 拒絕無效空格 ID"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(
			["__invalid_sticker__", "", "", ""], owned
		),
		"D8 拒絕未登記貼紙"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(["008", "", "", ""], owned),
		"D9 拒絕裝備尚未取得的貼紙"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(
			["001", "", "001", ""], owned
		),
		"D10 拒絕重複裝備相同貼紙"
	)
	_check(
		not PlayerProgress.validate_equipped_stickers(
			["001", "", "", ""], "001"
		),
		"D11 拒絕異常貼紙所有權資料"
	)

	var invalid: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		{"equipped_stickers": ["001", "001", "", ""]},
		owned
	)

	_check(
		invalid.is_empty(),
		"D12 異常裝備資料不可還原"
	)

# ============================================================
# 6. 測試 E：資料隔離（4 項）
# ============================================================
func _test_isolation() -> void:
	print("")
	print("---------- 測試 E：資料隔離 ----------")

	var runtime_before: Array[String] = DataManager.equipped_stickers.duplicate()
	var original: Dictionary = {
		"equipped_stickers": ["001", "", "004", ""]
	}

	var restored: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		original, ["001", "004", "006"]
	)

	if restored.is_empty():
		_check(false, "E1 無法建立隔離測試資料")
		return

	restored["equipped_stickers"][0] = "006"

	_check(
		original["equipped_stickers"] == ["001", "", "004", ""],
		"E1 還原副本不污染原始存檔"
	)
	_check(
		DataManager.equipped_stickers == runtime_before,
		"E2 純資料還原不修改運行時裝備"
	)

	var initial_copy: Dictionary = PlayerProgress.get_initial_player_data()
	initial_copy["equipment"]["equipped_stickers"][0] = "001"

	var new_initial: Dictionary = PlayerProgress.get_initial_player_data()

	_check(
		new_initial["equipment"]["equipped_stickers"] == ["", "", "", ""],
		"E3 初始裝備不受外部修改"
	)

	var first: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		{"equipped_stickers": ["001", "", "", ""]}, ["001"]
	)
	var second: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		{"equipped_stickers": ["", "004", "", ""]}, ["004"]
	)

	_check(
		first.get("equipped_stickers", []) == ["001", "", "", ""]
		and second.get("equipped_stickers", []) == ["", "004", "", ""],
		"E4 不同裝備還原資料彼此獨立"
	)

# ============================================================
# 7. 測試 F：JSON 資料轉換（4 項）
# ============================================================
func _test_json() -> void:
	print("")
	print("---------- 測試 F：JSON ----------")

	var player_data: Dictionary = PlayerProgress.get_initial_player_data()
	player_data["inventory"]["owned_stickers"] = ["001", "004", "006"]
	player_data["equipment"]["equipped_stickers"] = ["001", "", "004", "006"]

	_check(
		PlayerProgress.validate_player_data(player_data),
		"F1 完整玩家裝備資料合法"
	)

	var json_text: String = JSON.stringify(player_data)
	var parsed: Variant = JSON.parse_string(json_text)

	_check(
		typeof(parsed) == TYPE_DICTIONARY,
		"F2 JSON 正確轉換及解析"
	)

	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var restored_player: Dictionary = parsed

	_check(
		PlayerProgress.validate_player_data(restored_player),
		"F3 JSON 還原後完整資料合法"
	)

	var restored: Dictionary = PlayerProgress.build_restored_equipped_stickers(
		restored_player["equipment"],
		restored_player["inventory"]["owned_stickers"]
	)

	_check(
		restored.get("equipped_stickers", []) == ["001", "", "004", "006"],
		"F4 JSON 完整保留貼紙位置及空白格"
	)

# ============================================================
# 8. 測試 G：F6 正式存檔保護（3 項）
# ============================================================
func _test_save_protection() -> void:
	print("")
	print("---------- 測試 G：存檔保護 ----------")

	_check(
		not PlayerProgress.can_save_equipped_stickers(),
		"G1 F6 不允許正式保存貼紙裝備"
	)

	var fake_candidate: Dictionary = {
		"slot_id": 2,
		"player": PlayerProgress.get_initial_player_data()
	}
	var before: Dictionary = fake_candidate.duplicate(true)

	_check(
		not PlayerProgress.append_equipped_stickers_to_candidate(fake_candidate),
		"G2 拒絕無正式工作階段的裝備保存"
	)
	_check(
		fake_candidate == before,
		"G3 被拒絕的候選資料保持不變"
	)

# ============================================================
# 9. 統一測試判斷
# ============================================================
func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("【PASS】" + description)
	else:
		_failed += 1
		push_error("【FAIL】" + description)

# ============================================================
# 10. 輸出最終測試結果
# ============================================================
func _print_result() -> void:
	print("")
	print("========== 測試結果 ==========")
	print("通過項目：", _passed)
	print("失敗項目：", _failed)

	if _failed == 0 and _passed == 35:
		print("========== 全部測試通過 ==========")
	else:
		print("========== 測試失敗或測試數量不完整 ==========")

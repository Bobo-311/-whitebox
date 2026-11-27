extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerOwnedStickersTest V1
# 玩家已取得貼紙獨立測試
#
# Godot 4.5.1
# STEP 10.7.5
#
# ============================================================
# 測試範圍
# ============================================================
#
# A. 系統初始化
# B. 初始貼紙資料
# C. 舊版存檔相容
# D. 正常貼紙還原
# E. 異常貼紙資料拒絕
# F. 原始資料隔離
# G. JSON 轉換及商店交易資料結構
# H. F6 正式存檔保護
#
# 本測試不建立、刪除或修改正式存檔。
# 不執行真實商店交易。
# ============================================================


# ============================================================
# 1. 測試統計
# ============================================================

var _passed: int = 0

var _failed: int = 0


# ============================================================
# 2. 開始測試
# ============================================================

func _ready() -> void:

	print("")
	print("========== PlayerOwnedStickers Test ==========")

	# 確保本場景不在正式存檔工作階段執行。

	if SaveManager.current_slot_id != 0:

		push_error(
			"【測試】目前存在正式存檔，停止獨立測試"
		)

		return

	_test_initialization()

	if not PlayerProgress.is_initialized():

		_print_result()

		return

	_test_initial_data()

	_test_legacy_save()

	_test_valid_stickers()

	_test_invalid_stickers()

	_test_data_isolation()

	_test_json_and_shop_data()

	_test_save_protection()

	_print_result()


# ============================================================
# 3. 測試 A：系統初始化
# ============================================================

func _test_initialization() -> void:

	print("")
	print("---------- 測試 A ----------")

	_check(
		PlayerProgress.is_initialized(),
		"A1 PlayerProgress 初始化完成"
	)

	_check(
		PlayerProgress.get_loaded_slot_id() == 0,
		"A2 尚未建立正式玩家工作階段"
	)

	_check(
		DataManager.STICKER_DB.has("001"),
		"A3 愛心貼紙已正式登記"
	)

	_check(
		DataManager.STICKER_DB.has("004"),
		"A4 魔法棒貼紙已正式登記"
	)


# ============================================================
# 4. 測試 B：初始貼紙資料
# ============================================================

func _test_initial_data() -> void:

	print("")
	print("---------- 測試 B ----------")

	var initial: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	var inventory: Dictionary = initial.get(
		"inventory",
		{}
	)

	var equipment: Dictionary = initial.get(
		"equipment",
		{}
	)

	_check(
		inventory.has("owned_stickers"),
		"B1 初始貼紙收藏欄位存在"
	)

	_check(
		inventory.get("owned_stickers", ["error"]).is_empty(),
		"B2 初始尚未取得任何貼紙"
	)

	_check(
		equipment.get("equipped_stickers", []).size() == 4,
		"B3 初始貼紙裝備欄為四格"
	)

	_check(
		PlayerProgress.validate_player_data(initial),
		"B4 初始玩家資料通過完整驗證"
	)


# ============================================================
# 5. 測試 C：舊版存檔相容
# ============================================================

func _test_legacy_save() -> void:

	print("")
	print("---------- 測試 C ----------")

	var legacy_inventory: Dictionary = {}

	var restored: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			legacy_inventory
		)
	)

	_check(
		not restored.is_empty(),
		"C1 舊版存檔可正常建立貼紙資料"
	)

	_check(
		restored.has("owned_stickers"),
		"C2 舊版存檔正確補足貼紙欄位"
	)

	_check(
		restored.get("owned_stickers", ["error"]).is_empty(),
		"C3 舊版存檔使用初始空白收藏"
	)

	_check(
		legacy_inventory.is_empty(),
		"C4 舊版原始資料未受到修改"
	)


# ============================================================
# 6. 測試 D：正常貼紙還原
# ============================================================

func _test_valid_stickers() -> void:

	print("")
	print("---------- 測試 D ----------")

	_check(
		PlayerProgress.validate_owned_stickers([]),
		"D1 正確接受空白貼紙收藏"
	)

	_check(
		PlayerProgress.validate_owned_stickers(["001"]),
		"D2 正確接受單張貼紙"
	)

	_check(
		PlayerProgress.validate_owned_stickers(
			["001", "004", "006"]
		),
		"D3 正確接受多張貼紙"
	)

	var saved_inventory: Dictionary = {

		"owned_stickers": [
			"001",
			"004",
			"016"
		]
	}

	var restored: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			saved_inventory
		)
	)

	_check(
		not restored.is_empty(),
		"D4 正式貼紙資料可正常還原"
	)

	_check(
		restored.get("owned_stickers", []) == [
			"001",
			"004",
			"016"
		],
		"D5 所有貼紙 ID 及順序正確保留"
	)

	var empty_restored: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			{"owned_stickers": []}
		)
	)

	_check(
		not empty_restored.is_empty()
		and empty_restored.get(
			"owned_stickers",
			["error"]
		).is_empty(),
		"D6 正確區分合法空白收藏與還原失敗"
	)


# ============================================================
# 7. 測試 E：異常貼紙資料拒絕
# ============================================================

func _test_invalid_stickers() -> void:

	print("")
	print("---------- 測試 E ----------")

	_check(
		not PlayerProgress.validate_owned_stickers(
			"001"
		),
		"E1 正確拒絕文字型貼紙收藏"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			{"001": true}
		),
		"E2 正確拒絕 Dictionary 型收藏"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			[1]
		),
		"E3 正確拒絕數字型貼紙 ID"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			[""]
		),
		"E4 正確拒絕空白貼紙 ID"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			[" "]
		),
		"E5 正確拒絕空格貼紙 ID"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			["__invalid_sticker__"]
		),
		"E6 正確拒絕未登記貼紙"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			["001", "001"]
		),
		"E7 正確拒絕重複貼紙"
	)

	_check(
		not PlayerProgress.validate_owned_stickers(
			[null]
		),
		"E8 正確拒絕 null 貼紙 ID"
	)

	var invalid: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			{"owned_stickers": ["001", "001"]}
		)
	)

	_check(
		invalid.is_empty(),
		"E9 異常正式貼紙資料不可還原"
	)


# ============================================================
# 8. 測試 F：原始資料隔離
# ============================================================

func _test_data_isolation() -> void:

	print("")
	print("---------- 測試 F ----------")

	var original: Dictionary = {
		"owned_stickers": ["001", "004"]
	}

	var runtime_before: Array[String] = (
		DataManager.owned_stickers.duplicate()
	)

	var restored: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			original
		)
	)

	if restored.is_empty():

		_check(
			false,
			"F1 無法建立隔離測試資料"
		)

		return

	var restored_owned: Array = (
		restored["owned_stickers"]
	)

	restored_owned.append("006")

	_check(
		original["owned_stickers"] == ["001", "004"],
		"F1 還原副本不污染原始存檔資料"
	)

	var initial_copy: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	initial_copy["inventory"]["owned_stickers"].append(
		"001"
	)

	var new_initial: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	_check(
		new_initial["inventory"]["owned_stickers"].is_empty(),
		"F2 初始收藏不受外部修改"
	)

	_check(
		DataManager.owned_stickers == runtime_before,
		"F3 純資料還原不污染運行時貼紙"
	)

	var first_restore: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			{"owned_stickers": ["001"]}
		)
	)

	var second_restore: Dictionary = (
		PlayerProgress.build_restored_owned_stickers(
			{"owned_stickers": ["004"]}
		)
	)

	_check(
		first_restore.get("owned_stickers", []) == ["001"]
		and second_restore.get("owned_stickers", []) == ["004"],
		"F4 兩份貼紙還原資料彼此獨立"
	)


# ============================================================
# 9. 測試 G：JSON 與商店交易資料結構
#
# 僅模擬購買成功後的玩家資料。
# 不實際扣除 DataManager 金幣。
#
# 測試用售價不是正式商店定價。
# ============================================================

func _test_json_and_shop_data() -> void:

	print("")
	print("---------- 測試 G ----------")

	var player_data: Dictionary = (
		PlayerProgress.get_initial_player_data()
	)

	# 模擬商店購買後：
	# 玩家原本有 100 金幣，
	# 花費 30 金幣取得愛心貼紙。

	player_data["stats"]["total_gold"] = 70

	player_data["inventory"]["owned_stickers"] = [
		"001"
	]

	_check(
		PlayerProgress.validate_player_data(
			player_data
		),
		"G1 模擬商店購買後的玩家資料合法"
	)

	var json_text: String = (
		JSON.stringify(player_data)
	)

	var parsed: Variant = (
		JSON.parse_string(json_text)
	)

	_check(
		typeof(parsed) == TYPE_DICTIONARY,
		"G2 玩家資料可正常轉換及解析 JSON"
	)

	if typeof(parsed) != TYPE_DICTIONARY:

		return

	var restored_player: Dictionary = parsed

	_check(
		PlayerProgress.validate_player_data(
			restored_player
		),
		"G3 JSON 還原資料通過完整驗證"
	)

	_check(
		int(
			restored_player["stats"]["total_gold"]
		) == 70,
		"G4 購買後剩餘金幣正確"
	)

	_check(
		restored_player["inventory"]["owned_stickers"]
		== ["001"],
		"G5 購買取得的貼紙正確"
	)

	_check(
		restored_player["equipment"]["quick_slots"].size() == 5,
		"G6 原有快捷欄資料完整保留"
	)

	_check(
		restored_player["inventory"].has("items"),
		"G7 原有背包資料完整保留"
	)

	_check(
		restored_player["equipment"]["equipped_stickers"].size()
		== 4,
		"G8 貼紙裝備保留欄位完整"
	)


# ============================================================
# 10. 測試 H：F6 存檔保護
#
# 沒有正式工作階段時，
# 不允許將貼紙資料加入正式存檔。
# ============================================================

func _test_save_protection() -> void:

	print("")
	print("---------- 測試 H ----------")

	_check(
		not PlayerProgress.can_save_owned_stickers(),
		"H1 F6 不允許正式保存貼紙"
	)

	var fake_candidate: Dictionary = {

		"slot_id": 2,

		"player": PlayerProgress.get_initial_player_data()
	}

	var before: Dictionary = fake_candidate.duplicate(true)

	_check(
		not PlayerProgress.append_owned_stickers_to_candidate(
			fake_candidate
		),
		"H2 F6 不允許加入正式貼紙資料"
	)

	_check(
		fake_candidate == before,
		"H3 被拒絕的候選資料未受到修改"
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
			"【PASS】" + description
		)

	else:

		_failed += 1

		push_error(
			"【FAIL】" + description
		)


# ============================================================
# 12. 輸出最終結果
# ============================================================

func _print_result() -> void:

	print("")
	print("========== 測試結果 ==========")

	print("通過項目：", _passed)

	print("失敗項目：", _failed)

	if _failed == 0:

		print("========== 全部測試通過 ==========")

	else:

		print("========== 存在測試失敗 ==========")

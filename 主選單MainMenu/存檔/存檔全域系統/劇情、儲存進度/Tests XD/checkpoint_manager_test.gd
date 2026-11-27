
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# CheckpointManager V1｜獨立驗收測試
#
# 執行方式：
# 開啟 checkpoint_manager_test.tscn，按下 F6。
#
# 測試原則：
# - 不建立存檔
# - 不刪除存檔
# - 不修改存檔
# - 不實例化遊戲地圖
# - 不觸發任何遊戲劇情
#
# 只驗證地圖、畫架及定位點的對應關係。
# ============================================================


# ============================================================
# 1. 測試結果統計
# ============================================================

var _passed_count: int = 0

var _failed_count: int = 0


# ============================================================
# 2. 自動執行所有測試
# ============================================================

func _ready() -> void:

	# 防止正式發行版本執行開發測試。
	if not OS.is_debug_build():

		return

	print("")
	print("========== CheckpointManager Test ==========")

	_test_initial_checkpoint()

	_test_am002_checkpoint()

	_test_invalid_checkpoint()

	_test_scene_markers()

	_test_data_protection()

	_print_result()


# ============================================================
# 3. 測試 A｜新遊戲初始出生點
#
# 確認舊存檔仍可解析到 AM001，
# 而不是被錯誤導向 AM002 畫架。
# ============================================================

func _test_initial_checkpoint() -> void:

	print("")
	print("---------- 測試 A ----------")

	var data: Dictionary = (
		CheckpointManager.get_initial_checkpoint()
	)

	_check(
		not data.is_empty(),
		"A1 初始出生點資料存在"
	)

	_check(
		data.get("scene_path", "")
		== "res://Maps/AM001.tscn",
		"A2 初始地圖正確對應 AM001"
	)

	_check(
		data.get("spawn_name", "")
		== "NewGameSpawnPoint",
		"A3 初始出生點名稱正確"
	)

	_check(
		data.get("is_initial", false) == true,
		"A4 初始出生點識別正確"
	)


# ============================================================
# 4. 測試 B｜AM002 正式畫架
# ============================================================

func _test_am002_checkpoint() -> void:

	print("")
	print("---------- 測試 B ----------")

	var data: Dictionary = (
		CheckpointManager.resolve_checkpoint(
			"am002",
			"easel_am002_01"
		)
	)

	_check(
		not data.is_empty(),
		"B1 AM002 畫架資料存在"
	)

	_check(
		data.get("scene_path", "")
		== "res://Maps/AM002.tscn",
		"B2 畫架正確對應 AM002"
	)

	_check(
		data.get("spawn_name", "")
		== "CheckpointSpawn_AM002_01",
		"B3 畫架出生點名稱正確"
	)

	_check(
		data.get("is_initial", true) == false,
		"B4 正式畫架與初始出生點正確區分"
	)


# ============================================================
# 5. 測試 C｜無效資料防護
#
# 未登記的地圖或畫架不可偷偷回傳初始位置。
# ============================================================

func _test_invalid_checkpoint() -> void:

	print("")
	print("---------- 測試 C ----------")

	_check(
		CheckpointManager.resolve_map_scene(
			"unknown_map"
		).is_empty(),
		"C1 正確拒絕未知地圖"
	)

	_check(
		CheckpointManager.resolve_checkpoint(
			"am002",
			"unknown_easel"
		).is_empty(),
		"C2 正確拒絕未知畫架"
	)

	_check(
		CheckpointManager.resolve_checkpoint(
			"first_land_sakura_garden",
			"easel_am002_01"
		).is_empty(),
		"C3 正確拒絕跨地圖錯誤畫架"
	)


# ============================================================
# 6. 測試 D｜實際場景資源與定位點
#
# 透過 PackedScene.get_state() 檢查場景資料。
#
# 不使用 instantiate()，
# 因此不會執行地圖及玩家的 _ready()。
# ============================================================

func _test_scene_markers() -> void:

	print("")
	print("---------- 測試 D ----------")

	_check(
		CheckpointManager.validate_checkpoint(
			"first_land_sakura_garden",
			"easel_start_01"
		),
		"D1 AM001 場景資源有效"
	)

	_check(
		CheckpointManager.validate_checkpoint(
			"am002",
			"easel_am002_01"
		),
		"D2 AM002 場景資源有效"
	)

	_check(
		_scene_has_unique_marker(
			"res://Maps/AM001.tscn",
			"NewGameSpawnPoint"
		),
		"D3 AM001 初始 Marker2D 存在且唯一"
	)

	_check(
		_scene_has_unique_marker(
			"res://Maps/AM002.tscn",
			"CheckpointSpawn_AM002_01"
		),
		"D4 AM002 畫架 Marker2D 存在且唯一"
	)


# ============================================================
# 7. 檢查場景中的 Marker2D
#
# 本測試檢查直接儲存在目標場景內的節點。
# 不展開巢狀子場景。
#
# 必須同時符合：
# - 節點名稱正確
# - 節點類型為 Marker2D
# - 不存在重複名稱
# ============================================================

func _scene_has_unique_marker(
	scene_path: String,
	marker_name: String
) -> bool:

	if not ResourceLoader.exists(
		scene_path,
		"PackedScene"
	):

		return false

	var packed: PackedScene = (
		load(scene_path) as PackedScene
	)

	if packed == null:

		return false

	var scene_state: SceneState = (
		packed.get_state()
	)

	var name_count: int = 0

	var marker_count: int = 0

	for index in range(
		scene_state.get_node_count()
	):

		if (
			String(scene_state.get_node_name(index))
			!= marker_name
		):

			continue

		name_count += 1

		if (
			scene_state.get_node_type(index)
			== &"Marker2D"
		):

			marker_count += 1

	return (
		name_count == 1
		and marker_count == 1
	)


# ============================================================
# 8. 測試 E｜資料保護
#
# 外部修改查詢結果時，
# 不應污染 CheckpointManager 的原始資料。
# ============================================================

func _test_data_protection() -> void:

	print("")
	print("---------- 測試 E ----------")

	var data: Dictionary = (
		CheckpointManager.resolve_checkpoint(
			"am002",
			"easel_am002_01"
		)
	)

	# 故意修改本地取得的副本。
	data["spawn_name"] = "Invalid_Test_Spawn"

	# 重新查詢管理器的正式資料。
	var fresh_data: Dictionary = (
		CheckpointManager.resolve_checkpoint(
			"am002",
			"easel_am002_01"
		)
	)

	_check(
		fresh_data.get("spawn_name", "")
		== "CheckpointSpawn_AM002_01",
		"E1 外部修改不會污染正式定位資料"
	)


# ============================================================
# 9. 統一測試輸出
# ============================================================

func _check(
	condition: bool,
	description: String
) -> void:

	if condition:

		_passed_count += 1

		print(
			"[PASS] " + description
		)

	else:

		_failed_count += 1

		print(
			"[FAIL] " + description
		)


# ============================================================
# 10. 顯示最終驗收結果
# ============================================================

func _print_result() -> void:

	print("")
	print("========== 測試結果 ==========")

	print(
		"通過項目：",
		_passed_count
	)

	print(
		"失敗項目：",
		_failed_count
	)

	if _failed_count == 0:

		print(
			"========== 全部測試通過 =========="
		)

	else:

		push_error(
			"【CheckpointManagerTest】存在測試失敗項目"
		)


extends Node

# ============================================================
# StoryProgress V2｜獨立功能測試
#
# 僅供開發階段 F6 測試。
#
# 執行前必須先備份正式 saves 資料夾。
#
# 本腳本只允許在四格皆為空白時執行，
# 避免覆蓋既有玩家紀錄。
# ============================================================

func _ready() -> void:

	if not OS.is_debug_build():

		return

	# 等待所有 Autoload 初始化完成。
	call_deferred("_run_tests")


func _run_tests() -> void:

	print("========== StoryProgress Test ==========")

	# --------------------------------------------------------
	# 安全檢查：不得使用已有存檔的資料夾
	# --------------------------------------------------------

	for slot_id in range(1, SaveManager.SLOT_COUNT + 1):

		if (
			SaveManager.get_slot_state(slot_id)
			!= SaveManager.SlotState.EMPTY
		):

			push_error(
				"【測試停止】請先備份正式存檔，測試需要空白欄位"
			)

			return

	# --------------------------------------------------------
	# 測試 A：建立 Slot 01
	# --------------------------------------------------------

	if not SaveManager.create_new_game(1):

		push_error("【測試失敗】Slot 01 建立失敗")
		return

	if not SaveManager.load_slot(1):

		push_error("【測試失敗】Slot 01 讀取失敗")
		return

	assert(Dialogic.VAR.merchant_quest == 0)

	print("【測試 A】新遊戲預設值正常")

	# --------------------------------------------------------
	# 測試 B：模擬 Slot 01 任務及戰鬥進度
	#
	# 這些是假資料，只用於測試資料保存。
	# --------------------------------------------------------

	Dialogic.VAR.merchant_quest = 2

	DataManager.combat_unlocked = true

	DataManager.mark_cutscene_completed(
		"test_flag"
	)

	if not StoryProgress.commit_merchant_quest():

		push_error("【測試失敗】商人任務保存失敗")
		return

	if not StoryProgress.commit_combat_unlock():

		push_error("【測試失敗】戰鬥能力保存失敗")
		return

	if not StoryProgress.commit_story_flag(
		"test_flag"
	):

		push_error("【測試失敗】事件旗標保存失敗")
		return

	print("【測試 B】Slot 01 永久進度保存成功")

	# --------------------------------------------------------
	# 測試 C：建立 Slot 02
	#
	# 不得繼承 Slot 01 的任何劇情資料。
	# --------------------------------------------------------

	if not SaveManager.create_new_game(2):

		push_error("【測試失敗】Slot 02 建立失敗")
		return

	if not SaveManager.load_slot(2):

		push_error("【測試失敗】Slot 02 讀取失敗")
		return

	assert(Dialogic.VAR.merchant_quest == 0)

	assert(not DataManager.combat_unlocked)

	assert(
		not DataManager.is_cutscene_completed(
			"test_flag"
		)
	)

	print("【測試 C】Slot 02 資料隔離正常")

	# --------------------------------------------------------
	# 測試 D：重新從磁碟載入 Slot 01
	# --------------------------------------------------------

	if not SaveManager.load_slot(1):

		push_error("【測試失敗】Slot 01 重新讀取失敗")
		return

	assert(Dialogic.VAR.merchant_quest == 2)

	assert(DataManager.combat_unlocked)

	assert(
		DataManager.is_cutscene_completed(
			"test_flag"
		)
	)

	print("【測試 D】Slot 01 資料還原正常")

	# --------------------------------------------------------
	# 測試 E：再次切換 Slot 02
	# --------------------------------------------------------

	if not SaveManager.load_slot(2):

		push_error("【測試失敗】Slot 02 重新讀取失敗")
		return

	assert(Dialogic.VAR.merchant_quest == 0)

	assert(not DataManager.combat_unlocked)

	assert(
		not DataManager.is_cutscene_completed(
			"test_flag"
		)
	)

	print("【測試 E】不同存檔無資料污染")

	print("========== 全部測試通過 ==========")

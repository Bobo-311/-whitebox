extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# StoryStateTest V1｜劇情場景狀態回歸測試
#
# Godot 4.5.1
#
# STEP 10.5.4-A
#
# ============================================================
# 測試目的
# ============================================================
#
# 1. 已完成劇情不會重新觸發
# 2. 已離開的 NPC 正確隱藏
# 3. 指定永久隱藏演員正確處理
# 4. 不應隱藏的演員維持原狀
# 5. 已解鎖的地道門正確顯示
# 6. 未達成前置條件時保持地道門隱藏
# 7. 未完成的劇情仍可正常初始化
#
# ============================================================
# 安全規則
# ============================================================
#
# 本腳本僅供 F6 開發測試。
#
# 不建立正式存檔。
# 不寫入 JSON。
# 不修改現有地圖。
# 不實際播放 Dialogic 劇本。
# 不修改任何正式演員及白貓節點。
#
# 所有測試物件皆由程式暫時建立。
# ============================================================


# ============================================================
# 1. 測試專用常數
#
# 使用獨立 ID，避免與正式劇情名稱衝突。
# ============================================================

const TEST_TIMELINE: String = "__test_story_state__"

const TEST_PREREQUISITE: String = "__test_key__"


# ============================================================
# 2. 測試統計
# ============================================================

var _passed: int = 0

var _failed: int = 0


# ============================================================
# 3. 測試入口
# ============================================================

func _ready() -> void:

	# 正式發行版本不執行開發測試。
	if not OS.is_debug_build():
		return

	# 等待目前測試場景及 Autoload 初始化完成。
	call_deferred("_run_tests")


# ============================================================
# 4. 執行全部測試
# ============================================================

func _run_tests() -> void:

	print("")
	print("========== StoryState Test ==========")

	# --------------------------------------------------------
	# 安全檢查
	#
	# 必須使用 F6 直接執行測試場景。
	# 禁止在已載入正式存檔的遊戲流程內執行。
	# --------------------------------------------------------

	if SaveManager.current_slot_id != 0:

		push_error(
			"【測試停止】目前已有正式存檔工作階段"
		)

		return

	if Dialogic.current_timeline != null:

		push_error(
			"【測試停止】目前正在播放劇情"
		)

		return

	# 備份原本的運行時劇情紀錄。
	var original_progress: Array[String] = []

	original_progress.assign(
		DataManager.completed_cutscenes
	)

	# 執行各項測試。
	await _test_completed_story()

	await _test_missing_prerequisite()

	await _test_uncompleted_story()

	# --------------------------------------------------------
	# 恢復測試開始前的記憶體資料。
	#
	# 不涉及任何磁碟存檔。
	# --------------------------------------------------------

	DataManager.completed_cutscenes.clear()

	DataManager.completed_cutscenes.assign(
		original_progress
	)

	print("")
	print("========== 測試結果 ==========")

	print("通過項目：", _passed)

	print("失敗項目：", _failed)

	if _failed == 0:

		print("========== 全部測試通過 ==========")

	else:

		push_error(
			"【StoryStateTest】存在未通過項目"
		)


# ============================================================
# 5. 建立模擬劇情導演
#
# 使用現有的正式 CutsceneDirector 類別。
#
# 注意：
# 必須在 add_child(director) 之前完成演員設定，
# 才能讓 Director._ready() 使用正確的資料。
# ============================================================

func _create_test_director(
	prerequisite: String = ""
) -> CutsceneDirector:

	var director := CutsceneDirector.new()

	director.name = "TestDirector"

	director.target_timeline = TEST_TIMELINE

	director.required_prerequisite = prerequisite

	# 禁止自動播放測試用的虛構劇本。
	director.trigger_on_map_enter = false

	director.trigger_on_enemies_cleared = false

	# --------------------------------------------------------
	# A. 建立模擬 NPC
	# --------------------------------------------------------

	var npc := Node2D.new()

	npc.name = "TestNPC"

	director.add_child(npc)

	director.target_npc = npc

	director.hide_target_npc_after_complete = true

	# --------------------------------------------------------
	# B. 建立完成劇情後應永久隱藏的角色
	# --------------------------------------------------------

	var leaving_actor := Node2D.new()

	leaving_actor.name = "LeavingActor"

	director.add_child(leaving_actor)

	# --------------------------------------------------------
	# C. 建立應保留在場景中的角色
	# --------------------------------------------------------

	var remaining_actor := Node2D.new()

	remaining_actor.name = "RemainingActor"

	director.add_child(remaining_actor)

	# --------------------------------------------------------
	# D. 建立模擬地道門
	#
	# 預設為隱藏狀態。
	# --------------------------------------------------------

	var door := Node2D.new()

	door.name = "TestDoor"

	door.visible = false

	director.add_child(door)

	# --------------------------------------------------------
	# E. 設定原本 Director 使用的 Actors 字典
	# --------------------------------------------------------

	director.actors = {

		"leaving_actor": NodePath("LeavingActor"),

		"remaining_actor": NodePath("RemainingActor"),

		"door_at_floor": NodePath("TestDoor")
	}

	# 指定完成劇情後需要永久消失的演員。
	director.permanent_hide_actors.assign(
		["leaving_actor"]
	)

	# 所有 Inspector 對應資料設定完成後，
	# 才將導演加入場景樹。
	add_child(director)

	return director


# ============================================================
# 6. 測試 A：已完成劇情的場景還原
#
# 模擬 StoryProgress 已完成資料還原，
# 然後才建立地圖中的 CutsceneDirector。
# ============================================================

func _test_completed_story() -> void:

	print("")
	print("---------- 測試 A ----------")

	DataManager.completed_cutscenes.clear()

	DataManager.mark_cutscene_completed(
		TEST_TIMELINE
	)

	DataManager.mark_cutscene_completed(
		TEST_PREREQUISITE
	)

	var director := _create_test_director(
		TEST_PREREQUISITE
	)

	await get_tree().process_frame

	var npc: Node2D = director.target_npc

	var leaving_actor := (
		director.get_node("LeavingActor") as Node2D
	)

	var remaining_actor := (
		director.get_node("RemainingActor") as Node2D
	)

	var door := (
		director.get_node("TestDoor") as Node2D
	)

	# A1：已完成劇情不得重複觸發。
	_expect(
		director.has_triggered
		and not director.monitoring
		and not director.is_active,
		"A1 已完成劇情正確停止觸發"
	)

	# A2：原本已離開的 NPC 正確隱藏。
	_expect(
		not npc.visible,
		"A2 已離開 NPC 正確隱藏"
	)

	# A3：隱藏 NPC 不再進行一般處理。
	_expect(
		npc.process_mode == Node.PROCESS_MODE_DISABLED,
		"A3 已離開 NPC 停止運作"
	)

	# A4：永久隱藏演員正確還原。
	_expect(
		not leaving_actor.visible
		and leaving_actor.process_mode
		== Node.PROCESS_MODE_DISABLED,
		"A4 永久隱藏演員正確還原"
	)

	# A5：未列入永久隱藏名單的角色不受影響。
	_expect(
		remaining_actor.visible,
		"A5 保留演員維持原狀"
	)

	# A6：原有的地道門顯示邏輯正常。
	_expect(
		door.visible
		and is_equal_approx(door.modulate.a, 1.0),
		"A6 已完成劇情的地道門正確顯示"
	)

	director.queue_free()

	await get_tree().process_frame


# ============================================================
# 7. 測試 B：尚未達成前置條件
#
# 模擬玩家尚未取得必要事件旗標。
# ============================================================

func _test_missing_prerequisite() -> void:

	print("")
	print("---------- 測試 B ----------")

	DataManager.completed_cutscenes.clear()

	var director := _create_test_director(
		TEST_PREREQUISITE
	)

	await get_tree().process_frame

	var door := (
		director.get_node("TestDoor") as Node2D
	)

	# B1：前置條件未達成，不啟用劇情觸發。
	_expect(
		not director.monitoring
		and not director.has_triggered,
		"B1 前置條件未達成時正確阻擋劇情"
	)

	# B2：尚未解鎖的地道門保持隱藏。
	_expect(
		not door.visible,
		"B2 未解鎖地道門保持隱藏"
	)

	director.queue_free()

	await get_tree().process_frame


# ============================================================
# 8. 測試 C：尚未完成劇情
#
# 模擬玩家第一次進入對應地圖。
#
# 不會真的觸發劇本，
# 只檢查劇情導演能否正常完成初始化。
# ============================================================

func _test_uncompleted_story() -> void:

	print("")
	print("---------- 測試 C ----------")

	DataManager.completed_cutscenes.clear()

	var director := _create_test_director()

	# 原本 Director 有兩幀物理初始化，
	# 以及 0.2 秒觸發保護時間。
	#
	# 此處預留足夠時間，確認初始化後的狀態。
	await get_tree().physics_frame

	await get_tree().physics_frame

	await get_tree().create_timer(0.5).timeout

	var npc: Node2D = director.target_npc

	# C1：尚未完成劇情，不得被錯誤跳過。
	_expect(
		not director.has_triggered,
		"C1 尚未完成劇情沒有被錯誤跳過"
	)

	# C2：尚未完成劇情的 NPC 不應永久消失。
	_expect(
		npc.visible,
		"C2 尚未完成劇情的 NPC 正常保留"
	)

	# C3：原本的區域監聽功能仍可啟用。
	_expect(
		director.monitoring,
		"C3 尚未完成劇情的區域監聽正常"
	)

	director.queue_free()

	await get_tree().process_frame


# ============================================================
# 9. 統一測試結果
#
# 不使用 assert 強制中斷整套測試。
# 即使其中一項失敗，仍能看到其他項目的結果。
# ============================================================

func _expect(
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

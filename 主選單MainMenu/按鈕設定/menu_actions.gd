
extends Node

# ============================================================
# 《眠境 RE:RECOLOR》
# MenuActions V3｜主選單頁面與存檔進場管理器
#
# 適用版本：Godot 4.5.1
#
# 掛載位置：
# main_menu.tscn / MainMenu / MenuActions
#
# ------------------------------------------------------------
# 主要職責
# ------------------------------------------------------------
#
# 1. 主選單按鈕操作
# 2. 子頁面建立與切換
# 3. 頁面返回與歷史紀錄
# 4. 共用 Hover / Confirm 音效
# 5. 頁面淡入淡出
# 6. 接收玩家選擇的存檔編號
# 7. 將讀檔要求交給 WorldEntry
# 8. 防止讀檔轉場期間重複操作
# 9. 讀檔前置檢查失敗時恢復選單
# 10. 轉場結束但仍留在主選單時恢復操作
#
# ------------------------------------------------------------
# 系統分工
# ------------------------------------------------------------
#
# MenuActions：
# 主選單操作與頁面管理。
#
# SaveManager：
# 存檔建立、讀取、驗證及磁碟管理。
#
# WorldEntry：
# 解析存檔地圖、出生點及進場要求。
#
# SceneTransition：
# 黑幕動畫與實際遊戲場景切換。
#
# MainMenuAudio：
# 主選單音效與音樂管理。
#
# ------------------------------------------------------------
# 注意事項
# ------------------------------------------------------------
#
# 本腳本不直接操作 JSON。
# 本腳本不直接移動玩家。
# 本腳本不負責死亡重生。
# 本腳本不負責畫架快速傳送。
#
# WorldEntry 回傳 true 代表進場要求已受理，
# 不代表地圖及玩家已經完成初始化。
#
# 完整的轉場成功／失敗訊號，
# 將在後續 SceneTransition 強化階段加入。
# ============================================================


# ============================================================
# 1. 子頁面場景
#
# 保留原本 Inspector 欄位名稱，
# 避免替換腳本後遺失原有資源設定。
# ============================================================

@export_group("子頁面場景")

## 開始遊戲／夢境紀錄頁面
@export var start_page_scene: PackedScene

## 設定首頁
@export var settings_page_scene: PackedScene

## 製作團隊頁面
@export var credits_page_scene: PackedScene

## 音量設定頁面
@export var audio_settings_page_scene: PackedScene

## 按鍵設定頁面
@export var controls_settings_page_scene: PackedScene


# ============================================================
# 2. 頁面動畫設定
# ============================================================

@export_group("頁面動畫設定")

## 主選單及子頁面的淡入淡出時間
@export_range(0.1, 2.0, 0.05)
var transition_time: float = 0.15

## 進入子頁面時的背景變暗程度
@export_range(0.0, 1.0, 0.05)
var background_dim: float = 0.35


# ============================================================
# 3. 除錯設定
#
# 正式發行前可關閉一般輸出訊息。
# 錯誤與警告仍然會正常輸出。
# ============================================================

@export_group("除錯設定")

@export var debug_log: bool = true


# ============================================================
# 4. 主選單節點引用
#
# 全部沿用原本的場景樹結構。
# 不修改任何 UI 排版與節點名稱。
# ============================================================

@onready var logo: TextureRect = (
	$"../Design/Logo"
)

@onready var menu_buttons: VBoxContainer = (
	$"../Design/MenuButtons"
)

@onready var start_button: Button = (
	$"../Design/MenuButtons/StartButton"
)

@onready var settings_button: Button = (
	$"../Design/MenuButtons/SettingsButton"
)

@onready var credits_button: Button = (
	$"../Design/MenuButtons/CreditsButton"
)

@onready var exit_button: Button = (
	$"../Design/MenuButtons/ExitButton"
)


# ============================================================
# 5. 轉場與音訊節點
# ============================================================

## 子頁面背景遮罩
@onready var dim_overlay: ColorRect = (
	$"../Design/DimOverlay"
)

## 子頁面統一掛載位置
@onready var page_host: Control = (
	$"../Design/PageHost"
)

## 遊戲啟動時的淡入遮罩
@onready var intro_fade: ColorRect = (
	$"../IntroFade"
)

## 原有主選單音效管理器
@onready var menu_audio: MainMenuAudio = (
	$"../MenuAudio"
)


# ============================================================
# 6. 頁面管理狀態
# ============================================================

## 目前正在顯示的子頁面
var _active_page: MainMenuPage = null

## 目前子頁面使用的場景資源
var _active_page_scene: PackedScene = null

## 保存上一層頁面，提供返回功能
var _page_history: Array[PackedScene] = []

## 一般頁面操作鎖
##
## 頁面動畫期間禁止重複切換。
var _is_busy: bool = false


# ============================================================
# 7. 遊戲世界進場狀態
# ============================================================

## 是否正在執行讀檔進場
##
## 此狀態和一般頁面動畫分開管理。
var _is_entering_world: bool = false

## 本次準備載入的存檔編號
##
## 0 代表目前沒有進場要求。
var _pending_slot_id: int = 0


# ============================================================
# 8. 初始化
# ============================================================

func _ready() -> void:

	# 主選單背景遮罩初始透明
	dim_overlay.color.a = 0.0

	# --------------------------------------------------------
	# A. 連接主選單按鈕
	# --------------------------------------------------------

	start_button.pressed.connect(
		_on_start_pressed
	)

	settings_button.pressed.connect(
		_on_settings_pressed
	)

	credits_button.pressed.connect(
		_on_credits_pressed
	)

	exit_button.pressed.connect(
		_on_exit_pressed
	)

	# --------------------------------------------------------
	# B. 統一連接 Hover 音效
	# --------------------------------------------------------

	for button in [
		start_button,
		settings_button,
		credits_button,
		exit_button
	]:

		button.mouse_entered.connect(
			_on_button_hover
		)

	# --------------------------------------------------------
	# C. 初始不需要監控世界轉場
	#
	# 只有正式讀檔時才啟用 _process()。
	# --------------------------------------------------------

	set_process(false)

	if debug_log:

		print(
			"【主選單】MenuActions 初始化完成"
		)


# ============================================================
# 9. 讀檔期間的輸入保護
#
# 一般情況下不攔截任何輸入。
#
# 正式進場時，阻止輸入繼續傳遞至 GUI，
# 避免玩家在黑幕淡入期間：
#
# - 點擊其他存檔
# - 建立新的夢境紀錄
# - 開啟清除紀錄確認視窗
# - 按下返回
#
# 不需要暫停整個 SceneTree，
# 避免影響既有轉場動畫。
# ============================================================

func _input(_event: InputEvent) -> void:

	if not _is_entering_world:
		return

	get_viewport().set_input_as_handled()


# ============================================================
# 10. 監控進場狀態
#
# 目前 SceneTransition 尚未提供完整的
# transition_finished / transition_failed 訊號。
#
# 因此本階段暫時監控其 is_transitioning 狀態。
#
# 正常成功：
# 主選單被卸載，本腳本自然停止運作。
#
# 轉場結束但仍留在主選單：
# 視為未完成進場，解除操作鎖。
#
# 注意：
# 如果 SceneTransition 自身發生錯誤，
# 導致 is_transitioning 永遠為 true，
# 必須由後續轉場管理器處理。
# ============================================================

func _process(_delta: float) -> void:

	if not _is_entering_world:

		set_process(false)
		return

	# 場景仍在切換，繼續保持操作鎖
	if SceneTransition.is_transitioning:
		return

	# 正常進場時，主選單應已離開場景樹。
	# 如果本腳本仍在執行，代表沒有完成切換。

	push_warning(
		"【主選單】Slot %02d 轉場結束，但仍停留在主選單"
		% _pending_slot_id
	)

	_reset_world_entry_state()


# ============================================================
# 11. 共用 Hover 音效
# ============================================================

func _on_button_hover() -> void:

	if not _can_execute():
		return

	menu_audio.play_hover()


# ============================================================
# 12. 主選單按鈕
# ============================================================

## 開始遊戲
##
## 先進入夢境紀錄頁面，
## 不直接建立存檔或切換遊戲地圖。

func _on_start_pressed() -> void:

	await _open_page(
		start_page_scene,
		"開始遊戲"
	)


## 設定

func _on_settings_pressed() -> void:

	await _open_page(
		settings_page_scene,
		"設定"
	)


## 製作團隊

func _on_credits_pressed() -> void:

	await _open_page(
		credits_page_scene,
		"製作團隊"
	)


# ============================================================
# 13. 離開遊戲
#
# 保留原本的設定保存及音效流程。
# ============================================================

func _on_exit_pressed() -> void:

	if not _can_execute():
		return

	_is_busy = true

	# 保存全域遊戲設定
	SettingsManager.save_settings()

	# 等待確認音效播放完成
	await menu_audio.play_confirm_and_wait()

	# 正式關閉遊戲
	get_tree().quit()


# ============================================================
# 14. 建立子頁面
#
# 所有子頁面必須繼承 MainMenuPage，
# 才能使用共用返回、Hover 及功能訊號。
# ============================================================

func _create_page(
	scene: PackedScene,
	page_name: String
) -> MainMenuPage:

	# 檢查是否指定場景
	if scene == null:

		push_warning(
			"【主選單】尚未設定頁面：" + page_name
		)

		return null

	# 建立場景實例
	var instance: Node = scene.instantiate()

	# 確認根節點類型
	var page: MainMenuPage = (
		instance as MainMenuPage
	)

	if page == null:

		instance.free()

		push_error(
			"【主選單】頁面未繼承 MainMenuPage："
			+ page_name
		)

		return null

	return page


# ============================================================
# 15. 從主選單進入第一層子頁面
#
# 例如：
# 主選單 → 夢境紀錄
# 主選單 → 設定
# 主選單 → 製作團隊
# ============================================================

func _open_page(
	scene: PackedScene,
	page_name: String
) -> void:

	# 防止重複開啟頁面
	if not _can_execute():
		return

	if _active_page != null:
		return

	var page: MainMenuPage = (
		_create_page(scene, page_name)
	)

	if page == null:
		return

	# 鎖定頁面操作
	_is_busy = true

	# 播放確認音效
	menu_audio.play_confirm()

	# 第一層頁面不應保留舊歷史
	_page_history.clear()

	# --------------------------------------------------------
	# A. 主選單淡出
	# --------------------------------------------------------

	var tween: Tween = create_tween()

	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		logo,
		"modulate:a",
		0.0,
		transition_time
	)

	tween.tween_property(
		menu_buttons,
		"modulate:a",
		0.0,
		transition_time
	)

	tween.tween_property(
		dim_overlay,
		"color:a",
		background_dim,
		transition_time
	)

	await tween.finished

	# --------------------------------------------------------
	# B. 隱藏主選單
	# --------------------------------------------------------

	logo.hide()
	menu_buttons.hide()

	# --------------------------------------------------------
	# C. 安裝新頁面
	# --------------------------------------------------------

	_install_page(
		page,
		scene
	)

	# --------------------------------------------------------
	# D. 子頁面淡入
	# --------------------------------------------------------

	await _fade_page(
		page,
		1.0
	)

	# 完成動畫後恢復操作
	_is_busy = false


# ============================================================
# 16. 進入下一層子頁面
#
# 例如：
# 設定 → 音量設定
# 設定 → 按鍵設定
# ============================================================

func _open_sub_page(
	scene: PackedScene,
	page_name: String
) -> void:

	if not _can_execute():
		return

	if _active_page == null:
		return

	var page: MainMenuPage = (
		_create_page(scene, page_name)
	)

	if page == null:
		return

	_is_busy = true

	# 共用確認音效
	menu_audio.play_confirm()

	# 記錄上一層頁面
	_page_history.append(
		_active_page_scene
	)

	# 執行頁面替換
	await _replace_page(
		page,
		scene
	)

	_is_busy = false


# ============================================================
# 17. 頁面替換
#
# 統一處理：
# 舊頁面淡出 → 移除 → 新頁面淡入
# ============================================================

func _replace_page(
	page: MainMenuPage,
	scene: PackedScene
) -> void:

	# 舊頁面淡出
	await _fade_page(
		_active_page,
		0.0
	)

	# 移除舊頁面
	_remove_active_page()

	# 安裝新頁面
	_install_page(
		page,
		scene
	)

	# 新頁面淡入
	await _fade_page(
		page,
		1.0
	)


# ============================================================
# 18. 安裝頁面與共用訊號
#
# 所有子頁面統一使用：
# - back_requested
# - hover_requested
# - option_requested
# ============================================================

func _install_page(
	page: MainMenuPage,
	scene: PackedScene
) -> void:

	# 初始為透明，等待淡入
	page.modulate.a = 0.0

	# 返回訊號
	page.back_requested.connect(
		_on_page_back_requested
	)

	# Hover 音效訊號
	page.hover_requested.connect(
		_on_button_hover
	)

	# 功能選擇訊號
	page.option_requested.connect(
		_on_page_option_requested
	)

	# 記錄目前使用中的頁面
	_active_page = page

	_active_page_scene = scene

	# 加入原有 PageHost
	page_host.add_child(page)

	# 填滿原有頁面容器
	page.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	page.show()


# ============================================================
# 19. 移除目前子頁面
#
# 清除頁面實例及引用，
# 避免返回時累積重複的 UI 節點。
# ============================================================

func _remove_active_page() -> void:

	if is_instance_valid(_active_page):

		_active_page.hide()

		_active_page.queue_free()

	_active_page = null

	_active_page_scene = null


# ============================================================
# 20. 返回上一層
#
# 有歷史頁面：
# 返回上一層子頁面。
#
# 沒有歷史頁面：
# 返回主選單首頁。
#
# 遊戲讀檔期間禁止執行返回。
# ============================================================

func _on_page_back_requested() -> void:

	if not _can_execute():
		return

	if _active_page == null:
		return

	# --------------------------------------------------------
	# A. 返回上一層子頁面
	# --------------------------------------------------------

	if not _page_history.is_empty():

		var previous_scene: PackedScene = (
			_page_history.back()
		)

		var previous_page: MainMenuPage = (
			_create_page(
				previous_scene,
				"上一層頁面"
			)
		)

		if previous_page == null:
			return

		_is_busy = true

		menu_audio.play_confirm()

		# 移除已經返回的歷史紀錄
		_page_history.pop_back()

		await _replace_page(
			previous_page,
			previous_scene
		)

		_is_busy = false

		return

	# --------------------------------------------------------
	# B. 返回主選單首頁
	# --------------------------------------------------------

	_is_busy = true

	menu_audio.play_confirm()

	# 子頁面淡出
	await _fade_page(
		_active_page,
		0.0
	)

	# 移除子頁面
	_remove_active_page()

	# 恢復主選單顯示
	logo.show()

	menu_buttons.show()

	# --------------------------------------------------------
	# C. 主選單淡入
	# --------------------------------------------------------

	var tween: Tween = create_tween()

	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		logo,
		"modulate:a",
		1.0,
		transition_time
	)

	tween.tween_property(
		menu_buttons,
		"modulate:a",
		1.0,
		transition_time
	)

	tween.tween_property(
		dim_overlay,
		"color:a",
		0.0,
		transition_time
	)

	await tween.finished

	_is_busy = false


# ============================================================
# 21. 子頁面功能分派
#
# 所有子頁面的 option_requested 訊號
# 都會集中在這裡處理。
#
# 原有功能：
#
# AudioButton    → 音量設定
# ControlsButton → 按鍵設定
# Confirm        → 共用確認音效
#
# V3 新增：
#
# SaveSlot01     → 載入第 01 格
# SaveSlot02     → 載入第 02 格
# SaveSlot03     → 載入第 03 格
# SaveSlot04     → 載入第 04 格
# ============================================================

func _on_page_option_requested(
	option: StringName
) -> void:

	if not _can_execute():
		return

	match option:

		# ----------------------------------------------------
		# 音量設定
		# ----------------------------------------------------

		&"AudioButton":

			await _open_sub_page(
				audio_settings_page_scene,
				"音量設定"
			)

		# ----------------------------------------------------
		# 按鍵設定
		# ----------------------------------------------------

		&"ControlsButton":

			await _open_sub_page(
				controls_settings_page_scene,
				"按鍵設定"
			)

		# ----------------------------------------------------
		# 共用確認音效
		# ----------------------------------------------------

		&"Confirm":

			menu_audio.play_confirm()

		# ----------------------------------------------------
		# 第 01 格夢境紀錄
		# ----------------------------------------------------

		&"SaveSlot01":

			_on_existing_save_selected(1)

		# ----------------------------------------------------
		# 第 02 格夢境紀錄
		# ----------------------------------------------------

		&"SaveSlot02":

			_on_existing_save_selected(2)

		# ----------------------------------------------------
		# 第 03 格夢境紀錄
		# ----------------------------------------------------

		&"SaveSlot03":

			_on_existing_save_selected(3)

		# ----------------------------------------------------
		# 第 04 格夢境紀錄
		# ----------------------------------------------------

		&"SaveSlot04":

			_on_existing_save_selected(4)

		# ----------------------------------------------------
		# 尚未處理的功能
		#
		# 保留原本的音效及除錯輸出。
		# ----------------------------------------------------

		_:

			menu_audio.play_confirm()

			if debug_log:

				print(
					"【主選單】尚未處理的功能：",
					option
				)


# ============================================================
# 22. 正式讀取已有存檔
#
# 本次 V3 最重要的新增功能。
#
# ------------------------------------------------------------
# 操作流程
#
# A. 檢查目前頁面
# B. 驗證存檔欄位編號
# C. 確認沒有其他場景正在切換
# D. 鎖定主選單操作
# E. 播放確認音效
# F. 將讀檔要求交給 WorldEntry
# G. 要求失敗時解除操作鎖
# H. 要求受理後監控轉場狀態
#
# ------------------------------------------------------------
# MenuActions 不需要知道 AM001 的場景路徑，
# 也不需要知道 NewGameSpawnPoint 的座標。
#
# 上述資料全部交給 WorldEntry 管理。
# ============================================================

func _on_existing_save_selected(
	slot_id: int
) -> void:

	# --------------------------------------------------------
	# A. 防止重複操作
	# --------------------------------------------------------

	if not _can_execute():
		return

	# --------------------------------------------------------
	# B. 確認目前是夢境紀錄頁面
	#
	# 避免其他子頁面意外觸發讀檔要求。
	# --------------------------------------------------------

	if not (_active_page is SaveSelectPage):

		push_warning(
			"【主選單】目前不是夢境紀錄頁面"
		)

		return

	# --------------------------------------------------------
	# C. 驗證存檔編號
	#
	# 使用 SaveManager 的欄位數量，
	# 不另外維護不同的欄位規則。
	# --------------------------------------------------------

	if (
		slot_id < 1
		or slot_id > SaveManager.SLOT_COUNT
	):

		push_warning(
			"【主選單】無效的存檔編號："
			+ str(slot_id)
		)

		return

	# --------------------------------------------------------
	# D. 確認目前沒有其他場景轉場
	# --------------------------------------------------------

	if SceneTransition.is_transitioning:

		push_warning(
			"【主選單】已有場景正在切換"
		)

		return

	# --------------------------------------------------------
	# E. 鎖定遊戲進場操作
	#
	# 必須在呼叫 WorldEntry 之前鎖定，
	# 防止重複點擊或訊號再次觸發。
	# --------------------------------------------------------

	_is_busy = true

	_is_entering_world = true

	_pending_slot_id = slot_id

	# --------------------------------------------------------
	# F. 播放原有確認音效
	# --------------------------------------------------------

	menu_audio.play_confirm()

	if debug_log:

		print(
			"【主選單】開始處理 Slot %02d 的讀檔要求"
			% slot_id
		)

	# --------------------------------------------------------
	# G. 正式交給 WorldEntry
	#
	# WorldEntry 會：
	# 1. 驗證存檔狀態
	# 2. 解析地圖 ID
	# 3. 解析出生點 ID
	# 4. 呼叫 SaveManager.load_slot()
	# 5. 呼叫 SceneTransition.change_map()
	# --------------------------------------------------------

	var accepted: bool = (
		WorldEntry.load_existing_slot(slot_id)
	)

	# --------------------------------------------------------
	# H. 進場前置檢查失敗
	#
	# 保留目前夢境紀錄頁面，
	# 解除操作鎖，允許玩家重新選擇。
	#
	# 不刪除、不建立、不覆蓋任何存檔。
	# --------------------------------------------------------

	if not accepted:

		push_warning(
			"【主選單】Slot %02d 無法進場，已取消操作"
			% slot_id
		)

		_reset_world_entry_state()

		return

	# --------------------------------------------------------
	# I. 進場要求已受理
	#
	# 注意：
	# 這不代表已完成遊戲場景載入。
	#
	# 開啟暫時性的轉場狀態監控。
	# 正常進場後，本主選單場景會被卸載。
	# --------------------------------------------------------

	set_process(true)

	if debug_log:

		print(
			"【主選單】已送出 Slot %02d 的進場要求"
			% slot_id
		)


# ============================================================
# 23. 恢復世界進場操作狀態
#
# 使用情境：
#
# 1. WorldEntry 拒絕進場
# 2. 轉場結束但仍留在主選單
#
# 統一解除所有與讀檔進場相關的操作鎖。
# ============================================================

func _reset_world_entry_state() -> void:

	_is_entering_world = false

	_is_busy = false

	_pending_slot_id = 0

	# 不再監控轉場
	set_process(false)

	if debug_log:

		print(
			"【主選單】已恢復夢境紀錄頁面操作"
		)


# ============================================================
# 24. 共用頁面淡入淡出
#
# 完整保留原本動畫時間與曲線。
# ============================================================

func _fade_page(
	page: Control,
	target_alpha: float
) -> void:

	var tween: Tween = create_tween()

	tween.set_trans(Tween.TRANS_SINE)

	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		page,
		"modulate:a",
		target_alpha,
		transition_time
	)

	await tween.finished


# ============================================================
# 25. 共用操作鎖定
#
# 以下情況禁止一般主選單操作：
#
# 1. 正在切換子頁面
# 2. 正在讀檔進入遊戲世界
# 3. 開場 IntroFade 尚未結束
# ============================================================

func _can_execute() -> bool:

	if _is_busy:
		return false

	if _is_entering_world:
		return false

	if intro_fade.visible:
		return false

	return true

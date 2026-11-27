extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# PauseInput V1｜玩家暫停輸入接收器
# Godot 4.5.1
# STEP 10.7.7-C
# 掛載位置：Player / PauseInput
# ============================================================
# 主要職責：
# 1. 接收一般遊戲狀態的 ESC 按鍵。
# 2. 將暫停要求交給 PauseMenu。
# 3. 保留原有筆記本、商店及劇情操作。
# 4. 防止長按 ESC 重複觸發。
# 5. 不修改 Player 主腳本。
#
# 本腳本不負責：
# - 正式存檔讀寫
# - 暫停選單畫面
# - 返回主選單轉場
# - 玩家工作階段清理
# ============================================================

# 1. 除錯設定及玩家引用
@export_group("除錯設定")
@export var debug_log: bool = true
@onready var player: Player = get_parent() as Player

# ============================================================
# 2. 初始化
# 暫停期間停止接收一般遊戲輸入。
# ============================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	if not is_instance_valid(player):
		push_error("【PauseInput】必須掛載在 Player 的直接子節點")
		set_process_input(false)
		return

	if debug_log:
		print("【PauseInput】V1 玩家暫停輸入已初始化")

# ============================================================
# 3. 正式接收 ESC 暫停要求
# 只有符合所有條件時，才會攔截原有輸入事件。
# ============================================================
func _input(event: InputEvent) -> void:
	# A. 只接收 ESC，避免長按重複觸發。
	if not event.is_action_pressed("ESC"):
		return
	if event.is_echo():
		return

	# B. 確認目前玩家有效。
	if not is_instance_valid(player):
		return

	# C. 確認屬於目前正式玩家。
	if DataManager.player_node != player:
		return

	# D. 保留原有遊戲操作鎖。
	if player.is_dead:
		return
	if player.is_in_dialogue:
		return
	if player.is_shopping:
		return
	if player.is_reading_book:
		return

	# E. 將正式暫停要求交給 PauseMenu。
	# 只有成功開啟暫停選單，才消耗本次 ESC 輸入。
	if PauseMenu.request_pause():
		get_viewport().set_input_as_handled()

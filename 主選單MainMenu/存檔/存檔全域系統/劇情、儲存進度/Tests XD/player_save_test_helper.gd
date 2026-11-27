extends Node
# ============================================================
# 《眠境 RE:RECOLOR》
# PlayerSaveTestHelper V1｜永久玩家資料驗收工具
# Godot 4.5.1
# STEP 10.7.7-E
#
# 掛載位置：Player / PlayerSaveTestHelper
# 僅供開發階段使用，不加入 Autoload。
# ============================================================
# 主要職責：
# 1. 按下 F9 增加 100 金幣。
# 2. 新增 008 起床氣貼紙。
# 3. 限制只能在正式 Slot 02 使用。
# 4. 防止重複發放測試資料。
# 5. 不直接寫入 JSON。
#
# 本工具不模擬正式商店交易或劇情贈送。
# 正式發行前必須移除。
# ============================================================

@onready var player: Player = get_parent() as Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not OS.is_debug_build():
		set_process_input(false)
		return
	if not is_instance_valid(player):
		set_process_input(false)
		return
	print("【開發者測試】永久玩家資料驗收工具已初始化")
	print("【開發者測試】按 F9 發放測試金幣與貼紙")

# ============================================================
# 1. 開發者測試輸入
# ============================================================
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not event is InputEventKey:
		return
	if not event.pressed or event.is_echo():
		return
	if event.keycode != KEY_F9:
		return
	get_viewport().set_input_as_handled()
	_grant_test_data()

# ============================================================
# 2. 發放測試資料
# 只修改目前運行時資料，不執行正式保存。
# ============================================================
func _grant_test_data() -> void:
	if SaveManager.current_slot_id != 2:
		push_warning("【開發者測試】僅允許在 Slot 02 執行")
		return
	if SceneTransition.is_transitioning:
		return
	if not is_instance_valid(player):
		return
	if DataManager.player_node != player:
		return
	if player.is_dead or player.is_in_dialogue:
		return
	if player.is_reading_book or player.is_shopping:
		return

	# 驗證貼紙資料庫。
	if not DataManager.STICKER_DB.has("008"):
		push_warning("【開發者測試】找不到 008 貼紙")
		return

	# 防止重複發放金幣與貼紙。
	if DataManager.owned_stickers.has("008"):
		print("【開發者測試】已持有測試貼紙，不重複發放")
		return

	# 本階段使用固定金幣基準。
	if DataManager.total_gold != 150:
		push_warning("【開發者測試】目前金幣並非預期的 150")
		return

	# 新增運行時金幣與貼紙收藏。
	DataManager.total_gold += 100
	DataManager.owned_stickers.append("008")

	print("========== 永久玩家資料驗收工具 ==========")
	print("【開發者測試】目前存檔：Slot 02")
	print("【開發者測試】新增金幣：100")
	print("【開發者測試】目前金幣：", DataManager.total_gold)
	print("【開發者測試】新增貼紙：008")
	print("【開發者測試】目前持有貼紙：", DataManager.owned_stickers)
	print("【開發者測試】目前貼紙數量：", DataManager.owned_stickers.size())
	print("【開發者測試】尚未寫入正式 JSON")
	print("==========================================")

extends TextureRect

# ============================================================
# 《眠境 RE:RECOLOR》
# EquipSlot V2｜貼紙裝備格永久資料相容版
# Godot 4.5.1
# STEP 10.7.6
# ============================================================
# 主要職責：
# 1. 顯示指定欄位的貼紙
# 2. 接收玩家拖曳的貼紙
# 3. 驗證貼紙所有權及欄位索引
# 4. 防止重複裝備
# 5. 支援右鍵卸除
# 6. 監聽 equipment_changed 更新介面
# 7. 保留原有白圈底圖替換機制
#
# 不直接寫入 JSON。
# 不修改玩家貼紙所有權。
# ============================================================

# 1. 節點及欄位設定
@export var slot_index: int = 0
@onready var holder: Container = $Holder
const STICKER_ITEM = preload("res://StickerItem/sticker_item.tscn")

# 2. 目前顯示狀態
var current_rendered_id: String = ""

# ============================================================
# 3. 初始化及裝備訊號綁定
# ============================================================
func _ready() -> void:
	if not DataManager.equipment_changed.is_connected(_sync_with_data):
		DataManager.equipment_changed.connect(_sync_with_data)
	_sync_with_data()

# ============================================================
# 4. 驗證裝備欄位索引
# ============================================================
func _is_valid_slot_index() -> bool:
	return (
		slot_index >= 0
		and slot_index < DataManager.equipped_stickers.size()
	)

# ============================================================
# 5. 同步裝備欄位畫面
# ============================================================
func _sync_with_data() -> void:
	if not _is_valid_slot_index():
		push_warning("【貼紙裝備格】欄位索引異常：" + str(slot_index))
		return

	var saved_id: String = DataManager.equipped_stickers[slot_index]

	# 空白欄位。
	if saved_id == "":
		_clear_slot()
		current_rendered_id = ""

	# 裝備已變更，重新生成貼紙。
	elif saved_id != current_rendered_id:
		_clear_slot()
		_spawn_sticker(saved_id)
		current_rendered_id = saved_id

# ============================================================
# 6. 驗證拖曳資料
# 只允許玩家已取得的正式貼紙。
# ============================================================
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not _is_valid_slot_index():
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("type", "") != "sticker":
		return false
	if typeof(data.get("id")) != TYPE_STRING:
		return false

	var sticker_id: String = data["id"]

	if sticker_id.is_empty():
		return false
	if not DataManager.STICKER_DB.has(sticker_id):
		return false
	if not DataManager.owned_stickers.has(sticker_id):
		return false

	return true

# ============================================================
# 7. 正式裝備貼紙
# 先建立候選裝備陣列，驗證成功後才更新 DataManager。
# ============================================================
func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return

	var new_id: String = data["id"]
	var next_slots: Array[String] = DataManager.equipped_stickers.duplicate()

	# 防止同一張貼紙同時出現在多個欄位。
	# 若原本已經裝備，清除舊位置。
	for i in range(next_slots.size()):
		if next_slots[i] == new_id:
			next_slots[i] = ""

	# 放入玩家指定的欄位。
	next_slots[slot_index] = new_id

	# 驗證完整四格裝備及所有權。
	if not PlayerProgress.validate_equipped_stickers(
		next_slots,
		DataManager.owned_stickers
	):
		push_warning("【貼紙裝備格】拒絕異常裝備配置")
		return

	# 配置沒有變化時，不重複刷新能力。
	if next_slots == DataManager.equipped_stickers:
		return

	# 統一更新運行時裝備。
	DataManager.equipped_stickers.assign(next_slots)

	print("【貼紙裝備格】裝備貼紙：", new_id, " / 第 ", slot_index + 1, " 格")
	print("【貼紙裝備格】目前裝備：", DataManager.equipped_stickers)

	# 通知所有裝備格及玩家重新計算能力。
	DataManager.equipment_changed.emit()

# ============================================================
# 8. 右鍵卸除貼紙
# 只移除裝備位置，不移除貼紙所有權。
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if not _is_valid_slot_index():
		return

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		var removed_id: String = DataManager.equipped_stickers[slot_index]

		if removed_id.is_empty():
			return

		DataManager.equipped_stickers[slot_index] = ""

		print("【貼紙裝備格】卸除貼紙：", removed_id, " / 第 ", slot_index + 1, " 格")
		print("【貼紙裝備格】目前裝備：", DataManager.equipped_stickers)

		DataManager.equipment_changed.emit()
		accept_event()

# ============================================================
# 9. 生成貼紙實體
# 保留原本白圈底圖隱藏及右鍵穿透機制。
# ============================================================
func _spawn_sticker(id: String) -> void:
	var new_sticker = STICKER_ITEM.instantiate()
	new_sticker.setup_sticker(id)

	# 避免貼紙阻擋下方裝備格的滑鼠輸入。
	new_sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(new_sticker)

	# 只隱藏白圈底圖，不影響子節點顯示。
	self_modulate.a = 0.0

# ============================================================
# 10. 清除欄位的貼紙顯示
# ============================================================
func _clear_slot() -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()

	# 恢復空白裝備格底圖。
	self_modulate.a = 1.0

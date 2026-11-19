extends Control

@onready var center_slots = $MarginContainer/MainLayout/Center_Stage/Center_Slots
@onready var item_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/ItemSlotsGrid
@onready var skill_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/SkillSlotsGrid
@onready var sticker_slots_grid = $MarginContainer/MainLayout/Center_Stage/Center_Slots/StickerSlotsGrid
@onready var item_list_ui = $MarginContainer/MainLayout/Center_Stage/ItemList_UI
@onready var list_content = $MarginContainer/MainLayout/Center_Stage/ItemList_UI/ListContent
@onready var info_name_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemName
@onready var info_desc_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemDesc
@onready var info_story_label = $MarginContainer/MainLayout/Right_Panel/InfoTextContainer/ItemStory

var current_selected_type := ""
var current_selected_index := -1
var current_list_selected_item := ""

func _ready():
	close_item_list()
	setup_all_slots()
	refresh_item_slots()
	load_stickers()
	DataManager.quick_slot_updated.connect(_on_quick_slot_updated)
	visibility_changed.connect(_on_visibility_changed)

func setup_all_slots():
	for grid in [item_slots_grid, skill_slots_grid, sticker_slots_grid]:
		for child in grid.get_children():
			if child is NotebookEquipSlot:
				child.slot_clicked.connect(on_slot_clicked)

func get_slot_node(type: String, index: int) -> NotebookEquipSlot:
	var grids := {"item": item_slots_grid, "skill": skill_slots_grid, "sticker": sticker_slots_grid}
	if grids.has(type):
		for child in grids[type].get_children():
			if child is NotebookEquipSlot and child.slot_index == index:
				return child
	return null

func refresh_item_slots():
	for i in range(DataManager.quick_slots.size()):
		var slot := get_slot_node("item", i + 1)
		if slot:
			var data: Dictionary = DataManager.ITEM_DB.get(DataManager.quick_slots[i], {})
			slot.set_icon(data.get("texture_path", ""))

func load_stickers():
	for i in range(DataManager.equipped_stickers.size()):
		var slot := get_slot_node("sticker", i + 1)
		if slot:
			var data: Dictionary = DataManager.STICKER_DB.get(DataManager.equipped_stickers[i], {})
			slot.set_icon(data.get("texture_path", ""))

func _on_quick_slot_updated():
	if not is_visible_in_tree():
		return
	refresh_item_slots()
	if item_list_ui.visible:
		refresh_inventory_ui()
		if current_list_selected_item != "" and not can_equip(current_list_selected_item):
			show_list_prompt()
	elif current_selected_type == "item":
		show_equipped_item_info("item", current_selected_index)

func _on_visibility_changed():
	if is_visible_in_tree():
		refresh_item_slots()
		load_stickers()
	else:
		close_item_list()
		clear_info_panel()

func _input(event):
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("TAB") or event.is_action_pressed("ESC"):
		if item_list_ui.visible:
			close_item_list()
			get_viewport().set_input_as_handled()
		else:
			current_selected_type = ""
			current_selected_index = -1
			current_list_selected_item = ""

func clear_info_panel():
	info_name_label.text = ""
	info_desc_label.text = ""
	info_story_label.text = ""
	info_story_label.hide()

func on_slot_clicked(slot_type: String, index: int):
	if slot_type == "item" and current_selected_type == slot_type and current_selected_index == index:
		open_item_list(slot_type, index)
		return
	current_selected_type = slot_type
	current_selected_index = index
	current_list_selected_item = ""
	match slot_type:
		"item":
			show_equipped_item_info(slot_type, index)
		"skill":
			clear_info_panel()
			info_name_label.text = "尚未實裝"
			info_desc_label.text = "此欄位目前僅供預覽。"
		"sticker":
			show_equipped_sticker_info(index)

func on_sticker_clicked(sticker_id: String):
	current_selected_type = "sticker"
	current_selected_index = -1
	current_list_selected_item = ""
	show_sticker_info(sticker_id)

func show_equipped_sticker_info(index: int):
	show_sticker_info(DataManager.equipped_stickers[index - 1])

func show_sticker_info(id: String):
	clear_info_panel()
	if not DataManager.STICKER_DB.has(id):
		info_name_label.text = "空欄位"
		info_desc_label.text = "尚未裝備任何貼紙。"
		return
	var data: Dictionary = DataManager.STICKER_DB[id]
	info_name_label.text = data.name
	info_desc_label.text = "功能類型：" + data.type + "\n數值影響：" + str(data.value)
	if data.has("threshold"):
		info_desc_label.text += "\n發動條件：HP低於 " + str(data.threshold * 100) + "%"

func show_equipped_item_info(slot_type: String, index: int):
	clear_info_panel()
	if slot_type != "item" or index < 1 or index > DataManager.quick_slots.size():
		return
	var id: String = DataManager.quick_slots[index - 1]
	if DataManager.ITEM_DB.has(id):
		show_item_info(DataManager.ITEM_DB[id], true)
	else:
		info_name_label.text = "空欄位"
		info_desc_label.text = "再點擊一下以選擇道具。"

func show_item_info(data: Dictionary, with_story: bool):
	info_name_label.text = data.name
	info_desc_label.text = data.get("description", "")
	info_story_label.text = data.get("story", "")
	info_story_label.visible = with_story and info_story_label.text != ""

func open_item_list(slot_type: String, index: int):
	current_selected_type = slot_type
	current_selected_index = index
	refresh_inventory_ui()
	center_slots.hide()
	item_list_ui.show()
	show_list_prompt()

func show_list_prompt():
	current_list_selected_item = ""
	clear_info_panel()
	info_name_label.text = "選擇裝備"
	info_desc_label.text = "請從左側選擇要裝備的道具。"

func close_item_list():
	item_list_ui.hide()
	center_slots.show()
	show_equipped_item_info(current_selected_type, current_selected_index)
	current_selected_type = ""
	current_selected_index = -1
	current_list_selected_item = ""

func owned_count(id: String) -> int:
	var stock: Dictionary = DataManager.inventory_items.get(id, {})
	return int(stock.get("current_carry", 0)) + int(stock.get("reserve_amount", 0))

func can_equip(id: String) -> bool:
	if not DataManager.ITEM_DB.has(id):
		return false
	var data: Dictionary = DataManager.ITEM_DB[id]
	var stock: Dictionary = DataManager.inventory_items.get(id, {})
	return owned_count(id) > 0 or (data.get("is_auto_refill", false) and stock.get("unlocked", false))

func refresh_inventory_ui():
	for child in list_content.get_children():
		list_content.remove_child(child)
		child.queue_free()
	for id in DataManager.inventory_items:
		if not can_equip(id):
			continue
		var data: Dictionary = DataManager.ITEM_DB[id]
		var stock: Dictionary = DataManager.inventory_items[id]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 60)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "      %s  (隨身 %d／庫存 %d)" % [data.name, stock.get("current_carry", 0), stock.get("reserve_amount", 0)]
		if ResourceLoader.exists(data.get("texture_path", "")):
			btn.icon = load(data.texture_path)
			btn.expand_icon = true
		btn.pressed.connect(_on_list_item_pressed.bind(id))
		list_content.add_child(btn)

func _on_list_item_pressed(id: String):
	var data: Dictionary = DataManager.ITEM_DB[id]
	if current_list_selected_item == id:
		equip_item_to_slot(id, data)
	else:
		current_list_selected_item = id
		show_item_info(data, false)

func equip_item_to_slot(item_id, _item_data):
	var target := current_selected_index - 1
	if current_selected_type != "item" or target < 0 or target >= DataManager.quick_slots.size():
		return
	if not can_equip(item_id):
		return
	for i in range(DataManager.quick_slots.size()):
		if DataManager.quick_slots[i] == item_id:
			DataManager.quick_slots[i] = ""
	DataManager.quick_slots[target] = item_id
	close_item_list()
	DataManager.quick_slot_updated.emit()

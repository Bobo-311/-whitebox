
extends CanvasLayer

# ============================================================
# 《眠境 RE:RECOLOR》
# ShopUI V2｜正式商店交易管理器
# Godot 4.5.1
# STEP 10.7.7-F-3
# ============================================================
# 主要職責：
# 1. 管理商店主選單及購買選單
# 2. 支援鍵盤及滑鼠操作
# 3. 驗證正式存檔工作階段
# 4. 驗證商品 ID 及商品價格
# 5. 管理金幣扣除及商品發放
# 6. 防止重複購買已取得貼紙
# 7. 防止 UI 訊號重複綁定
# 8. 防止交易執行期間重複進入
# 9. 管理商品售罄顯示及錯誤提示
# 10. 保留商人 Talk 劇情功能
# 11. 場景切換時關閉商店介面
#
# 保存規則：
# 商店只修改 DataManager 運行時資料。
# 不直接呼叫 SaveManager 寫入 JSON。
# 金幣、道具及貼紙由正式畫架統一保存。
#
# Sell 功能目前仍保留原本尚未實作的狀態。
# ============================================================

# ============================================================
# 1. 節點引用
# ============================================================
@onready var cursor = $Cursor

@onready var select_sound = $SelectSound
@onready var check_sound = $CheckSound
@onready var back_sound = $BackSound
@onready var purchase_success_sound = $"Purchase success sound"
@onready var purchase_failure_sound = $"Purchase failure sound"

@onready var main_menu_layout = $BottomFrame/MainMenu_Layout
@onready var buy_menu_layout = $BottomFrame/BuyMenu_Layout

@onready var main_vbox = $BottomFrame/MainMenu_Layout/RightMenuArea/VBoxContainer
@onready var buy_vbox = $BottomFrame/BuyMenu_Layout/LeftItemList/VBoxContainer

@onready var info_box = $InfoBox
@onready var desc_label = $InfoBox/MarginContainer/DescLabel
@onready var buy_prompt_label = $BottomFrame/BuyMenu_Layout/RightInfoArea/Label

# ============================================================
# 2. 商店狀態設定
# ============================================================
enum ShopState {
	MAIN,
	BUY
}

const DEFAULT_BUY_PROMPT: String = "What would you like to buy?"

var menu_items: Array[Label] = []
var current_index: int = 0
var cursor_offset: Vector2 = Vector2(-55, -20)
var current_state: int = ShopState.MAIN

# 由 ShopNPC 傳入對應的商人劇本。
var talk_timeline: String = ""

# 本次商店所屬的玩家及存檔工作階段。
var _shop_player: Node2D = null
var _shop_slot_id: int = 0
var _shop_map: Node = null

# 防止重複交易、重複關閉及異常操作。
var _is_purchasing: bool = false
var _is_closing: bool = false
var _is_talking: bool = false

# 防止舊版提示計時器覆蓋新提示。
var _prompt_revision: int = 0

# 防止舊版排版等待流程覆蓋新頁面。
var _layout_revision: int = 0

@export_group("除錯設定")
@export var debug_log: bool = true

# ============================================================
# 3. 商店商品資料庫
#
# 保留原有商品價格、描述及 ID。
# 商品文字必須與場景中的 Label.text 一致。
# ============================================================
var item_database: Dictionary = {
	"50G - 咕咕嘎嘎药水": {
		"desc": "不知道是什么，但听起来很好吃。\n恢复 20 HP",
		"price": 50,
		"item_id": "potion_gugu"
	},
	"30G - 奇迹苹果": {
		"desc": "又脆又甜的苹果。\n恢复 10 HP",
		"price": 30,
		"item_id": "miracle_apple"
	},
	"150G - 烤带骨牛排": {
		"desc": "香气四溢的带骨肉排。\n恢复 50 HP",
		"price": 150,
		"item_id": "steak_bone"
	},
	"20G - 蓝色提神水": {
		"desc": "喝起来像气泡水。\n恢复 5 HP",
		"price": 20,
		"item_id": "energy_drink"
	},
	"25G - 西巴鲁玛": {
		"desc": "神秘的道具。\n速度 +10",
		"price": 25,
		"item_id": "item_xibaluma"
	},
	"300G - 汉堡贴纸": {
		"desc": "裝備後，所有回復道具額外恢復 10 HP。",
		"price": 300,
		"sticker_id": "016"
	}
}

# ============================================================
# 4. 商店初始化
# ============================================================
func _ready() -> void:
	# 記錄商店開啟當下的正式工作階段。
	_shop_player = DataManager.player_node
	_shop_slot_id = SaveManager.current_slot_id
	_shop_map = get_tree().current_scene

	# 監聽跨地圖及返回主選單轉場。
	if not SceneTransition.transition_started.is_connected(_on_transition_started):
		SceneTransition.transition_started.connect(_on_transition_started)

	switch_to_main_menu()

	if debug_log:
		print("【商店】ShopUI V2 初始化完成")
		print("【商店】目前工作階段：Slot %02d" % _shop_slot_id)

# ============================================================
# 5. 驗證目前商店工作階段
#
# 不允許已經離開的商店繼續進行交易。
# ============================================================
func _is_shop_session_valid() -> bool:
	if _shop_slot_id <= 0:
		return false

	if SaveManager.current_slot_id != _shop_slot_id:
		return false

	if SaveManager.get_slot_state(_shop_slot_id) != SaveManager.SlotState.READY:
		return false

	if not is_instance_valid(_shop_player):
		return false

	if DataManager.player_node != _shop_player:
		return false

	if not is_instance_valid(_shop_map):
		return false

	if get_tree().current_scene != _shop_map:
		return false

	if SceneTransition.is_transitioning:
		return false

	if not PlayerProgress.can_save_gold():
		return false

	if not PlayerProgress.can_save_inventory():
		return false

	if not PlayerProgress.can_save_owned_stickers():
		return false

	return true

# ============================================================
# 6. 一般商店操作檢查
# ============================================================
func _can_interact() -> bool:
	if _is_closing:
		return false

	if _is_talking:
		return false

	if _is_purchasing:
		return false

	if is_queued_for_deletion():
		return false

	if SceneTransition.is_transitioning:
		return false

	if get_tree().paused:
		return false

	return true

# ============================================================
# 7. 鍵盤輸入
#
# 保留原有 ESC、TAB、up、down、enter。
# 避免空清單造成除以零或索引錯誤。
# ============================================================
func _input(event: InputEvent) -> void:
	if not _can_interact():
		return

	if event.is_action_pressed("ESC") or event.is_action_pressed("TAB"):
		get_viewport().set_input_as_handled()

		if current_state == ShopState.BUY:
			if back_sound:
				back_sound.play()
			switch_to_main_menu()
		else:
			_close_shop(true)

		return

	if menu_items.is_empty():
		return

	if event.is_action_pressed("down"):
		get_viewport().set_input_as_handled()

		current_index = (current_index + 1) % menu_items.size()
		update_cursor_position()

		if select_sound:
			select_sound.play()

	elif event.is_action_pressed("up"):
		get_viewport().set_input_as_handled()

		current_index = (
			current_index - 1 + menu_items.size()
		) % menu_items.size()

		update_cursor_position()

		if select_sound:
			select_sound.play()

	elif event.is_action_pressed("enter"):
		get_viewport().set_input_as_handled()
		handle_selection()

# ============================================================
# 8. 切換至商店主選單
# ============================================================
func switch_to_main_menu() -> void:
	if _is_closing or _is_talking:
		return

	if is_instance_valid(_shop_player):
		_shop_player.set("is_shopping", true)

	current_state = ShopState.MAIN
	current_index = 0

	_reset_buy_prompt()

	main_menu_layout.show()
	buy_menu_layout.hide()
	info_box.hide()

	refresh_menu_items(main_vbox)

# ============================================================
# 9. 切換至購買選單
# ============================================================
func switch_to_buy_menu() -> void:
	if not _can_interact():
		return

	current_state = ShopState.BUY
	current_index = 0

	_reset_buy_prompt()

	main_menu_layout.hide()
	buy_menu_layout.show()
	info_box.show()

	refresh_menu_items(buy_vbox)

# ============================================================
# 10. 更新選單及滑鼠訊號
#
# V2 修正：
# 使用相同的 Callable 進行訊號檢查與連接。
# 避免 bind() 後的訊號被重複註冊。
# ============================================================
func refresh_menu_items(container: Node) -> void:
	_layout_revision += 1
	var revision: int = _layout_revision

	menu_items.clear()

	for child in container.get_children():
		if not child is Label:
			continue

		var item_label: Label = child as Label

		menu_items.append(item_label)
		item_label.mouse_filter = Control.MOUSE_FILTER_STOP

		var hover_callback: Callable = (
			_on_item_mouse_entered.bind(item_label)
		)

		var input_callback: Callable = (
			_on_item_gui_input.bind(item_label)
		)

		if not item_label.mouse_entered.is_connected(hover_callback):
			item_label.mouse_entered.connect(hover_callback)

		if not item_label.gui_input.is_connected(input_callback):
			item_label.gui_input.connect(input_callback)

		_update_product_color(item_label)

	if menu_items.is_empty():
		cursor.hide()
		return

	current_index = clampi(
		current_index,
		0,
		menu_items.size() - 1
	)

	cursor.show()

	# 等待 Container 完成排版。
	await get_tree().process_frame

	if _is_closing or revision != _layout_revision:
		return

	await get_tree().process_frame

	if _is_closing or revision != _layout_revision:
		return

	update_cursor_position()

# ============================================================
# 11. 更新商品售罄顏色
#
# 一般消耗道具可以重複購買。
# 貼紙已擁有時變成暗灰色。
# ============================================================
func _update_product_color(item_label: Label) -> void:
	var item_name: String = item_label.text

	item_label.modulate = Color.WHITE

	if not item_database.has(item_name):
		return

	var item_info: Dictionary = item_database[item_name]

	if _is_sticker_owned(item_info):
		item_label.modulate = Color(0.3, 0.3, 0.3, 1.0)

func _is_sticker_owned(item_info: Dictionary) -> bool:
	if not item_info.has("sticker_id"):
		return false

	var sticker_id: String = str(item_info["sticker_id"])

	return DataManager.owned_stickers.has(sticker_id)

# ============================================================
# 12. 滑鼠懸停
# ============================================================
func _on_item_mouse_entered(item_node: Label) -> void:
	if not _can_interact():
		return

	var index: int = menu_items.find(item_node)

	if index == -1 or index == current_index:
		return

	current_index = index
	update_cursor_position()

	if select_sound:
		select_sound.play()

# ============================================================
# 13. 滑鼠點擊
#
# 保留原有攻擊輸入釋放及 GUI 事件攔截。
# 玩家端的攻擊狀態防護將另行驗證。
# ============================================================
func _on_item_gui_input(event: InputEvent, item_node: Label) -> void:
	if not event is InputEventMouseButton:
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		return

	get_viewport().set_input_as_handled()

	if InputMap.has_action("attack"):
		Input.action_release("attack")

	if not _can_interact():
		return

	var index: int = menu_items.find(item_node)

	if index == -1:
		return

	current_index = index
	handle_selection()

# ============================================================
# 14. 選單功能分派
# ============================================================
func handle_selection() -> void:
	if not _can_interact():
		return

	if menu_items.is_empty():
		return

	if current_index < 0 or current_index >= menu_items.size():
		return

	if current_state == ShopState.MAIN:
		match current_index:
			0:
				# Buy
				if check_sound:
					check_sound.play()

				switch_to_buy_menu()

			1:
				# Sell
				# 保留原版尚未實作的功能。
				pass

			2:
				# Talk
				if check_sound:
					check_sound.play()

				if talk_timeline.is_empty():
					_close_shop(false)
					return

				start_merchant_talk(talk_timeline)

			3:
				# Exit
				_close_shop(true)

	elif current_state == ShopState.BUY:
		var selected_label: Label = menu_items[current_index]
		var item_name: String = selected_label.text

		if item_name == "Exit":
			if back_sound:
				back_sound.play()

			switch_to_main_menu()
			return

		_purchase_item(item_name)

# ============================================================
# 15. 正式商品交易入口
#
# 所有必要驗證必須在扣款前完成。
#
# 交易過程中不使用 await。
# 金幣及商品於同一次函式執行中更新。
# 不直接寫入正式存檔。
# ============================================================
func _purchase_item(item_name: String) -> bool:
	if not _can_interact():
		return false

	if current_state != ShopState.BUY:
		return false

	if not _is_shop_session_valid():
		return _purchase_failed(
			"Invalid save session!",
			"目前沒有合法的商店工作階段"
		)

	# --------------------------------------------------------
	# A. 驗證商品是否存在
	# --------------------------------------------------------
	if not item_database.has(item_name):
		return _purchase_failed(
			"Invalid item!",
			"未登記的商品：" + item_name
		)

	if typeof(item_database[item_name]) != TYPE_DICTIONARY:
		return _purchase_failed(
			"Invalid item!",
			"商品資料格式異常"
		)

	var item_info: Dictionary = item_database[item_name]

	# --------------------------------------------------------
	# B. 驗證商品價格
	# --------------------------------------------------------
	var raw_price: Variant = item_info.get("price")

	if typeof(raw_price) != TYPE_INT:
		return _purchase_failed(
			"Invalid price!",
			"商品價格不是整數"
		)

	var price: int = int(raw_price)

	if price <= 0:
		return _purchase_failed(
			"Invalid price!",
			"商品價格必須大於 0"
		)

	# --------------------------------------------------------
	# C. 驗證商品類型
	#
	# 一件商品只能是普通道具或貼紙。
	# 不允許同時具有兩種類型。
	# --------------------------------------------------------
	var is_item: bool = item_info.has("item_id")
	var is_sticker: bool = item_info.has("sticker_id")

	if is_item == is_sticker:
		return _purchase_failed(
			"Invalid item!",
			"商品類型異常"
		)

	var product_id: String = ""

	# --------------------------------------------------------
	# D. 驗證一般道具 ID
	# --------------------------------------------------------
	if is_item:
		if typeof(item_info["item_id"]) != TYPE_STRING:
			return _purchase_failed(
				"Invalid item!",
				"道具 ID 格式異常"
			)

		product_id = item_info["item_id"]

		if not DataManager.ITEM_DB.has(product_id):
			return _purchase_failed(
				"Invalid item!",
				"道具未登記：" + product_id
			)

		if not PlayerProgress.validate_inventory_items(
			DataManager.inventory_items
		):
			return _purchase_failed(
				"Invalid inventory!",
				"目前背包資料異常"
			)

	# --------------------------------------------------------
	# E. 驗證貼紙 ID 及持有狀態
	# --------------------------------------------------------
	elif is_sticker:
		if typeof(item_info["sticker_id"]) != TYPE_STRING:
			return _purchase_failed(
				"Invalid sticker!",
				"貼紙 ID 格式異常"
			)

		product_id = item_info["sticker_id"]

		if not DataManager.STICKER_DB.has(product_id):
			return _purchase_failed(
				"Invalid sticker!",
				"貼紙未登記：" + product_id
			)

		if not PlayerProgress.validate_owned_stickers(
			DataManager.owned_stickers
		):
			return _purchase_failed(
				"Invalid inventory!",
				"目前貼紙收藏資料異常"
			)

		if DataManager.owned_stickers.has(product_id):
			return _purchase_failed(
				"You already have this item!",
				"已擁有貼紙：%s，拒絕重複購買" % product_id
			)

	# --------------------------------------------------------
	# F. 驗證玩家金幣
	# --------------------------------------------------------
	if DataManager.total_gold < 0:
		return _purchase_failed(
			"Invalid gold!",
			"玩家金幣資料異常"
		)

	if DataManager.total_gold < price:
		return _purchase_failed(
			"You don't have enough gold!",
			"錢不夠！商品要 %d G，但你只有 %d G" % [
				price,
				DataManager.total_gold
			]
		)

	# --------------------------------------------------------
	# G. 建立交易操作鎖
	# --------------------------------------------------------
	_is_purchasing = true

	var gold_before: int = DataManager.total_gold

	# --------------------------------------------------------
	# H. 正式扣除金幣及發放商品
	#
	# 普通道具進入庫存。
	# 貼紙進入收藏，但不自動裝備。
	# --------------------------------------------------------
	DataManager.total_gold -= price

	if is_item:
		DataManager.add_item_to_reserve(product_id, 1)

	elif is_sticker:
		DataManager.owned_stickers.append(product_id)

		if debug_log:
			print("【商店】獲得新貼紙：", product_id)

	# --------------------------------------------------------
	# I. 更新商店畫面及音效
	#
	# 不再重新綁定整份商品選單訊號。
	# --------------------------------------------------------
	for item_label in menu_items:
		if is_instance_valid(item_label):
			_update_product_color(item_label)

	_reset_buy_prompt()
	update_cursor_position()

	if purchase_success_sound:
		purchase_success_sound.play()

	# --------------------------------------------------------
	# J. 正式交易成功紀錄
	# --------------------------------------------------------
	if debug_log:
		print("========== 商店交易成功 ==========")
		print("【商店】目前存檔：Slot %02d" % _shop_slot_id)
		print("【商店】商品 ID：", product_id)
		print("【商店】購買前金幣：", gold_before)
		print("【商店】扣除金幣：", price)
		print("【商店】目前金幣：", DataManager.total_gold)

		if is_item:
			print(
				"【商店】商品隨身數量：",
				DataManager.inventory_items[product_id]["current_carry"]
			)
			print(
				"【商店】商品庫存數量：",
				DataManager.inventory_items[product_id]["reserve_amount"]
			)

		elif is_sticker:
			print(
				"【商店】目前貼紙收藏：",
				DataManager.owned_stickers
			)

		print("【商店】本次交易未寫入正式 JSON")
		print("=================================")

	_is_purchasing = false

	return true

# ============================================================
# 16. 統一交易失敗處理
#
# 不扣除金幣、不發放商品、不寫入 JSON。
# ============================================================
func _purchase_failed(
	prompt: String,
	reason: String
) -> bool:
	if back_sound:
		back_sound.play()

	_show_buy_prompt(prompt)

	if debug_log:
		print("【商店】交易已拒絕：", reason)
		print("【商店】目前金幣：", DataManager.total_gold)
		print("【商店】未執行扣款及商品發放")

	return false

# ============================================================
# 17. 商品提示管理
#
# 使用版本編號防止較早的計時器
# 覆蓋較新的交易提示。
# ============================================================
func _show_buy_prompt(message: String) -> void:
	_prompt_revision += 1
	var revision: int = _prompt_revision

	buy_prompt_label.text = message

	await get_tree().create_timer(1.0, false).timeout

	if _is_closing or _is_talking:
		return

	if revision != _prompt_revision:
		return

	if current_state != ShopState.BUY:
		return

	buy_prompt_label.text = DEFAULT_BUY_PROMPT

func _reset_buy_prompt() -> void:
	_prompt_revision += 1
	buy_prompt_label.text = DEFAULT_BUY_PROMPT

# ============================================================
# 18. 啟動商人 Talk 劇情
#
# 保留原有 Dialogic 及玩家狀態機流程。
# ============================================================
func start_merchant_talk(timeline_name: String) -> void:
	if _is_talking or _is_closing:
		return

	if timeline_name.is_empty():
		_close_shop(false)
		return

	if Dialogic.current_timeline != null:
		return

	_is_talking = true
	_prompt_revision += 1

	hide()
	set_process_input(false)

	var player = _shop_player

	if is_instance_valid(player):
		player.is_shopping = false
		player.is_in_dialogue = true

		if "velocity" in player:
			player.velocity = Vector2.ZERO

		if player.state_machine:
			player.state_machine.process_mode = Node.PROCESS_MODE_DISABLED

	if not Dialogic.timeline_ended.is_connected(_on_talk_timeline_ended):
		Dialogic.timeline_ended.connect(
			_on_talk_timeline_ended,
			CONNECT_ONE_SHOT
		)

	# 沿用原版商人對話啟動方式。
	Dialogic.start(timeline_name)
	Dialogic.timeline_started.emit()

# ============================================================
# 19. 商人 Talk 劇情結束
# ============================================================
func _on_talk_timeline_ended() -> void:
	if not _is_talking:
		return

	_is_talking = false

	var player = _shop_player

	if is_instance_valid(player):
		if DataManager.player_node == player:
			player.is_in_dialogue = false

			if player.state_machine:
				player.state_machine.process_mode = Node.PROCESS_MODE_INHERIT

	_close_shop(false)

# ============================================================
# 20. 更新游標位置及商品說明
# ============================================================
func update_cursor_position() -> void:
	if menu_items.is_empty():
		cursor.hide()
		return

	if current_index < 0 or current_index >= menu_items.size():
		return

	var target_node: Label = menu_items[current_index]

	if not is_instance_valid(target_node):
		return

	var center_y: float = target_node.size.y / 2.0

	cursor.global_position = (
		target_node.global_position
		+ Vector2(
			cursor_offset.x,
			center_y + cursor_offset.y
		)
	)

	cursor.show()

	if current_state != ShopState.BUY:
		return

	var item_name: String = target_node.text

	if item_database.has(item_name):
		var item_info: Dictionary = item_database[item_name]

		if _is_sticker_owned(item_info):
			desc_label.text = "【已售罄】\n你已經擁有這件物品了。"
		else:
			desc_label.text = str(item_info.get("desc", ""))

	else:
		desc_label.text = ""

# ============================================================
# 21. 統一關閉商店
#
# 不修改金幣、背包及正式存檔。
# 只解除本次商店操作狀態。
# ============================================================
func _close_shop(play_sound: bool = false) -> void:
	if _is_closing:
		return

	_is_closing = true

	_prompt_revision += 1
	_layout_revision += 1

	set_process_input(false)

	if play_sound and back_sound:
		back_sound.play()

	if is_instance_valid(_shop_player):
		if DataManager.player_node == _shop_player:
			_shop_player.set("is_shopping", false)

	hide()

	if debug_log:
		print("【商店】商店介面已關閉")

	queue_free()

# ============================================================
# 22. 場景轉場保護
#
# 商店 UI 原本掛在 SceneTree.root，
# 因此不能只依靠地圖卸載自動銷毀。
# ============================================================
func _on_transition_started(_scene_path: String) -> void:
	if _is_closing:
		return

	if debug_log:
		print("【商店】偵測到場景轉場，關閉商店介面")

	_close_shop(false)

# ============================================================
# 23. 商店離開場景樹
#
# 防止外部直接 queue_free() 時，
# 玩家仍然保留購物狀態。
# ============================================================
func _exit_tree() -> void:
	if SceneTransition.transition_started.is_connected(_on_transition_started):
		SceneTransition.transition_started.disconnect(_on_transition_started)

	if Dialogic.timeline_ended.is_connected(_on_talk_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_talk_timeline_ended)

	if is_instance_valid(_shop_player):
		if DataManager.player_node == _shop_player:
			_shop_player.set("is_shopping", false)

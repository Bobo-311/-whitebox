extends Node

# ==========================================
# 📻 廣播電台系統 (事件驅動)
# ==========================================
# 什麼是 signal (廣播)？
# 想像 DataManager 是一個廣播電台。當某件事發生時，它會「發射 (emit)」訊號。
# 其他 UI 或腳本只要「訂閱 (connect)」這個頻道，一聽到廣播就會自動做事，不用互相綁定。

signal map_changed(new_map_name: String) # 廣播：玩家跨地圖了！UI 快更新地圖名字！
signal equipment_changed                 # 廣播：玩家換裝備了！玩家肉體快重新計算血量！
signal quick_slot_updated                # 🌟 本次新增廣播：道具數量變了！左下角快捷欄快更新數字！

# ==========================================
# 🧠 全域變數儲存區 (跨場景大腦記憶體)
# ==========================================
# 為什麼要把這些寫在這裡？
# 因為每次玩家切換地圖、或按存檔重載場景時，場景裡的玩家節點都會被「刪除並重新生成」。
# 只有存在 DataManager 裡的資料，才能跟著玩家一輩子不見。

var current_map_name: String = "鐘塔" # 記錄玩家現在在哪張地圖，預設是鐘塔
var is_teleporting: bool = false # 記錄玩家是不是正在使用傳送門 (防呆用)

var total_gold: int = 150 # 玩家口袋裡的總財產
var player_node: Node2D = null # 一個變數用來「抓住」玩家實體，讓所有 UI 都能透過大腦找到玩家

# --- 存檔點 (篝火) 系統 ---
var last_save_position: Vector2 = Vector2.ZERO # 記錄玩家點擊畫架時腳踩的確切座標，死掉就在這裡重生
var saved_hp: float = 0     # 存檔時的小抄：玩家最大血量 (重載場景時用來把血補滿)
var saved_energy: float = 0 # 存檔時的小抄：玩家目前的能量
var saved_sp: float = 0     # 存檔時的小抄：玩家最大體力

# --- 靈魂回收系統 (撿屍體機制) ---
var has_soul_on_ground: bool = false # 記錄地圖上現在有沒有掉落的靈魂
var soul_spawn_pos: Vector2 = Vector2.ZERO # 記錄靈魂該生成在哪個座標
var soul_stored_gold: int = 0 # 記錄那個靈魂身上帶了玩家多少錢
var save_map_path: String = "" # 記錄玩家最後是在哪張地圖存檔的
var soul_map_path: String = "" # 記錄玩家死掉、噴裝的那張地圖是哪一張

# ==========================================
# 📔 貼紙系統核心資料庫
# ==========================================
# 玩家目前裝備在筆記本上的 4 張貼紙 ID。空字串 "" 代表沒裝。
var equipped_stickers: Array[String] = ["", "", "", ""]
# 玩家背包裡實際擁有的貼紙清單。
var owned_stickers: Array[String] = ["001", "004", "006", "008"]

# 貼紙的「圖鑑字典」。這是一份唯讀 (const) 的清單，記錄每張貼紙叫什麼、有什麼功能。
const STICKER_DB = {
	"001": {
		"name": "愛心",
		"texture_path": "res://Stickers/001愛心.png", 
		"type": "max_hp_boost", # 類型：加最大血量
		"value": 20             # 數值：加 20 滴
	},
	"004": {
		"name": "魔法棒",
		"texture_path": "res://Stickers/004魔法棒.png", 
		"type": "skill_dmg_multiplier", # 類型：技能傷害倍率
		"value": 1.35                   # 數值：1.35倍
	},
	"006": {
		"name": "手裡劍",
		"texture_path": "res://Stickers/006手裡劍.png", 
		"type": "heal_on_kill", # 類型：殺敵吸血
		"value": 0.10           # 數值：吸 10%
	},
	"008": {
		"name": "起床氣",
		"texture_path": "res://Stickers/008起床氣.png", 
		"type": "low_hp_atk_boost", # 類型：低血量加攻
		"value": 1.35,              # 數值：加 1.35 倍
		"threshold": 0.35           # 發動條件：血量低於 35%
	}
}

# 工具函數：用來更新地圖名稱，並立刻大喊廣播叫大家換名字
func update_map_name(new_name: String) -> void:
	current_map_name = new_name 
	map_changed.emit(current_map_name) 

# 工具函數：讓其他腳本可以一句話問大腦「玩家現在有裝這張貼紙嗎？」
func has_sticker(sticker_id: String) -> bool:
	return sticker_id in equipped_stickers 


# ==========================================
# 🎒 道具與快捷欄系統 (全面升級版)
# ==========================================

# 1️⃣ 道具圖鑑資料庫 (ITEM_DB)
# 跟貼紙一樣，這是記錄遊戲中所有道具「靜態資訊」的字典。
const ITEM_DB = {
	"potion_gugu": {
		"name": "咕咕嘎嘎药水",
		"max_carry": 2, # 🌟 最重要屬性：玩家身上最多只能帶 2 瓶
		"heal_amount": 20,  # 🌟 新增這行：設定補 20 滴血
		"description": "不知道是什么，但听起来很好吃。\n恢复 20 HP",
		"story": "不知道是什么，但听起来很好吃。据说是某个在森林迷路的小孩发明的。", # 🌟 你的故事原封不動還給你！
		"texture_path": "res://FreePixelSurvivalItemsPack/Items/99.png" 
	},
	"apple_test": {
		"name": "奇蹟蘋果",
		"max_carry": 3, # 🌟 最多可以帶 3 顆
		"heal_amount": 10,  # 🌟 新增這行：設定補 10 滴血
		"description": "又脆又甜的蘋果。\n恢復 10 HP",
		"story": "森林裡隨處可見的野蘋果，據說在極度飢餓時吃下，會發生微小的奇蹟。", # 幫蘋果也補個故事防呆
		"texture_path": "res://FreePixelSurvivalItemsPack/Items/98.png" 
	}
}

# 2️⃣ 玩家真實道具背包狀態 (動態資料)
# 分為「身上帶著的 (current_carry)」跟「放家裡倉庫的 (reserve_amount)」。
var inventory_items = {
	"potion_gugu": {
		"current_carry": 2,  # 現在身上有 2 瓶
		"reserve_amount": 5  # 倉庫裡還有 5 瓶備用
	},
	"apple_test": {
		"current_carry": 1,  # 身上有 1 顆
		"reserve_amount": 10 # 倉庫裡還有 10 顆
	}
}

# 3️⃣ 快捷欄狀態
# quick_slots: 裝備在畫面左下角 5 個格子的道具 ID。
var quick_slots: Array[String] = ["potion_gugu", "apple_test", "", "", ""]
# current_slot_index: 記住現在玩家切換到第幾格了 (0代表第一格，也就是藥水)
var current_slot_index: int = 0


# ==========================================
# ⚙️ 道具系統操作函數
# ==========================================

# 📥 獲得新道具 (商店買的、地上撿的，通通先丟進倉庫)
func add_item_to_reserve(item_id: String, amount: int) -> void:
	if inventory_items.has(item_id):
		# 如果大腦原本就有這個道具的資料，直接把數量加進倉庫
		inventory_items[item_id]["reserve_amount"] += amount
	else:
		# 防呆：如果這是玩家第一次獲得這個道具，幫它建一個全新的資料格
		inventory_items[item_id] = {
			"current_carry": 0,  # 剛拿到時身上是 0 個 (要回家存檔才能拿)
			"reserve_amount": amount
		}
	print("【大腦】獲得道具：", item_id, "，目前庫存總數：", inventory_items[item_id]["reserve_amount"])

# 🔍 獲取身上攜帶的數量 (專門提供給 UI 顯示 2/2 數字用的)
func get_item_count(item_id: String) -> int:
	if inventory_items.has(item_id):
		return inventory_items[item_id]["current_carry"]
	return 0

# 🔄 滾輪切換邏輯 (玩家按 1 和 3 時觸發)
func rotate_quick_slot(direction: int) -> void:
	var slots_count = quick_slots.size() # 拿到總格數 (5格)
	
	# 用 for 迴圈找，最多找 5 次，避免全部都是空格時陷入死迴圈當機
	for i in range(slots_count):
		# 🌟 神奇數學：加上總數再取餘數 (%)，能讓 0~4 完美頭尾相接循環！
		# 例如現在是 0(第一格)，按左邊(-1)，(0 - 1 + 5) % 5 = 4(最後一格)！
		current_slot_index = (current_slot_index + direction + slots_count) % slots_count
		
		# 檢查這格是不是空的？只要不是空的 ( != "" )，就決定停在這格！
		if quick_slots[current_slot_index] != "":
			print("【系統】快捷欄切換至第 ", current_slot_index + 1, " 格：", quick_slots[current_slot_index])
			
			# 決定好後，發射廣播叫左下角的 UI 轉動圖片！
			quick_slot_updated.emit() 
			return # 找到就退出函數

# 🍎 使用道具 (玩家按 Q 時觸發)
func use_current_item() -> void:
	var item_id = quick_slots[current_slot_index]
	
	# 防呆：如果現在指著空氣，或者身上的數量已經是 0，直接退出不做事
	if item_id == "" or get_item_count(item_id) <= 0: 
		print("【系統】沒東西或數量不足 (喀喀聲)")
		return
		
	# ⚡ 正式消耗身上的數量！扣 1！
	inventory_items[item_id]["current_carry"] -= 1
	print("【系統】使用了 ", item_id, "，身上剩餘：", inventory_items[item_id]["current_carry"])
	
	# 🌟🌟🌟 本次新增：產生實際的補血效果！ 🌟🌟🌟
	if player_node and ITEM_DB[item_id].has("heal_amount"):
		var heal_value = ITEM_DB[item_id]["heal_amount"]
		player_node.heal(heal_value) # 叫玩家執行補血動作！
	# 🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟🌟
	
	# 檢查扣除後是不是沒了 ( <= 0 )
	if inventory_items[item_id]["current_carry"] <= 0:
		# 判斷它是「可補充的藥水」還是「吃完就沒的一次性道具」
		# (目前我們簡單用 ID 是不是 "potion" 開頭來判斷)
		var is_replenishable = item_id.begins_with("potion")
		
		if is_replenishable:
			# 藥水：就算 0/2 也要留在畫面上，只是圖示變灰
			print("【系統】藥水喝光了！留在快捷欄上顯示 0 數量。")
		else:
			# 蘋果：吃完直接從裝備格上拔掉！並自動幫玩家切換到下一個道具！
			print("【系統】一次性道具用盡！自動解除裝備並切換。")
			quick_slots[current_slot_index] = "" 
			rotate_quick_slot(1) 
			
	# 不管是吃東西還是拔裝備，最後一定發廣播叫 UI 刷新！
	quick_slot_updated.emit() 


# ==========================================
# 🏕️ 存檔點補給邏輯 (篝火補水機制)
# ==========================================
# 這個函數只有在玩家按下「存檔」按鈕時才會被呼叫
func replenish_quick_slots() -> void:
	print("【系統】抵達存檔點！開始從倉庫調用物資補給...")
	var has_replenished = false # 標記這次到底有沒有真的補到東西
	
	# 巡視左下角快捷欄上的每一個道具
	for item_id in quick_slots:
		# 確認這格有裝東西，而且大腦的背包和圖鑑裡都有這個道具的資料
		if item_id != "" and inventory_items.has(item_id) and ITEM_DB.has(item_id):
			
			# 獲取它最多能帶幾個、身上有幾個、家裡剩幾個
			var max_carry = ITEM_DB[item_id]["max_carry"]
			var current = inventory_items[item_id]["current_carry"]
			var reserve = inventory_items[item_id]["reserve_amount"]
			
			# 計算「缺口」：例如上限 2 瓶，身上 0 瓶，缺口就是 2 瓶
			var need_amount = max_carry - current
			
			# 如果有缺口，且家裡倉庫還有貨可以補
			if need_amount > 0 and reserve > 0:
				# 🌟 實際能補的數量：用 min() 函數取「缺口」和「倉庫剩餘量」兩者中較小的那一個
				# (如果缺 2 瓶，但家裡只剩 1 瓶，那就只能補 1 瓶)
				var add_amount = min(need_amount, reserve)
				
				# 身上數量增加！家裡倉庫數量減少！
				inventory_items[item_id]["current_carry"] += add_amount
				inventory_items[item_id]["reserve_amount"] -= add_amount
				has_replenished = true # 標記為：有補給成功
				
				print("【補給成功】", item_id, " 補充了 ", add_amount, " 個。倉庫剩餘: ", inventory_items[item_id]["reserve_amount"])
				
	# 如果整個巡視過程中有發生任何補給，發射廣播叫 UI 數字刷新
	if has_replenished:
		quick_slot_updated.emit()

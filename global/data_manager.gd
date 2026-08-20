extends Node

# ==========================================
# 📻 廣播電台系統 (事件驅動)
# ==========================================
signal map_changed(new_map_name: String) # 廣播：玩家跨地圖了！UI 快更新地圖名字！
signal equipment_changed                  # 廣播：玩家換裝備了！玩家肉體快重新計算血量！
signal quick_slot_updated                 # 廣播：道具數量變了！左下角快捷欄快更新數字！

# ==========================================
# 🧠 全域變數儲存區 (跨場景大腦記憶體)
# ==========================================
var current_map_name: String = "鐘塔" # 記錄玩家現在在哪張地圖，預設是鐘塔
var is_teleporting: bool = false # 記錄玩家是不是正在使用傳送門 (防呆用)

var total_gold: int = 500 # 玩家口袋裡的總財產
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
var equipped_stickers: Array[String] = ["", "", "", ""]
var owned_stickers: Array[String] = ["001", "004", "006", "008"]

const STICKER_DB = {
	"001": {
		"name": "愛心",
		"texture_path": "res://Stickers/001愛心.png", 
		"type": "max_hp_boost",
		"value": 20             
	},
	"004": {
		"name": "魔法棒",
		"texture_path": "res://Stickers/004魔法棒.png", 
		"type": "skill_dmg_multiplier",
		"value": 1.35                    
	},
	"006": {
		"name": "手裡劍",
		"texture_path": "res://Stickers/006手裡劍.png", 
		"type": "heal_on_kill",
		"value": 0.10           
	},
	"008": {
		"name": "起床氣",
		"texture_path": "res://Stickers/008起床氣.png", 
		"type": "low_hp_atk_boost", # 類型：低血量加攻
		"value": 1.35,              # 數值：加 1.35 倍
		"threshold": 0.35           # 發動條件：血量低於 35%
	},
	"016": {
		"name": "漢堡",
		"texture_path": "res://Stickers/016漢堡.png", # ⚠️ 記得換成你隨便塞的那張圖片路徑
		"type": "heal_item_boost", # 類型：回復道具強化
		"value": 10              # 數值：額外回 10 滴血
	}
}

# ==========================================
# 🎒 道具與快捷欄系統 (全面升級版)
# ==========================================
const ITEM_DB = {
	"potion_gugu": {
		"name": "咕咕嘎嘎药水",
		"max_carry": 2, 
		"heal_amount": 20, 
		"description": "不知道是什么，但听起来很好吃。\n恢复 20 HP",
		"story": "不知道是什么，但听起来很好吃。据说是某个在森林迷路的小孩发明的。",
		"texture_path": "res://ItemsPack/Items/99.png" 
	},
	"miracle_apple": {
		"name": "奇迹苹果",
		"max_carry": 1, 
		"heal_amount": 10, 
		"description": "又脆又甜的苹果。\n恢复 10 HP",
		"story": "森林里随处可见的野苹果，据说在极度饥饿时吃下，会发生微小的奇迹。",
		"texture_path": "res://ItemsPack/Items/64.png" 
	},
	"steak_bone": {
		"name": "烤带骨牛排",
		"max_carry": 1, 
		"heal_amount": 50, 
		"description": "香气四溢的带骨肉排。\n恢复 50 HP",
		"story": "表面烤得微焦，切开却是完美的粉红色。光是闻到味道就能让人涌现无限力量。",
		"texture_path": "res://ItemsPack/Items/74.png" 
	},
	"energy_drink": {
		"name": "蓝色提神水",
		"max_carry": 1, 
		"heal_amount": 5, 
		"description": "喝起来像气泡水。\n恢复 5 HP",
		"story": "标签上写着「未满十二岁请勿饮用」，但森林里根本没人在乎这种规定。",
		"texture_path": "res://ItemsPack/Items/63.png" 
	},
	"item_xibaluma": {
		"name": "西巴鲁玛",
		"max_carry": 1, 
		"heal_amount": 0, # 暫時不補血，純收藏或以後補速度
		"description": "神秘的道具。\n速度 +10",
		"story": "没人知道这是什么，但据说带着它会健步如飞。成分不明，请斟酌使用。",
		"texture_path": "res://ItemsPack/Items/28.png" 
	}
}

var inventory_items = {
	"potion_gugu": { "current_carry": 2, "reserve_amount": 0 },
	"miracle_apple": { "current_carry": 1, "reserve_amount": 0 },
	"steak_bone": { "current_carry": 1, "reserve_amount": 0 },
	"energy_drink": { "current_carry": 1, "reserve_amount": 0 },
	"item_xibaluma": { "current_carry": 1, "reserve_amount": 0 }
}

var quick_slots: Array[String] = ["", "", "", "", ""]
var current_slot_index: int = 0

# ==========================================
# ⚙️ 系統與工具函數
# ==========================================
func update_map_name(new_name: String) -> void:
	current_map_name = new_name 
	map_changed.emit(current_map_name) 

func has_sticker(sticker_id: String) -> bool:
	return sticker_id in equipped_stickers 

func add_item_to_reserve(item_id: String, amount: int) -> void:
	if inventory_items.has(item_id):
		inventory_items[item_id]["reserve_amount"] += amount
	else:
		inventory_items[item_id] = {
			"current_carry": 0,
			"reserve_amount": amount
		}
	print("【大腦】獲得道具：", item_id, "，目前庫存總數：", inventory_items[item_id]["reserve_amount"])

func get_item_count(item_id: String) -> int:
	if inventory_items.has(item_id):
		return inventory_items[item_id]["current_carry"]
	return 0

func rotate_quick_slot(direction: int) -> void:
	var slots_count = quick_slots.size()
	for i in range(slots_count):
		current_slot_index = (current_slot_index + direction + slots_count) % slots_count
		if quick_slots[current_slot_index] != "":
			print("【系統】快捷欄切換至第 ", current_slot_index + 1, " 格：", quick_slots[current_slot_index])
			quick_slot_updated.emit() 
			return

# 🍎 使用道具 (所有道具用完皆保留並變灰)
func use_current_item() -> void:
	var item_id = quick_slots[current_slot_index]
	
	# 防呆 1：格子是空的
	if item_id == "": 
		return
		
	# 防呆 2：數量已經是 0，發出喀喀聲，不執行補血
	if get_item_count(item_id) <= 0: 
		print("【系統】道具數量不足 (喀喀聲)")
		return
		
	# 執行消耗邏輯：數量扣 1
	inventory_items[item_id]["current_carry"] -= 1
	print("【系統】使用了 ", item_id, "，身上剩餘：", inventory_items[item_id]["current_carry"])
	
	# 執行補血邏輯
	if player_node and ITEM_DB[item_id].has("heal_amount"):
		var heal_value = ITEM_DB[item_id]["heal_amount"]
		player_node.heal(heal_value)
		
	# 數量歸零時的判定 (🌟 這次改動的核心：不移除裝備，只印提示)
	if inventory_items[item_id]["current_carry"] <= 0:
		print("【系統】道具用盡！留在快捷欄上顯示 0 數量並變灰。")
			
	# 大喊一聲，叫 UI 更新畫面
	quick_slot_updated.emit() 

func replenish_quick_slots() -> void:
	print("【系統】抵達存檔點！開始從倉庫調用物資補給...")
	var has_replenished = false
	
	for item_id in quick_slots:
		if item_id != "" and inventory_items.has(item_id) and ITEM_DB.has(item_id):
			var max_carry = ITEM_DB[item_id]["max_carry"]
			var current = inventory_items[item_id]["current_carry"]
			var reserve = inventory_items[item_id]["reserve_amount"]
			
			var need_amount = max_carry - current
			
			if need_amount > 0 and reserve > 0:
				var add_amount = min(need_amount, reserve)
				inventory_items[item_id]["current_carry"] += add_amount
				inventory_items[item_id]["reserve_amount"] -= add_amount
				has_replenished = true
				print("【補給成功】", item_id, " 補充了 ", add_amount, " 個。倉庫剩餘: ", inventory_items[item_id]["reserve_amount"])
				
	if has_replenished:
		quick_slot_updated.emit()

# ==========================================
# 💥 打擊感卡頓/頓幀系統 (Hitstop)
# ==========================================

# 🌟 一般打擊頓幀
func trigger_hitstop(duration: float = 0.08, freeze_scale: float = 0.05) -> void:
	Engine.time_scale = freeze_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func hitstop(duration: float = 0.08, time_scale: float = 0.05) -> void:
	trigger_hitstop(duration, time_scale)

# 🌟 近戰處決專用：輕微慢動作 (Bullet Time) + 俐落短暫過渡
func trigger_execution_hitstop(duration: float = 0.2, slow_scale: float = 0.2) -> void:
	Engine.time_scale = slow_scale
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		var orig_zoom = camera.zoom
		camera.zoom = orig_zoom * 1.06
		
		await get_tree().create_timer(duration, true, false, true).timeout
		
		Engine.time_scale = 1.0

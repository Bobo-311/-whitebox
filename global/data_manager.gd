extends Node

# ==========================================
# 廣播電台系統 (事件驅動)
# ==========================================
# 定義一個廣播頻道：只要有腳本呼叫 map_changed.emit()，所有監聽這個頻道的 UI 就會做事
signal map_changed(new_map_name: String)

# 定義裝備廣播頻道：當玩家穿、脫裝備時發射廣播，通知玩家肉體重新計算數值
signal equipment_changed 

# ==========================================
# 全域變數儲存區 (大腦記憶體)
# ==========================================
var current_map_name: String = "鐘塔" # 預設一開始在地圖：鐘塔
var is_teleporting: bool = false # 記錄玩家是否正在使用黑洞傳送

var total_gold: int = 150 # 記錄總金幣
var player_node: Node2D = null # 全域玩家定位器，預設為空

# 記錄重生用的確切位置 (玩家按下 E 的腳底位置)
var last_save_position: Vector2 = Vector2.ZERO

# 記錄存檔時的滿血滿狀態小抄 (用於重載場景時恢復)
var saved_hp: float = 0
var saved_energy: float = 0
var saved_sp: float = 0

# 靈魂持久化紀錄
var has_soul_on_ground: bool = false # 記錄目前地圖上是否該有靈魂
var soul_spawn_pos: Vector2 = Vector2.ZERO # 記錄靈魂該出現的座標
var soul_stored_gold: int = 0 # 記錄靈魂帶了多少錢

# 記錄存檔點和靈魂所屬的地圖「路徑」
var save_map_path: String = "" # 記錄玩家在哪張地圖存檔的
var soul_map_path: String = "" # 記錄玩家在哪張地圖死掉的

# ==========================================
# 貼紙系統核心資料庫
# ==========================================
# 記錄 4 個裝備欄的貼紙「ID」。空字串 "" 代表沒裝裝備
var equipped_stickers: Array[String] = ["", "", "", ""]

# ==========================================
# 貼紙圖鑑資料庫 (Database)
# ==========================================
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
		"type": "low_hp_atk_boost",
		"value": 1.35,
		"threshold": 0.35 
	}
}

# ==========================================
# 玩家擁有的貼紙清單 (背包)
# ==========================================
var owned_stickers: Array[String] = [
	"001", "004", "006", "008" # 假設玩家現在擁有這四張貼紙
]

# ==========================================
# 道具圖鑑資料庫 (Item Database)
# ==========================================
const ITEM_DB = {
	"potion_gugu": {
		"name": "咕咕嘎嘎药水",
		"max_carry": 2, 
		"description": "不知道是什么，但听起来很好吃。\n恢复 20 HP",
		"story": "不知道是什么，但听起来很好吃。据说是某个在森林迷路的小孩发明的。",
		"texture_path": "res://FreePixelSurvivalItemsPack/Items/99.png" 
	}
}

# ==========================================
# 玩家真實道具背包狀態 (動態資料)
# ==========================================
var inventory_items = {
	"potion_gugu": {
		"current_carry": 0,
		"reserve_amount": 0
	}
}

var equipped_items: Array[String] = ["potion_gugu", "", "", ""]

# ==========================================
# 全域公開函數
# ==========================================
func update_map_name(new_name: String) -> void:
	current_map_name = new_name # 更新大腦記憶
	map_changed.emit(current_map_name) # 發射廣播！通知所有 UI 現在地圖換了！

# 全域檢查工具：讓任何腳本都可以隨時問大腦「玩家現在有裝備這張貼紙嗎？」
func has_sticker(sticker_id: String) -> bool:
	return sticker_id in equipped_stickers # 如果該 ID 有在裝備陣列裡，就回傳 true

# 當商店買到東西、或是地圖上撿到東西時，呼叫這個函數把東西放進倉庫
func add_item_to_reserve(item_id: String, amount: int) -> void:
	if inventory_items.has(item_id):
		inventory_items[item_id]["reserve_amount"] += amount
	else:
		inventory_items[item_id] = {
			"current_carry": 0,
			"reserve_amount": amount
		}
	
	print("【大腦】獲得道具：", item_id, "，本次新增：", amount, "，目前庫存總數：", inventory_items[item_id]["reserve_amount"])

# ==========================================
# [🌟 本次新增] 打擊感卡頓/頓幀系統 (Hitstop)
# ==========================================
func hitstop(duration: float = 0.05, time_scale: float = 0.05) -> void:
	Engine.time_scale = time_scale # 將遊戲總速度變慢到接近暫停 (0.05倍速)
	# 建立一個無視時間縮放的獨立計時器倒數
	await get_tree().create_timer(duration * time_scale, true, false, true).timeout
	Engine.time_scale = 1.0 # 時間恢復正常的 1.0 倍速

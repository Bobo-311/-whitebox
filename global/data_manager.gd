#DataManager.gd
extends Node

# ==========================================
# 🌟 UI 廣播電台系統 (事件驅動)
# ==========================================
# 定義一個廣播頻道：只要有腳本呼叫 map_changed.emit()，所有監聽這個頻道的 UI 就會做事
signal map_changed(new_map_name: String)

# ==========================================
# 全域變數儲存區 (大腦記憶體)
# ==========================================
var current_map_name: String = "鐘塔" # 🌟 預設一開始在地圖：鐘塔
var is_teleporting: bool = false # 記錄玩家是否正在使用黑洞傳送

var total_gold: int = 0 # 記錄總金幣
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
var save_map_path: String = "" # 記錄玩家在哪張地圖存檔的 (例如 "res://main.tscn")
var soul_map_path: String = "" # 記錄玩家在哪張地圖死掉的

# 記錄 4 個裝備欄的貼紙圖片路徑。空字串 "" 代表沒裝裝備
var equipped_stickers: Array[String] = ["", "", "", ""]


# ==========================================
# 🌟 全域公開函數：修改地圖名稱的專屬通道
# ==========================================
func update_map_name(new_name: String) -> void:
	current_map_name = new_name # 更新大腦記憶
	map_changed.emit(current_map_name) # 📻 發射廣播！通知所有 UI 現在地圖換了！


# ==========================================
# 玩家擁有的貼紙清單 (背包)
# ==========================================
# 裡面放的是貼紙圖片的檔案路徑 (請替換成你實際的圖片路徑！)
var owned_stickers: Array[String] = [
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-mana-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-stamina-bar.png",
	"res://OOOOOOOOOOOOO/dragon-huds/dragon-huds/dragon-huds/rounded-bars/rounded-health-bar.png",
	
]

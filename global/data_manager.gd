#DataManager.gd
extends Node#把重要數據（像錢、關卡數）死寫在玩家腳本裡。如果玩家死掉重生成，錢可能就不見了。

# 把重要數據（像錢、關卡數）死寫在玩家腳本裡。如果玩家死掉重生成，錢可能就不見了。
var total_gold: int = 0 # 記錄總金幣
var player_node: Node2D = null # 全域玩家定位器，預設為空

# 🌟 記錄重生用的確切位置 (現在改為記錄玩家按下 E 的腳底位置)
var last_save_position: Vector2 = Vector2.ZERO

# 🌟 新增：這三本小抄用來記錄存檔時的滿血滿狀態
# 因為玩家場景重載後會失憶，所以要靠這三本小抄把數值寫回去
var saved_hp: float = 0
var saved_energy: float = 0
var saved_sp: float = 0

# 🌟 靈魂持久化紀錄
var has_soul_on_ground: bool = false # 記錄目前地圖上是否該有靈魂
var soul_spawn_pos: Vector2 = Vector2.ZERO # 記錄靈魂該出現的座標
var soul_stored_gold: int = 0 # 記錄靈魂帶了多少錢

extends Node#把重要數據（像錢、關卡數）死寫在玩家腳本裡。如果玩家死掉重生成，錢可能就不見了。

var total_gold: int = 0 # 記錄總金幣
var player_node: Node2D = null # 🌟 新增：全域玩家定位器，預設為空
var last_save_position: Vector2

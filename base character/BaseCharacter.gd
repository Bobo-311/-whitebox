extends CharacterBody2D          # 讓這個腳本繼承物理身體，這樣角色才能移動和實體碰撞
class_name BaseCharacter         # 定義這個類別名稱為 BaseCharacter，供玩家和野豬繼承

# --- 共通數值 ---
@export var max_hp: int = 100    # 最大血量。@export 讓這個變數可以顯示在編輯器右側面板供調整
var current_hp: float              # 目前血量。宣告為浮點數，方便計算小數點的傷害
var is_dead: bool = false        # 死亡狀態開關。記錄角色是不是死了，預設為「活著」(false)
var knockback_force: Vector2 = Vector2.ZERO # 擊退力道。記錄受傷時要往哪個方向、飛多遠，預設為零向量

# --- 內建函數：遊戲開始時執行一次 ---
func _ready() -> void:           # 當節點進入遊戲場景時呼叫
	current_hp = max_hp          # 遊戲一開始，將目前血量補滿至最大血量

# --- 共通功能：受傷邏輯 (這是最核心的函數) ---
func take_damage(amount: float, from_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO): # 接收傷害量、攻擊者位置、攻擊方向(選填)
	if is_dead: return           # 防呆機制：如果角色已經死亡，就直接跳出函數，不再重複扣血

	current_hp -= amount         # 將目前血量扣除受到的傷害量
	print(name, " 受傷了！剩餘血量：", current_hp) # 在後台控制台印出受傷訊息，方便開發除錯

	update_hp_bar()              # 呼叫更新血條的函數，讓畫面顯示最新血量

	# --- 擊退計算邏輯 ---
	if hit_dir != Vector2.ZERO:  # 如果攻擊本身帶有明確方向（例如子彈的飛行方向）
		knockback_force = hit_dir.normalized() * 500 # 就把那個方向標準化(長度為1)，然後乘以擊退力道 500
	else:                        # 如果沒有給定方向（例如近戰揮刀）
		knockback_force = (global_position - from_pos).normalized() * 500 # 用「自己的位置減去攻擊者的位置」算出反方向，再乘以 500

	# --- 判斷生死 ---
	if current_hp <= 0:          # 如果扣血後，目前血量小於或等於 0
		die()                    # 呼叫死亡函數
	else:                        # 如果血量還大於 0 (還活著)
		handle_hurt()            # 呼叫受傷處理函數 (切換到受傷狀態)

# --- 虛擬函數 (Virtual Functions)：留給子類別自己填寫實作細節 ---
func play_animation(prefix: String, dir: Vector2 = Vector2.ZERO): # 播放動畫的空殼函數
	pass                         # 內容留空，由 Player 或 Enemy 各自的腳本去寫怎麼播動畫

func update_hp_bar():            # 更新血條的空殼函數
	pass                         # 內容留空

func handle_hurt():              # 處理受傷狀態的空殼函數
	pass                         # 內容留空

func die():                      # 處理死亡狀態的空殼函數
	pass                         # 內容留空

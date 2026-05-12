#SavePoint.gd
extends Area2D

@export var save_menu_scene: PackedScene

@onready var interact_prompt = $InteractPrompt # 抓取 E 鍵圖片節點
# 🌟 刪除了對 Marker2D 的抓取，因為不需要了

var player_in_range: bool = false # 記錄玩家是否在感應範圍內
var tween: Tween # 負責處理動畫的變數
var prompt_original_y: float # 記錄 E 鍵初始的 Y 軸高度

func _ready():
	interact_prompt.hide() # 遊戲一開始先隱藏 E 鍵
	prompt_original_y = interact_prompt.position.y # 記住 E 鍵剛開始放在哪裡

func _process(_delta):
	# 當玩家在範圍內，而且剛按下 "interact" (E鍵) 時觸發
	if player_in_range and Input.is_action_just_pressed("interact"):
		
		# 🌟 核心修改：直接去 DataManager 抓取玩家當下的腳底位置，作為重生點！
		if DataManager and DataManager.player_node:
			DataManager.last_save_position = DataManager.player_node.global_position
			
		# 如果有設定 UI 場景，就把它實例化 (生出來) 並加到畫面上
		if save_menu_scene:
			var menu = save_menu_scene.instantiate()
			get_tree().root.add_child(menu)
			get_tree().paused = true # 世界時間停止，玩家無法移動

# --- 顯示 E 鍵並執行上下浮動動畫 ---
func show_prompt():
	interact_prompt.show()
	
	if tween:
		tween.kill() # 如果有舊的動畫正在跑，先強制停止，避免動畫衝突
		
	tween = create_tween().set_loops() # 創建新動畫，並設定為無限循環
	
	# 動畫階段 1：花 0.5 秒，將 Y 座標往上移動 10 像素 (數值減少代表往上)。使用 SINE 曲線讓過渡更平滑
	tween.tween_property(interact_prompt, "position:y", prompt_original_y - 15, 0.5).set_trans(Tween.TRANS_SINE)
	# 動畫階段 2：花 0.5 秒，將 Y 座標降回原本的高度
	tween.tween_property(interact_prompt, "position:y", prompt_original_y, 0.5).set_trans(Tween.TRANS_SINE)

# --- 隱藏 E 鍵並重置狀態 ---
func hide_prompt():
	interact_prompt.hide()
	
	if tween:
		tween.kill() # 玩家離開，停止浮動動畫
		
	# 強制把 E 鍵放回原始高度，以免下次顯示時位置越飄越高
	interact_prompt.position.y = prompt_original_y 

func _on_body_entered(body):
	# 這裡的 Player 會變成綠色，而且打錯字引擎會直接標紅線報錯！超安全！
	if body is Player: 
		player_in_range = true
		show_prompt()

func _on_body_exited(body):
	if body is Player:
		player_in_range = false
		hide_prompt()

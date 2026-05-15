extends Area2D # 繼承 Area2D 感應區

@export var portal_menu_scene: PackedScene # 屬性面板掛載傳送 UI (目前先保留位置，之後會用到)
@onready var interact_prompt = $InteractPrompt # 抓取按鍵提示圖片 (請確保你的 Sprite2D 叫這個名字)

var player_in_range: bool = false # 記錄玩家目前是否站在傳送門感應區內
var prompt_original_y: float # 記錄提示圖片一開始的原始高度
var tween: Tween # 宣告動畫控制器，用來處理浮動效果

func _ready():
	interact_prompt.hide() # 遊戲剛開始時，先將按鍵提示藏起來
	prompt_original_y = interact_prompt.position.y # 記下提示圖一開始的位置，當作浮動基準點

func _process(_delta):
	# 🌟 核心觸發邏輯：玩家在範圍內，且剛按下 "portal_interact" (O 鍵)
	if player_in_range and Input.is_action_just_pressed("portal_interact"):
		
		# 確定你有把 portal_menu_scene 掛載到右邊屬性面板
		if portal_menu_scene:
			var menu = portal_menu_scene.instantiate()
			get_tree().root.add_child(menu)
			get_tree().paused = true # 暫停遊戲，等待玩家選地點

# --- 處理按鍵提示浮動動畫 ---
func show_prompt():
	interact_prompt.show() # 顯示提示圖
	if tween: tween.kill() # 如果上次的動畫還沒播完，先強制停止，防止座標錯亂
	
	tween = create_tween().set_loops() # 建立一個無限循環的動畫
	# 花 0.5 秒向上飄 15 像素，然後再花 0.5 秒降回原處 (使用 SINE 曲線讓動態更柔和)
	tween.tween_property(interact_prompt, "position:y", prompt_original_y - 15, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(interact_prompt, "position:y", prompt_original_y, 0.5).set_trans(Tween.TRANS_SINE)

# --- 處理按鍵提示隱藏 ---
func hide_prompt():
	interact_prompt.hide() # 隱藏提示圖
	if tween: tween.kill() # 玩家離開了，立刻停止浮動動畫
	interact_prompt.position.y = prompt_original_y # 強制把圖片拉回原始高度，確保下次出現時位置正確

# --- 訊號連接：實體進入範圍 ---
func _on_body_entered(body):
	if body is Player: # 判斷進入感應區的是否為玩家本人
		player_in_range = true
		show_prompt() # 呼叫浮動提示

# --- 訊號連接：實體離開範圍 ---
func _on_body_exited(body):
	if body is Player: # 判斷離開感應區的是否為玩家本人
		player_in_range = false
		hide_prompt() # 隱藏提示並停止動畫

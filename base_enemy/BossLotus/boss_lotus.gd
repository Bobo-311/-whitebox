extends Node2D

# ==========================================
# 📊 [數值面板] - 可以在 Godot 右側 Inspector 直接調整
# ==========================================
@export_group("Boss 核心數值")
@export var max_hp: int = 500
@export var current_hp: int = 500

# 設定低於多少血量時進入第二階段 (預設 50%，也就是 250)
@export var phase_2_threshold: int = 250 

# 目前的階段狀態
var current_phase: int = 1

# ==========================================
# 節點抓取區
# ==========================================
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar = $HealthBar 

# (之後實作發射器時會用到，先寫好放著)
@onready var pivot_clockwise = $Spawners/Pivot_Clockwise
@onready var pivot_counter = $Spawners/Pivot_Counter


# ==========================================
# 💡 啟動函數
# ==========================================
func _ready() -> void:
	current_hp = max_hp
	
	# 初始化血條 (假設你的 HealthBar 組件有這個方法)
	if health_bar and health_bar.has_method("init_health"):
		health_bar.init_health(max_hp)
		
	print("🌺 淵獄蓮華正式降臨！進入第一階段。")
	_play_phase_1_timeline()

# ==========================================
# 🎬 時間軸導播室 (核心)
# ==========================================
func _play_phase_1_timeline() -> void:
	current_phase = 1
	if anim_player.has_animation("Phase1_Loop"):
		anim_player.play("Phase1_Loop")
	print("▶️ 啟動 第一階段 時間軸 (15秒循環)")

func _play_phase_2_timeline() -> void:
	current_phase = 2
	print("🚨 進入狂暴第二階段！")
	
	# 強制停止一階的時間軸，避免兩邊的指令打架
	anim_player.stop()
	
	# 視覺表現：讓蓮華花瓣泛紅 (用 Tween 讓顏色平滑漸變 0.5 秒)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), 0.5)
	
	if anim_player.has_animation("Phase2_Loop"):
		anim_player.play("Phase2_Loop")
	print("▶️ 啟動 第二階段 時間軸 (12秒循環)")

# ==========================================
# 🩸 受擊與階段切換 (由 Hurtbox 觸發)
# ==========================================
func take_damage(amount: int) -> void:
	current_hp -= amount
	current_hp = clampi(current_hp, 0, max_hp)
	print("💥 淵獄蓮華受傷！剩餘血量：", current_hp)
	
	# 更新 UI 血條
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_hp)
	
	# 觸發二階段判定 (當血量低於或等於設定的門檻時)
	if current_hp <= phase_2_threshold and current_phase == 1:
		_play_phase_2_timeline()
		
	# 死亡判定
	if current_hp <= 0:
		print("💀 淵獄蓮華 死亡！")
		anim_player.stop()
		# queue_free() # 測試階段先不要刪除王，方便觀察

# ==========================================
# 🎯 招式 API 接口 (供 AnimationPlayer 呼叫)
# ==========================================

# [機制1] 生成藤蔓路障 (預警 -> 砸下)
func trigger_vine_obstacles() -> void:
	print("🌿 [導演指令] 生成藤蔓路障！開始預警...")
	# TODO: 寫生成觸手的程式碼

# [機制2] 開始發射螺旋彈幕
func start_spiral_bullets(is_clockwise: bool) -> void:
	var dir = "順時針" if is_clockwise else "逆時針"
	print("🌀 [導演指令] 開始發射【", dir, "】螺旋彈幕！")
	# TODO: 讓對應的 Pivot 開始旋轉並噴射子彈

# [共用] 停止彈幕/進入休息
func stop_bullets() -> void:
	print("🛑 [導演指令] 彈幕停止，進入喘息/休息期。")
	# TODO: 讓 Pivot 停止噴射子彈

# [機制3] 高壓雷射死光 (二階專屬)
func start_laser_sweep(is_clockwise: bool) -> void:
	var dir = "順時針" if is_clockwise else "逆時針"
	print("⚡ [導演指令] 執行【", dir, "】高壓雷射死光掃射！")
	# TODO: 啟動雷射特效與判定

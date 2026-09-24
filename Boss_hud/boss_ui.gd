extends CanvasLayer

@onready var boss_name_label = $VBoxContainer/BossName
@onready var delay_bar = $VBoxContainer/HealthBars/DelayBar_Yellow
@onready var main_bar = $VBoxContainer/HealthBars/MainBar_Red
@onready var health_bars_container = $VBoxContainer/HealthBars # 用來做震動特效

var _health_tween: Tween
var _flash_tween: Tween # 專門處理白光閃爍的 Tween

func init_boss(boss_name: String, max_hp: int) -> void:
	boss_name_label.text = boss_name
	main_bar.max_value = max_hp
	main_bar.value = max_hp
	delay_bar.max_value = max_hp
	delay_bar.value = max_hp
	self.visible = true
	
	# 確保初始沒有多餘的材質發光
	main_bar.modulate = Color.WHITE

func update_health(new_hp: int) -> void:
	# ---------------------------------------------------
	# 🎬 1. 瞬間物理反饋 (真實血量)
	# ---------------------------------------------------
	main_bar.value = new_hp
	
	# ---------------------------------------------------
	# 🎬 2. 打擊閃爍特效 (Hit Flash)
	# ---------------------------------------------------
	# 每次被打到，真實血條瞬間爆閃成純白，再迅速暗下來恢復紅色。
	# 這能極大化玩家的視覺爽惡感。
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	main_bar.modulate = Color(3.0, 3.0, 3.0, 1.0) # 瞬間 3 倍高光爆閃 (Godot 支援大於1的顏色值)
	_flash_tween.tween_property(main_bar, "modulate", Color.WHITE, 0.15).set_trans(Tween.TRANS_CUBIC)

	# ---------------------------------------------------
	# 🎬 3. 黃血殘影衰減 (Delay Trail)
	# ---------------------------------------------------
	if _health_tween and _health_tween.is_running():
		_health_tween.kill()
		
	_health_tween = create_tween()
	
	# 階段 A：停頓更久一點 (0.6秒)，讓玩家看清楚剛剛那一刀多痛
	_health_tween.tween_interval(0.6) 
	
	# 階段 B：更暴力的曲線 (EXPO)
	# TRANS_EXPO 是一種一開始極快，後面極慢的曲線，非常適合動作遊戲的俐落感
	_health_tween.tween_property(delay_bar, "value", new_hp, 0.45)\
		 .set_trans(Tween.TRANS_EXPO)\
		 .set_ease(Tween.EASE_OUT)
		 
	# ---------------------------------------------------
	# 🎬 4. UI 微震動 (UI Shake) - 選擇性加入
	# ---------------------------------------------------
	# 讓血條本身在受到大傷害時稍微抖一下，增加重量感
	_shake_ui()

# 專屬的 UI 震動函數
func _shake_ui() -> void:
	var shake_tween = create_tween()
	var original_pos = health_bars_container.position
	
	# 快速往右下抖 2 像素，再彈回來
	shake_tween.tween_property(health_bars_container, "position", original_pos + Vector2(2, 2), 0.05)
	shake_tween.tween_property(health_bars_container, "position", original_pos + Vector2(-2, -1), 0.05)
	shake_tween.tween_property(health_bars_container, "position", original_pos, 0.05)

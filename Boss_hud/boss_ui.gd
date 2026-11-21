extends CanvasLayer

@onready var boss_name_label = $VBoxContainer/BossName
@onready var delay_bar = $VBoxContainer/HealthBars/DelayBar_Yellow
@onready var main_bar = $VBoxContainer/HealthBars/MainBar_Red
@onready var health_bars_container = $VBoxContainer/HealthBars 

@export var wake_up_distance: float = 950.0 # 🌟 玩家距離 Boss 多近以內才顯示血條 (設 0 代表全圖顯示)

var _health_tween: Tween
var _flash_tween: Tween # 專門處理白光閃爍的 Tween
var _is_boss_active: bool = false # 記錄 Boss 血條是否已經初始化啟用
var _is_boss_dead: bool = false   # 記錄 Boss 是否已死亡
var _has_damaged: bool = false    # 記錄 Boss 是否已經被打過 (被打過就常駐顯示)

func _ready() -> void:
	# 開局先把血條徹底藏起來
	self.visible = false
	# 🌟 已經不需要紀錄 position 了，刪除相關變數，保持程式碼乾淨

func _process(_delta: float) -> void:
	if not _is_boss_active or _is_boss_dead:
		if self.visible:
			self.visible = false
		return
		
	var should_hide: bool = false
	
	# 🌟 1. 檢查是否在 Dialogic 劇情中
	if Dialogic.current_timeline != null:
		should_hide = true
		
	# 🌟 2. 檢查阿尼是否處於過場走位、對話鎖定、看書或 F4 拍照模式
	if DataManager and is_instance_valid(DataManager.player_node):
		var p = DataManager.player_node
		if p.get("is_in_dialogue") or p.get("_photo_mode_Active") or p.get("is_reading_book"):
			should_hide = true
		# 關鍵：當 CutsceneDirector 控制阿尼走位時，會把 state_machine 設為 DISABLED！
		if p.get("state_machine") and p.state_machine.process_mode == Node.PROCESS_MODE_DISABLED:
			should_hide = true
			
	# 🌟 3. 檢查場景裡的 CutsceneDirector 是不是開著電影黑邊？
	# 只要玩家的 PlayerHUD 被導演或拍照模式藏起來了，Boss 血條就跟著藏！
	if DataManager and is_instance_valid(DataManager.player_node):
		var hud = DataManager.player_node.get("player_hud")
		if is_instance_valid(hud) and not hud.visible:
			should_hide = true

	# 🌟 4. 檢查父節點 (Boss 本體)：如果 Boss 被隱藏，或玩家還在走廊根本沒走近 Boss，先不亮血條！
	var parent_node = get_parent()
	if parent_node is Node2D:
		if not parent_node.visible:
			should_hide = true
		elif wake_up_distance > 0.0 and not _has_damaged and DataManager and is_instance_valid(DataManager.player_node):
			var dist = parent_node.global_position.distance_to(DataManager.player_node.global_position)
			if dist > wake_up_distance:
				should_hide = true
				
	self.visible = not should_hide

func init_boss(boss_name: String, max_hp: int) -> void:
	if boss_name != "":
		boss_name_label.text = boss_name
	main_bar.max_value = max_hp
	main_bar.value = max_hp
	delay_bar.max_value = max_hp
	delay_bar.value = max_hp
	main_bar.modulate = Color.WHITE
	
	_is_boss_dead = false
	_has_damaged = false
	_is_boss_active = true
	
	# 初始化當下先保持隱藏，交給下一幀的 _process 判斷是否沒有過場且距離夠近才顯示！
	self.visible = false

func update_health(new_hp: int) -> void:
	_has_damaged = true # 一旦扣血就標記已開戰
	
	# 確保新血量不會小於 0，也不會大於血條的上限！
	var safe_hp = clamp(new_hp, 0, main_bar.max_value)
	
	# 🎬 1. 瞬間物理反饋 (真實血量)
	main_bar.value = safe_hp
	
	# 🎬 2. 打擊閃爍特效 (Hit Flash)
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	main_bar.modulate = Color(3.0, 3.0, 3.0, 1.0)
	_flash_tween.tween_property(main_bar, "modulate", Color.WHITE, 0.15).set_trans(Tween.TRANS_CUBIC)

	# 🎬 3. 黃血殘影衰減 (Delay Trail) - 這裡也改吃 safe_hp
	if _health_tween and _health_tween.is_running():
		_health_tween.kill()
		
	_health_tween = create_tween()
	_health_tween.tween_interval(0.6) 
	_health_tween.tween_property(delay_bar, "value", safe_hp, 0.45)\
		 .set_trans(Tween.TRANS_EXPO)\
		 .set_ease(Tween.EASE_OUT)
		 
	# 🎬 4. UI 微震動 (UI Shake)
	_shake_ui()
	
	# 如果血量歸零，直接標記死亡關閉血條
	if safe_hp <= 0:
		_is_boss_dead = true

func _shake_ui() -> void:
	# 🌟 關鍵修正：絕對不要去 tween 排版容器(VBoxContainer)裡面的子節點座標！
	# 改為直接震動 CanvasLayer 原生的 offset 屬性，完全不干擾排版引擎！
	var shake_tween = create_tween()
	shake_tween.tween_property(self, "offset", Vector2(4, 4), 0.05)
	shake_tween.tween_property(self, "offset", Vector2(-4, -2), 0.05)
	shake_tween.tween_property(self, "offset", Vector2.ZERO, 0.05)

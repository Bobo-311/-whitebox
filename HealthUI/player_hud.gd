extends CanvasLayer # 繼承自畫布層，確保 UI 永遠顯示在遊戲畫面最前面

# ==========================================
# 節點抓取
# ==========================================
@onready var margin_container: MarginContainer = $MarginContainer # 抓取最外層容器，用來做 UI 震動

# 🌟 新增：抓取疊在一起的主血條與白血條
@onready var health_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/HealthContainer/HealthBar
@onready var damage_bar: ProgressBar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/HealthContainer/DamageBar")

@onready var sp_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/SpBar
@onready var overheat_overlay: ColorRect = $OverheatOverlay
@onready var ink_bar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/InkBar")

# ==========================================
# 比例尺與全域變數
# ==========================================
var hp_pixel_ratio: float = 3.0 
var sp_pixel_ratio: float = 3.0 

var original_hud_pos: Vector2 # 記錄 UI 初始位置
var damage_tween: Tween       # 專門控制白血殘影的動畫計時器
var hp_heal_tween: Tween      # 🌟 專門用來控制回血閃爍的動畫

func _ready():
	if margin_container:
		original_hud_pos = margin_container.position

# ==========================================
# 🌟 狀態更新函數 (果汁感血條升級版)
# ==========================================

func update_hp(new_hp: int, max_hp: int):
	if not health_bar: return
	
	# 1. 調整兩條血條的實體長度
	health_bar.max_value = max_hp
	health_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio
	if damage_bar:
		damage_bar.max_value = max_hp
		damage_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio

	# 2. 判斷是扣血還是補血，播放不同動畫
	if new_hp < health_bar.value:
		# 💥【受傷邏輯】：瞬間扣血 + UI震動 + 白血延遲掉落
		health_bar.value = new_hp # 主血條瞬間減少，露出底下的白血
		health_bar.modulate = Color.WHITE # 🌟 確保受傷時中斷發光，恢復正常顏色
		shake_ui() # 整個 UI 介面用力震動一下
		
		if damage_bar:
			if damage_tween and damage_tween.is_running():
				damage_tween.kill() # 如果連續被打，重置殘影計時
			damage_tween = get_tree().create_tween()
			damage_tween.tween_interval(0.4) # 白血停頓 0.4 秒 (Damage Chunk)
			damage_tween.tween_property(damage_bar, "value", new_hp, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			
	elif new_hp > health_bar.value:
		# 💖【補血邏輯】：平滑增長綠條 + 瞬間閃白光
		if hp_heal_tween and hp_heal_tween.is_running():
			hp_heal_tween.kill()
			
		hp_heal_tween = create_tween().set_parallel(true)
		
		# 1. 讓主血條與白血條一起平滑生長
		hp_heal_tween.tween_property(health_bar, "value", new_hp, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if damage_bar:
			hp_heal_tween.tween_property(damage_bar, "value", new_hp, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		# 2. UI 瞬間變亮 (數值 > 1 代表發光)，然後在 0.3 秒內平滑褪回正常的白色
		health_bar.modulate = Color(2.0, 2.0, 2.0, 1.0)
		hp_heal_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.3)

# 💥 UI 震動特效 (Shake)
func shake_ui():
	if not margin_container: return
	var shake_tween = get_tree().create_tween()
	# 快速左右上下亂數晃動 4 次
	for i in range(4):
		var rand_x = randf_range(-6.0, 6.0)
		var rand_y = randf_range(-6.0, 6.0)
		shake_tween.tween_property(margin_container, "position", original_hud_pos + Vector2(rand_x, rand_y), 0.04)
	# 最後歸位
	shake_tween.tween_property(margin_container, "position", original_hud_pos, 0.04)

# ==========================================
# 其他系統更新函數 (體力、墨水)
# ==========================================

func update_sp(current_sp: float, max_sp: float):
	if sp_bar:
		sp_bar.max_value = max_sp
		sp_bar.custom_minimum_size.x = max_sp * sp_pixel_ratio 
		sp_bar.value = current_sp

func update_ink(current_ink: float, max_ink: float) -> void:
	if ink_bar and ink_bar.has_method("update_ink"):
		ink_bar.update_ink(current_ink, max_ink)

func set_ink_mode(mode_id: int) -> void:
	if ink_bar and ink_bar.has_method("set_mode"):
		ink_bar.set_mode(mode_id)

func update_ammo(current_ammo: int, max_ammo: int) -> void:
	if ink_bar and ink_bar.has_method("update_ink"):
		ink_bar.update_ink(current_ammo * 10.0, max_ammo * 10.0)

# --- 體力透支 (過熱) 視覺切換 ---
func set_overheat_visual(is_active: bool):
	if not sp_bar or not overheat_overlay:
		return 
	
	# 抓取 SP 條目前的樣式來複製，而不是每次都產生全新的空樣式
	var style_box = sp_bar.get_theme_stylebox("fill").duplicate()
	var tween = get_tree().create_tween()
	
	if is_active:
		style_box.bg_color = Color.HOT_PINK # 過熱時變成粉紅色
		tween.tween_property(overheat_overlay, "modulate:a", 0.4, 0.3) 
	else:
		# 🌟 把這裡改成黃色！你可以用 Color.GOLD，或是自訂 RGB 數值
		style_box.bg_color = Color.GOLD 
		tween.tween_property(overheat_overlay, "modulate:a", 0.0, 0.3) 
		
	sp_bar.add_theme_stylebox_override("fill", style_box)

func preview_ink(preview_val: float) -> void:
	if ink_bar and ink_bar.has_method("preview_ink"):
		ink_bar.preview_ink(preview_val)

func confirm_ink(final_val: float) -> void:
	if ink_bar and ink_bar.has_method("confirm_ink_drop"):
		ink_bar.confirm_ink_drop(final_val)

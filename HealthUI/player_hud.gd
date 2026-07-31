#playerhud
extends CanvasLayer # 繼承自畫布層，確保 UI 永遠顯示在遊戲畫面最前面

# ==========================================
# 節點抓取 (只抓還存在的元件)
# ==========================================
@onready var health_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/HealthBar
@onready var sp_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/SpBar
@onready var overheat_overlay: ColorRect = $OverheatOverlay

# 🌟 墨水容器 (用 get_node_or_null 抓取，防止防呆崩潰)
@onready var ink_container: HBoxContainer = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/InkContainer")

# ==========================================
# 比例尺設定
# ==========================================
var hp_pixel_ratio: float = 3.0 
var sp_pixel_ratio: float = 3.0 

# ==========================================
# 狀態更新函數
# ==========================================

# --- 更新血條 ---
func update_hp(current_hp: int, max_hp: int):
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio
		
		var tween = get_tree().create_tween()
		tween.tween_property(health_bar, "value", current_hp, 0.3)

# --- 更新墨水彈藥 UI ---
func update_ammo(current_ammo: int, max_ammo: int) -> void:
	if not ink_container:
		return
		
	var ink_icons = ink_container.get_children()
	
	for i in range(ink_icons.size()):
		if i < max_ammo:
			ink_icons[i].visible = true
			
			if i < current_ammo:
				if current_ammo >= max_ammo:
					ink_icons[i].modulate = Color(1.3, 1.2, 0.8, 1.0) # 滿彈藥發光
				else:
					ink_icons[i].modulate = Color.WHITE # 正常全彩
			else:
				ink_icons[i].modulate = Color(0.2, 0.2, 0.2, 0.4) # 耗盡變灰
		else:
			ink_icons[i].visible = false

# --- 更新體力條 ---
func update_sp(current_sp: float, max_sp: float):
	if sp_bar:
		sp_bar.max_value = max_sp
		sp_bar.custom_minimum_size.x = max_sp * sp_pixel_ratio 
		sp_bar.value = current_sp

# ==========================================
# 視覺特效控制
# ==========================================

# --- 體力透支 (過熱) 視覺切換 ---
func set_overheat_visual(is_active: bool):
	if not sp_bar or not overheat_overlay:
		return 
	
	var style_box = StyleBoxFlat.new()
	var tween = get_tree().create_tween()
	
	if is_active:
		style_box.bg_color = Color.HOT_PINK
		tween.tween_property(overheat_overlay, "modulate:a", 0.4, 0.3) 
	else:
		style_box.bg_color = Color.LIME_GREEN
		tween.tween_property(overheat_overlay, "modulate:a", 0.0, 0.3) 
		
	sp_bar.add_theme_stylebox_override("fill", style_box)

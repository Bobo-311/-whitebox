extends CanvasLayer # 確保 UI 永遠顯示在遊戲畫面最前面

# ==========================================
# 節點抓取
# ==========================================
@onready var margin_container: MarginContainer = $MarginContainer # 抓取最外層，用來做全域震動

# 主血條與白底殘影血條 (Damage Chunk)
@onready var health_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/HealthContainer/HealthBar
@onready var damage_bar: ProgressBar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/HealthContainer/DamageBar")

# 墨水條 (能量/彈藥庫)
@onready var ink_bar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/InkBar")

# 🌟【改動】：已完全刪除 sp_bar 與 overheat_overlay 的抓取宣告。

# ==========================================
# 比例尺與變數
# ==========================================
var hp_pixel_ratio: float = 3.0 # 血量轉換為畫面像素寬度的倍率
var original_hud_pos: Vector2   # 記憶初始位置 (震動歸位用)
var damage_tween: Tween         # 控制白血殘影
var hp_heal_tween: Tween        # 控制回血閃爍

func _ready():
	if margin_container:
		original_hud_pos = margin_container.position

# ==========================================
# 狀態更新函數 (果汁感血條升級版)
# ==========================================
func update_hp(new_hp: int, max_hp: int):
	if not health_bar: return
	
	# 1. 動態調整血條最大長度
	health_bar.max_value = max_hp
	health_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio
	if damage_bar:
		damage_bar.max_value = max_hp
		damage_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio

	# 2. 判斷扣血或補血
	if new_hp < health_bar.value:
		# 💥【受傷邏輯】：主血條瞬間掉，白血延遲 0.4 秒後追上
		health_bar.value = new_hp 
		health_bar.modulate = Color.WHITE # 防呆：強制中斷補血亮光
		shake_ui() 
		
		if damage_bar:
			if damage_tween and damage_tween.is_running():
				damage_tween.kill() # 如果連續被打，重置延遲計時
			damage_tween = get_tree().create_tween()
			damage_tween.tween_interval(0.4) 
			damage_tween.tween_property(damage_bar, "value", new_hp, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			
	elif new_hp > health_bar.value:
		# 💖【補血邏輯】：雙血條平滑增長，並伴隨閃亮特效
		if hp_heal_tween and hp_heal_tween.is_running():
			hp_heal_tween.kill()
			
		hp_heal_tween = create_tween().set_parallel(true)
		
		hp_heal_tween.tween_property(health_bar, "value", new_hp, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if damage_bar:
			hp_heal_tween.tween_property(damage_bar, "value", new_hp, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		health_bar.modulate = Color(2.0, 2.0, 2.0, 1.0) # HDR 高亮
		hp_heal_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.3)

# UI 震動反饋
func shake_ui():
	if not margin_container: return
	var shake_tween = get_tree().create_tween()
	# 隨機亂數位移 4 次
	for i in range(4):
		var rand_x = randf_range(-6.0, 6.0)
		var rand_y = randf_range(-6.0, 6.0)
		shake_tween.tween_property(margin_container, "position", original_hud_pos + Vector2(rand_x, rand_y), 0.04)
	shake_tween.tween_property(margin_container, "position", original_hud_pos, 0.04)

# ==========================================
# 墨水(能量)更新對接
# ==========================================
func update_ink(current_ink: float, max_ink: float) -> void:
	if ink_bar and ink_bar.has_method("update_ink"):
		ink_bar.update_ink(current_ink, max_ink)

func set_ink_mode(mode_id: int) -> void:
	if ink_bar and ink_bar.has_method("set_mode"):
		ink_bar.set_mode(mode_id)

func update_ammo(current_ammo: int, max_ammo: int) -> void:
	if ink_bar and ink_bar.has_method("update_ink"):
		ink_bar.update_ink(current_ammo * 10.0, max_ammo * 10.0)

# 紅槍蓄力預覽
func preview_ink(preview_val: float) -> void:
	if ink_bar and ink_bar.has_method("preview_ink"):
		ink_bar.preview_ink(preview_val)
		
func confirm_ink_drop(final_val: float) -> void:
	if ink_bar and ink_bar.has_method("confirm_ink_drop"):
		ink_bar.confirm_ink_drop(final_val)

# 🌟【改動】：已完全刪除 update_sp 與 set_overheat_visual 函數。

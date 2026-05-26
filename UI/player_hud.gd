extends CanvasLayer # 讓腳本繼承自畫布層，確保 UI 永遠顯示在遊戲畫面最前面，不被角色遮擋 player_hud

# --- 抓取畫面上的節點 ---
@onready var health_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/HealthBar # 根據節點路徑，抓取紅色的血量進度條
@onready var energy_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/EnergyBar # 根據節點路徑，抓取黃色的能量進度條
@onready var sp_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/SpBar         # 根據節點路徑，抓取綠色/粉色的體力進度條
@onready var overheat_overlay: ColorRect = $OverheatOverlay # 抓取你建立的黑色全螢幕遮罩節點 (過熱視覺特效用)

# --- 更新血條長度 ---
func update_hp(current_hp: int, max_hp: int): # 自訂函數：接收目前的血量與最大血量數值
	if health_bar: # 防呆檢查：確認畫面上確實有抓到血量條節點
		health_bar.max_value = max_hp # 告訴進度條，它的最大滿值是多少
		var tween = get_tree().create_tween() # 建立一個新的 Tween 動畫效果控制器
		tween.tween_property(health_bar, "value", current_hp, 0.3) # 指示控制器，花費 0.3 秒將血條平滑地滑動到最新數值

# --- 更新能量條長度 ---
func update_energy(current_energy: int, max_energy: int): # 自訂函數：接收目前的能量與最大能量數值
	if energy_bar: # 防呆檢查：確認畫面上確實有抓到能量條節點
		energy_bar.max_value = max_energy # 告訴進度條，它的最大滿值是多少
		var tween = get_tree().create_tween() # 建立一個新的 Tween 動畫效果控制器
		tween.tween_property(energy_bar, "value", current_energy, 0.3) # 指示控制器，花費 0.3 秒將能量條平滑地滑動到最新數值

# --- 🌟 更新體力條長度 ---
func update_sp(current_sp: float, max_sp: float): # 自訂函數：接收目前的體力與最大體力數值
	if sp_bar: # 防呆檢查：確認畫面上確實有抓到體力條節點
		sp_bar.max_value = max_sp # 告訴體力進度條，它的最大滿值是多少
		sp_bar.value = current_sp # 因為體力每秒都在頻繁變動，這裡直接強制將進度條的值設定為最新體力，不使用動畫以保持畫面最流暢

# --- 🌟 改變體力條顏色與全螢幕變暗特效 ---
func set_overheat_visual(is_active: bool): # 自訂函數：接收一個布林值 (true代表觸發過熱，false代表恢復正常)
	if not sp_bar or not overheat_overlay: # 防呆檢查：如果沒抓到體力條或是遮罩節點
		return # 直接跳出函數，不做任何事情避免報錯
	
	var style_box = StyleBoxFlat.new() # 在記憶體中建立一個全新的 StyleBoxFlat 實體 (相當於拿出一個全新的調色盤)
	var tween = get_tree().create_tween() # 建立一個新的 Tween 動畫效果控制器，用來控制畫面變暗的平滑過渡
	
	if is_active: # 條件判斷：如果啟動了過熱狀態 (is_active 為 true)
		style_box.bg_color = Color.HOT_PINK # 將調色盤的背景顏色屬性設定為極度耀眼的亮粉紅色 (HOT_PINK)
		# 讓畫面變灰暗：指示動畫控制器，花費 0.3 秒，將全螢幕遮罩的透明度 (modulate:a) 平滑地過渡到 0.4 (半透明的黑色)
		tween.tween_property(overheat_overlay, "modulate:a", 0.4, 0.3) 
	else: # 條件判斷：如果解除了過熱狀態 (is_active 為 false)
		style_box.bg_color = Color.LIME_GREEN # 將調色盤的背景顏色屬性設定回正常的萊姆綠色 (LIME_GREEN)
		# 讓畫面恢復正常：指示動畫控制器，花費 0.3 秒，將全螢幕遮罩的透明度平滑地過渡回 0.0 (完全透明，看不見遮罩)
		tween.tween_property(overheat_overlay, "modulate:a", 0.0, 0.3) 
		
	sp_bar.add_theme_stylebox_override("fill", style_box) # 使用引擎指令，將我們調好顏色的調色盤，強制覆蓋掉體力條原本負責顯示進度的 "fill" 區塊顏色

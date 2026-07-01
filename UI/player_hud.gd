#playerhud
extends CanvasLayer # 繼承自畫布層，確保 UI 永遠顯示在遊戲畫面最前面，不被角色遮擋

# ==========================================
# 節點抓取 (取得畫面上的 UI 元件)
# ==========================================
@onready var health_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/HealthBar # 抓取紅色的血量進度條
@onready var energy_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/EnergyBar # 抓取黃色的能量進度條
@onready var sp_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/SpBar         # 抓取綠色的體力進度條
@onready var overheat_overlay: ColorRect = $OverheatOverlay                                   # 抓取過熱時的全螢幕黑色遮罩

# ==========================================
# [🌟 本次改動] 核心設定：血量比例尺
# ==========================================
# 定義 1 滴血等於多少像素寬度。這決定了血條伸長的速度，數字越大血條越長 (可自由微調)
var hp_pixel_ratio: float = 3.0 
var energy_pixel_ratio: float = 3.0  # 能量的專屬像素比例尺 (預設 1點能量 = 3像素)
var sp_pixel_ratio: float = 3.0      # 體力的專屬像素比例尺 (預設 1點體力 = 3像素)

# ==========================================
# 狀態更新函數
# ==========================================

# --- 更新血條 ---
func update_hp(current_hp: int, max_hp: int): # 接收目前的血量與最大血量
	if health_bar: # 確認有抓到血條節點
		health_bar.max_value = max_hp # 告訴進度條，它的最大滿值是多少
		
		# [🌟 本次改動] 讓血條物理性變長！
		# 根據「最大血量 * 比例尺」，算出最新的 UI 實體寬度，給予玩家成長回饋
		health_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio
		
		# 建立 Tween 動畫，花費 0.3 秒將血條平滑地滑動到最新血量
		var tween = get_tree().create_tween()
		tween.tween_property(health_bar, "value", current_hp, 0.3)

# ==========================================
# 狀態更新函數
# ==========================================

# --- 更新能量條 ---
func update_energy(current_energy: int, max_energy: int): # 接收目前的能量與最大能量數值
	if energy_bar: # 防呆檢查：確認畫面上確實有抓到能量條節點
		energy_bar.max_value = max_energy # 告訴進度條，它的最大滿值是多少
		
		# 🌟 [本次改動] 強制鎖死能量條的實體長度，切斷與血條的連動拉伸！
		# 透過「最大能量 * 比例尺」，計算出專屬於能量條的 UI 寬度 (例如 100 * 3.0 = 300 像素)
		# 這樣寫的好處是：如果未來能量上限也透過裝備提升，它也能像血條一樣自然變長
		energy_bar.custom_minimum_size.x = max_energy * energy_pixel_ratio 
		
		# 建立一個新的 Tween 動畫效果控制器
		var tween = get_tree().create_tween() 
		# 指示控制器，花費 0.3 秒將能量條的顯示進度平滑地滑動到最新數值
		tween.tween_property(energy_bar, "value", current_energy, 0.3) 

# --- 更新體力條 ---
func update_sp(current_sp: float, max_sp: float): # 接收目前的體力與最大體力數值
	if sp_bar: # 防呆檢查：確認畫面上確實有抓到體力條節點
		sp_bar.max_value = max_sp # 告訴體力進度條，它的最大滿值是多少
		
		# 🌟 [本次改動] 強制鎖死體力條的實體長度，維持獨立排版！
		# 透過「最大體力 * 比例尺」，計算出專屬於體力條的 UI 寬度 (例如 100 * 3.0 = 300 像素)
		sp_bar.custom_minimum_size.x = max_sp * sp_pixel_ratio 
		
		# 因為體力每秒都在頻繁變動，這裡直接強制將進度條的值設定為最新體力，不使用動畫以保持畫面最流暢
		sp_bar.value = current_sp

# ==========================================
# 視覺特效控制
# ==========================================

# --- 體力透支 (過熱) 視覺切換 ---
func set_overheat_visual(is_active: bool): # 接收布林值判斷是否過熱
	if not sp_bar or not overheat_overlay: # 防呆：若沒抓到節點則直接跳出
		return 
	
	# 建立全新的 StyleBoxFlat 實體 (相當於準備一個新調色盤)
	var style_box = StyleBoxFlat.new()
	# 建立 Tween 動畫，用來控制畫面變暗的平滑過渡
	var tween = get_tree().create_tween()
	
	if is_active: # 如果啟動了過熱狀態
		style_box.bg_color = Color.HOT_PINK # 將體力條背景設定為亮粉紅色
		# 花費 0.3 秒，將全螢幕遮罩的透明度平滑過渡到 0.4 (半透明黑)
		tween.tween_property(overheat_overlay, "modulate:a", 0.4, 0.3) 
	else: # 如果解除了過熱狀態
		style_box.bg_color = Color.LIME_GREEN # 將體力條背景設定回萊姆綠色
		# 花費 0.3 秒，將全螢幕遮罩的透明度平滑過渡回 0.0 (完全透明)
		tween.tween_property(overheat_overlay, "modulate:a", 0.0, 0.3) 
		
	# 將調好顏色的調色盤，強制覆蓋掉體力條原本負責顯示進度的 "fill" 區塊顏色
	sp_bar.add_theme_stylebox_override("fill", style_box)

extends BaseEnemy
class_name BigDango

# ==========================================
# ⚙️ Boss 專屬配置
# ==========================================
@export_category("💣 Boss 鎖血與召喚")
@export var minion_scene: PackedScene # 🌟 等一下要從右邊面板把藍色小團子拖進來！

# 記錄鎖血階段 (80%, 60%, 40%, 20%)
var hp_thresholds: Array[float] = [0.8, 0.6, 0.4, 0.2]
var current_phase_index: int = 0
var is_invincible: bool = false # 專屬無敵星星開關 (紫光時開啟)

# ==========================================
# 🛡️ 霸體機制 (覆寫老爸的受傷硬直)
# ==========================================
# 正規做法：老爸扣完血會呼叫 handle_hurt() 進入硬直狀態。
# 我們在這裡「攔截」它，並且什麼都不做 (pass)！
# 這樣大胖呆被打時依然會閃白光、噴血，但「動作絕對不會被打斷」，完美實現霸體！
func handle_hurt() -> void:
	pass

# ==========================================
# 🩸 鎖血反擊機制 (覆寫老爸的扣血邏輯)
# ==========================================
func take_damage(amount: float, attacker_pos: Vector2 = Vector2.ZERO, dir: Vector2 = Vector2.ZERO, is_melee: bool = false, extra_knockback: float = 1.0) -> void:
	
	# 1. 正在紫光無敵，或已經死了，直接把傷害沒收！
	if is_invincible or is_dead:
		return
		
	# 2. 呼叫老爸邏輯：幫忙扣血、閃光、更新血條。
	# 🌟 注意：我們把 extra_knockback 強制改成 0.0，確保霸體不會被任何技能擊退！
	super.take_damage(amount, attacker_pos, dir, is_melee, 0.0)
	
	# 3. 檢查是否跨越 20% 的鎖血線
	_check_hp_threshold()

func _check_hp_threshold() -> void:
	if current_phase_index >= hp_thresholds.size() or is_dead:
		return # 4個階段都觸發完了，就不理它
		
	var hp_ratio = float(current_hp) / float(max_hp)
	var target_threshold = hp_thresholds[current_phase_index]
	
	# 當血量掉到目標線以下時，強制觸發！
	if hp_ratio <= target_threshold:
		current_phase_index += 1 # 推進到下一階段，避免重複觸發
		
		if state_machine:
			# 🌟【技能二：溫稀哩爸爸】
			# 強制打斷大腦目前的所有動作，進入鎖血反擊狀態！
			state_machine.change_state("CounterSpawn")

# ==========================================
# 💥 自爆賴皮豬 (覆寫老爸的死亡邏輯)
# ==========================================
# 正規做法：老爸死掉會進入通用的 "Die" 狀態。
# 我們攔截下來，讓牠進入大胖呆專屬的 "BossDie" 狀態來執行自爆預警！
func die() -> void:
	if is_dead: return
	is_dead = true
	
	if state_machine:
		state_machine.change_state("BossDie")
		
	drop_coin()

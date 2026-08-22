extends State                    # 繼承自狀態模板 base_hurt

# 🌟 新增這行：讓受傷結束後，可以自訂要切換去哪個狀態 (預設是 Chase 照顧野豬)
@export var aggro_state: String = "Chase"


var hurt_timer: float = 0.4      # 受傷硬直計時器：預設被打退 0.4 秒

func enter():                    # 進入受傷狀態時執行
	hurt_timer = 0.4             # 重置受傷時間
	character.can_attack = false # 被打飛時沒收攻擊權力
	character.play_animation("hurt") # 播放受傷挨打的動畫

func state_physics_update(delta: float): # 每一幀物理更新
	hurt_timer -= delta          # 扣除受傷時間

	# 🌟【關鍵修復】刪除了寫死的 lerp(0.15) 摩擦力與 velocity 覆蓋！
	# 現在野豬受傷時的滑行與煞車，會 100% 依照你在 KnockbackComponent 裡的設定運作。

	if hurt_timer <= 0:          # 如果 0.4 秒硬直結束
		if character.current_hp > 0: # 如果野豬還活著
			character.can_attack = true # 恢復攻擊權力

			if character.player_node:   
				# 🌟【新增判斷】檢查這隻怪是不是野蠻人，而且是不是已經狂暴了？
				if "is_berserk" in character and character.is_berserk:
					state_machine.change_state("BerserkCharge") # 狂暴後被打，繼續起來衝撞！
				else:
					state_machine.change_state(aggro_state) # 沒狂暴，或是其他怪，照舊切換回預設狀態 (Chase)
			else:                       
				state_machine.change_state("Move")

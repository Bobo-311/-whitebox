extends State                    # 繼承自狀態模板 base_hurt

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

			if character.player_node:   # 如果視野內還有玩家
				state_machine.change_state("Chase")  # 進入追擊狀態
			else:                       # 如果玩家不見了
				state_machine.change_state("Move") # 進入隨機漫遊狀態

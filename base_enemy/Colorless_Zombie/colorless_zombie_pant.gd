extends State

@export var rest_time: float = 2.0 # 在面板上可以調整的休息秒數
var pant_timer: float = 0.0

func enter():
	pant_timer = rest_time
	character.velocity = Vector2.ZERO # 確保原地不動
	character.play_animation("idle")  # 播放待機/喘氣動畫
	
	# 買個保險：發呆時絕對不能有傷害
	if character.hitbox:
		character.hitbox.set_deferred("monitoring", false)
	
	# 裝監視器：看看他有沒有成功進入這個狀態？
	print("【休息腳本】成功進入 Pant 狀態！準備發呆 ", rest_time, " 秒")

func state_physics_update(delta: float):
	pant_timer -= delta
	
	if pant_timer <= 0:
		# 休息結束，確認是否還有看到玩家，決定要追還是要巡邏
		if character.player_node and character.can_see_player:
			state_machine.change_state("Chase")
		else:
			state_machine.change_state("Move")

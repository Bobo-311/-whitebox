extends State

# ==========================================
# ⚙️ 二階狂暴數值設定 (面板可調)
# ==========================================
@export_category("二階狂暴數值")
@export var berserk_speed: float = 300.0   
@export var berserk_damage: float = 75.0   

var transition_timer: float = 2.0 # 變身發呆時間 (秒)

func enter():
	transition_timer = 2.0
	character.velocity = Vector2.ZERO 
	character.play_animation("idle", character.last_facing_vec)
	
	# 🆕 【強制變色】直接將精靈圖 modulate 設為純紅，且不使用 Tween 避免被其他特效蓋掉
	character.animated_sprite_2d.modulate = Color(1.0, 0.0, 0.0, 1.0)

func state_physics_update(delta: float):
	transition_timer -= delta
	
	# 時間到，切換到瘋狗衝刺狀態
	if transition_timer <= 0:
		state_machine.change_state("BerserkCharge")

func exit():
	# 變身結束，將數值正式更新到角色身上
	character.walk_speed = berserk_speed
	character.melee_damage = berserk_damage

extends State

# -------------------------------------------------------------------------
# ⚙️ 序列化設定面板 (企劃專用參數，可在 Inspector 自由調整)
# -------------------------------------------------------------------------
@export_group("遠程開火設定")
@export var projectile_scene: PackedScene # 彈藥庫：裝填暗影迴旋球的場景
@export var fire_frame: int = 4           # 觸發點：動畫播到第幾幀時吐出球

# -------------------------------------------------------------------------
# 🔒 狀態內部的暫存變數與防呆鎖
# -------------------------------------------------------------------------
var has_fired: bool = false               # 防呆：確保一次攻擊只會射出發一顆球
var has_finished_attack: bool = false     # 防呆：確保動作完全播完才允許切換狀態
var locked_target_pos: Vector2 = Vector2.ZERO # 記憶體：玩家最後已知座標 (盲射用)

# -------------------------------------------------------------------------
# 🎬 進入狀態 (當大腦切換到 Attack 時瞬間執行)
# -------------------------------------------------------------------------
func enter():
	character.velocity = Vector2.ZERO # 預期動作：開火前強制罰站，不能滑步
	has_fired = false
	has_finished_attack = false
	
	# 公平性：關閉近戰碰撞框，防止貼臉誤傷
	if character.hitbox:
		character.hitbox.set_deferred("monitoring", false)
	
	# 攻擊承諾：鎖定當下玩家位置並計算轉向，防止背向攻擊
	if character.player_node:
		locked_target_pos = character.player_node.global_position + Vector2(0, -30)
		character.last_facing_vec = (locked_target_pos - character.global_position).normalized()
	
	# 播放對應方向的攻擊動畫
	character.play_animation("attack", character.last_facing_vec)

# -------------------------------------------------------------------------
# 🔄 物理更新迴圈 (每秒 60 次，嚴密監控動畫影格進度)
# -------------------------------------------------------------------------
func state_physics_update(_delta: float):
	var anim = character.animated_sprite_2d
	
	if "attack" in anim.animation:
		var current_frame = anim.frame
		
		# 動畫影格判定：使用 >= 防止高速移動時發生漏幀
		if current_frame >= fire_frame and not has_fired:
			_fire_projectile()
			has_fired = true
			
		# 收招判定：確認動畫播到最後一幀後，切換到喘息狀態
		var max_frame = anim.sprite_frames.get_frame_count(anim.animation) - 1
		if current_frame == max_frame and not has_finished_attack:
			has_finished_attack = true
			state_machine.change_state("Pant") 

# -------------------------------------------------------------------------
# 🚀 實體化與發射邏輯 (建立迴旋鏢的核心)
# -------------------------------------------------------------------------
func _fire_projectile():
	if not projectile_scene: return
	
	# 尋找槍口位置 (若無則退回怪物中心)
	var muzzle = character.get_node_or_null("AimPivot/Muzzle")
	var start_pos = muzzle.global_position if muzzle else character.global_position
	
	# 盲射機制：強制朝著記憶中的座標發射 (玩家跑走也不影響)
	var target_pos = locked_target_pos 
	
	# 實體化子彈並交由世界場景託管 (避免跟隨怪物本體移動)
	var bullet = projectile_scene.instantiate()
	character.get_parent().add_child(bullet)
	
	# 呼叫子彈內建的飛行函數
	if bullet.has_method("fire"):
		bullet.fire(start_pos, target_pos)

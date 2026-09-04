extends State

# --- 開放面板調整，方便企劃隨時修改數值 ---
@export_category("🛡️ 鎖血召喚設定")

@export_group("時間與機制")
@export var invincible_duration: float = 0.5    # 無敵與發呆維持幾秒
@export var flash_color: Color = Color(0.6, 0.0, 0.8, 1.0) # 發光顏色 (預設紫光)

@export_group("召喚物設定")
@export var minion_spawn_count: int = 2         # 一次吐幾隻小怪
@export var minion_spit_force: float = 300.0    # 小怪噴飛的力道

@export_group("視覺衝擊")
@export var screen_shake_intensity: float = 15.0 # 震動螢幕的強度

var state_timer: float = 0.0 # 內部倒數計時器

func enter():
	state_timer = invincible_duration
	
	character.velocity = Vector2.ZERO # 1. 煞車停下
	character.is_invincible = true    # 2. 開啟無敵，免疫傷害
	
	_play_custom_flash()              # 3. 播放變色閃光
	
	# 4. 呼叫震屏
	var camera = character.get_tree().get_first_node_in_group("camera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(screen_shake_intensity)
		
	_spawn_minions(minion_spawn_count) # 5. 吐出小怪

func state_physics_update(delta: float):
	state_timer -= delta
	
	if state_timer <= 0:
		# 🌟 0.5 秒無敵結束後，重新開始拉開距離！
		state_machine.change_state("BossKiting")


# --- 內部功能函數 ---

func _play_custom_flash():
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if not mat: return
	
	var tween = create_tween()
	# 瞬間變色，接著慢慢褪色回純白
	tween.tween_property(mat, "shader_parameter/state_color", flash_color, 0.1)
	tween.tween_property(mat, "shader_parameter/state_color", Color.WHITE, invincible_duration - 0.1)

func _spawn_minions(count: int):
	if not character.minion_scene: return 
	
	for i in range(count):
		var minion = character.minion_scene.instantiate()
		var random_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		
		# 把小怪生在世界上
		# ✅ 正規寫法 (排隊延遲加入)
		character.get_parent().call_deferred("add_child", minion)
		minion.global_position = character.global_position + (random_dir * 30.0)
		
		# 給予噴飛的物理力道
		if "velocity" in minion:
			minion.velocity = random_dir * minion_spit_force


func exit():
	character.is_invincible = false # 離開時務必關閉無敵
	
	# 強制把顏色調回純白，避免卡在紫光
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("state_color", Color.WHITE) 

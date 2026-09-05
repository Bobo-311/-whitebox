extends State

# --- 開放面板調整，方便企劃隨時修改數值 ---
@export_category("🛡️ 鎖血召喚設定")

@export_group("時間與機制")
@export var invincible_duration: float = 1.5    # 🌟 修改：無敵總時長。因為你要等 1 秒才吐，無敵必須大於 1 秒
@export var spawn_delay: float = 1.0            # 🌟 新增：發呆幾秒後才把小怪吐出來？
@export var flash_color: Color = Color(0.6, 0.0, 0.8, 1.0) # 發光顏色

@export_group("召喚物設定")
@export var minion_spawn_count: int = 2         # 一次吐幾隻
@export var minion_spit_force: float = 300.0    # 噴飛力道

@export_group("視覺衝擊")
@export var screen_shake_intensity: float = 15.0 # 震屏強度

var state_timer: float = 0.0  # 內部計時器
var has_spawned: bool = false # 🌟 狀態標記：記錄這回合是不是已經吐過了

func enter():
	state_timer = 0.0   # 🌟 為了方便算「第幾秒吐」，計時器改從 0 開始往上加
	has_spawned = false # 進來時重置吐怪狀態
	
	character.velocity = Vector2.ZERO # 1. 煞車停好
	character.is_invincible = true    # 2. 開啟無敵
	
	_play_custom_flash()              # 3. 播紫光
	
func state_physics_update(delta: float):
	state_timer += delta # 時間每一幀往上加
	
	# 🌟 核心邏輯 1：時間到了設定的「延遲秒數 (1.0)」，且還沒吐過，就吐怪！
	if state_timer >= spawn_delay and not has_spawned:
		_spawn_minions(minion_spawn_count)
		has_spawned = true # 標記吐過了，避免瘋狂狂吐
		
		# 吐怪瞬間呼叫震屏，這樣才有「用力噴出來」的感覺
		var camera = character.get_tree().get_first_node_in_group("camera")
		if camera and camera.has_method("apply_shake"):
			camera.apply_shake(screen_shake_intensity)
	
	# 🌟 核心邏輯 2：總時間到了設定的「無敵時間 (1.5)」，結束狀態
	if state_timer >= invincible_duration:
		state_machine.change_state("move") # 🌟 切回小寫的 move，繼續風箏

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
		
		# ✅ 正規延遲加入，避免物理碰撞報錯
		character.get_parent().call_deferred("add_child", minion)
		minion.global_position = character.global_position + (random_dir * 30.0)
		
		if "velocity" in minion:
			minion.velocity = random_dir * minion_spit_force

func exit():
	character.is_invincible = false # 離開務必關閉無敵
	
	var mat = character.animated_sprite_2d.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("state_color", Color.WHITE)

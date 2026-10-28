# --- portal_area.gd (掛在隱形傳送門 Area2D 上) ---
extends Area2D

@export_category("🚪 跨地圖傳送門設定")
@export_file("*.tscn") var target_scene_path: String # 點擊即可直接從資料夾選擇要去的地圖 (如 AM002.tscn)
@export var target_spawn_name: String = "From_Map1"  # 填寫去對面地圖時，要站在哪根 Marker2D 定位針上

# 🌟【過圖後的玩家面向設定】
# 預設為 0 (自動偵測玩家踏入傳送門時的移動方向)，你也可以在右側面板手動強制指定方向！
@export_enum("自動依進入方向 (Auto):0", "面向右 (Right):1", "面向左 (Left):2", "面向上 (Up):3", "面向下 (Down):4") 
var exit_facing: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# 確認走進來的是玩家本人
	if body.is_in_group("player") or body.name == "player":
		if target_scene_path.is_empty():
			push_warning("⚠️ 傳送門尚未設定目標地圖路徑！")
			return
			
		# 🌟 1. 計算玩家去到下一張地圖時應該面向哪個方向向量
		var facing_dir: Vector2 = _get_target_facing_dir(body)
		
		# 🌟 2. 呼叫全域轉場總管，把「地圖路徑」、「定位針名稱」與「目標面向」一起傳過去！
		SceneTransition.change_map(target_scene_path, target_spawn_name, facing_dir)
# ==========================================
# 🧭 輔助計算：決定過圖後的面向向量
# ==========================================
func _get_target_facing_dir(player_body: Node2D) -> Vector2:
	match exit_facing:
		1: return Vector2.RIGHT # 面板強制設定：面向右 (例如 2 走到 3)
		2: return Vector2.LEFT  # 面板強制設定：面向左 (例如 3 走回 2)
		3: return Vector2.UP    # 面板強制設定：面向上
		4: return Vector2.DOWN  # 面板強制設定：面向下
		_:
			# 🌟【自動偵測模式 1】：優先讀取玩家踏入傳送門瞬間的移動速度 (velocity)
			if player_body is CharacterBody2D and player_body.velocity != Vector2.ZERO:
				var vel = player_body.velocity
				if abs(vel.x) >= abs(vel.y):
					return Vector2.RIGHT if vel.x > 0 else Vector2.LEFT
				else:
					return Vector2.DOWN if vel.y > 0 else Vector2.UP
					
			# 🌟【自動偵測模式 2 (防呆保底)】：如果碰到門瞬間剛好放開按鍵 (速度為 0)，
			# 直接讀取阿尼 player.gd 肚子裡的 facing_direction 字串！
			if "facing_direction" in player_body:
				match player_body.facing_direction:
					"right": return Vector2.RIGHT
					"left":  return Vector2.LEFT
					"up":    return Vector2.UP
					"down":  return Vector2.DOWN
					
			return Vector2.DOWN

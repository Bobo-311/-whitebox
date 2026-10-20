# --- portal_area.gd (掛在隱形傳送門 Area2D 上) ---
extends Area2D

@export_category("🚪 跨地圖傳送門設定")
@export_file("*.tscn") var target_scene_path: String # 點擊即可直接從資料夾選擇要去的地圖 (如 AM002.tscn)
@export var target_spawn_name: String = "From_Map1"  # 填寫去對面地圖時，要站在哪根 Marker2D 定位針上

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# 確認走進來的是玩家本人
	if body.is_in_group("player") or body.name == "player":
		if target_scene_path.is_empty():
			push_warning("⚠️ 傳送門尚未設定目標地圖路徑！")
			return
			
		# 呼叫全域轉場總管，開始黑幕轉場！
		SceneTransition.change_map(target_scene_path, target_spawn_name)

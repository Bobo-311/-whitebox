# 掛在原有的 SceneTransition Autoload 場景上。
extends CanvasLayer

## 入口沒有另外放 CatSpawn 時，白貓與阿尼之間的距離（世界座標單位）。
@export_range(0.0, 512.0, 1.0, "or_greater") var cat_spawn_distance: float = 64.0

@onready var black_screen: ColorRect = $BlackScreen
var is_transitioning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	black_screen.modulate.a = 0.0

func change_map(target_scene_path: String, target_spawn_name: String, target_facing_dir: Vector2 = Vector2.ZERO) -> void:
	if is_transitioning:
		return
	is_transitioning = true

	# 只記錄這趟有沒有同行的白貓；舊地圖的節點會隨場景卸載。
	var cat_was_present := _find_map_cat(get_tree().current_scene) != null

	# 背景讀圖，同時讓黑幕淡入。
	var request_status := ResourceLoader.load_threaded_request(target_scene_path)
	var tween_in = create_tween()
	tween_in.tween_property(black_screen, "modulate:a", 1.0, 0.35)
	await tween_in.finished

	var new_scene_packed: PackedScene = null
	if request_status == OK or request_status == ERR_BUSY:
		while ResourceLoader.load_threaded_get_status(target_scene_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(target_scene_path) == ResourceLoader.THREAD_LOAD_LOADED:
			new_scene_packed = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
	await get_tree().create_timer(0.15).timeout

	# 金幣動畫接力：保留離開舊地圖時的動畫幀與進度。
	var saved_frame: int = 0
	var saved_progress: float = 0.0
	var old_coin = get_tree().root.find_child("CoinSprite", true, false) as AnimatedSprite2D
	if old_coin:
		saved_frame = old_coin.frame
		saved_progress = old_coin.frame_progress

	var change_result: Error
	if new_scene_packed:
		change_result = get_tree().change_scene_to_packed(new_scene_packed)
	else:
		change_result = get_tree().change_scene_to_file(target_scene_path)

	if change_result == OK:
		# 新玩家已經跑過 _ready()，白貓也已加入 white_cat 群組。
		await get_tree().scene_changed
		var new_coin = get_tree().root.find_child("CoinSprite", true, false) as AnimatedSprite2D
		if new_coin:
			new_coin.play("spin")
			new_coin.set_frame_and_progress(saved_frame, saved_progress)
		_move_player_to_spawn(target_spawn_name, target_facing_dir, cat_was_present)
	else:
		push_warning("【傳送門】無法切換地圖：%s（%s）" % [target_scene_path, error_string(change_result)])

	# 玩家和白貓完成定位以後才拉開黑幕。
	var tween_out = create_tween()
	tween_out.tween_property(black_screen, "modulate:a", 0.0, 0.35)
	await tween_out.finished
	is_transitioning = false

func _move_player_to_spawn(spawn_name: String, facing_dir: Vector2, cat_was_present: bool = false) -> void:
	var current_map := get_tree().current_scene
	if not current_map:
		return

	var player: Node2D = null
	if is_instance_valid(DataManager.player_node) and current_map.is_ancestor_of(DataManager.player_node):
		player = DataManager.player_node
	else:
		for node in get_tree().get_nodes_in_group("player"):
			if node is Node2D and current_map.is_ancestor_of(node):
				player = node
				break
	if not player:
		push_warning("【傳送門】新地圖找不到玩家：" + current_map.name)
		return

	if not spawn_name.is_empty():
		var spawn_point := current_map.find_child(spawn_name, true, false) as Node2D
		if spawn_point:
			player.global_position = spawn_point.global_position
			player.reset_physics_interpolation()
			if cat_was_present:
				var cat := _find_map_cat(current_map)
				if cat:
					_place_cat_at_entrance(cat, player, spawn_point, facing_dir)
		else:
			push_warning("【傳送門】%s 找不到入口 %s" % [current_map.name, spawn_name])

	if facing_dir != Vector2.ZERO and player.has_method("set_facing_direction"):
		player.call("set_facing_direction", facing_dir)
	var camera = get_tree().get_first_node_in_group("camera") as Camera2D
	if camera:
		camera.reset_smoothing()

func _find_map_cat(map_root: Node) -> WhiteCat:
	if not map_root:
		return null
	for node in get_tree().get_nodes_in_group("white_cat"):
		var cat := node as WhiteCat
		if not cat or not map_root.is_ancestor_of(cat) or cat.is_queued_for_deletion():
			continue
		if cat.is_visible_in_tree() and cat.process_mode != Node.PROCESS_MODE_DISABLED:
			return cat
	return null

func _place_cat_at_entrance(cat: WhiteCat, player: Node2D, entrance: Node2D, facing_dir: Vector2) -> void:
	cat.player_node = player
	if player is PhysicsBody2D:
		cat.add_collision_exception_with(player)
		player.add_collision_exception_with(cat)

	# 狹窄或不規則的入口，可在玩家 Marker 下放一個名為 CatSpawn 的 Marker2D。
	var cat_marker := entrance.get_node_or_null("CatSpawn") as Marker2D
	if cat_marker:
		cat.global_position = cat_marker.global_position
	else:
		cat.global_position = _cat_position_beside_player(cat, player.global_position, facing_dir)

	cat.velocity = Vector2.ZERO
	cat.is_recalling = false
	cat.nav_agent.target_position = cat.global_position
	cat.reset_physics_interpolation()
	if not cat.is_stunned:
		cat.play_animation("idle", facing_dir)

func _cat_position_beside_player(cat: WhiteCat, arrival: Vector2, facing_dir: Vector2) -> Vector2:
	# 水平門先試下方，上下門先試右方；沿著入口邊緣站，避免直接退回門外。
	var side := Vector2.DOWN if absf(facing_dir.x) > absf(facing_dir.y) else Vector2.RIGHT
	var start := cat.global_transform
	start.origin = arrival
	var directions: Array[Vector2] = [side, -side, facing_dir.normalized()]
	for direction in directions:
		var step := direction * cat_spawn_distance
		if not cat.test_move(start, step):
			return arrival + step
	# 周圍都被擋時共用玩家落點。白貓與玩家有雙向碰撞例外。
	return arrival

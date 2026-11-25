extends Node2D

# ============================================================
# 《眠境 RE:RECOLOR》
# Volcano V2｜火山地圖初始化管理
#
# Godot：4.5.1
# Dialogic：2.0-Alpha-21
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 初始化火山地圖名稱
# 2. 處理原有畫架傳送降落
# 3. 播放原有 opening 開場劇情
# 4. 劇情期間鎖定玩家操作
# 5. 相容一般對話及頭頂氣泡排版
# 6. 劇情結束後恢復玩家控制
# 7. 防止節點不存在造成執行錯誤
# 8. 防止重複啟動劇情
#
# ============================================================
# 不負責
# ============================================================
#
# - 正式存檔資料讀寫
# - 永久劇情進度保存
# - 畫架解鎖
# - 玩家死亡重生
# - 跨場景黑幕動畫
#
# 本次僅修正火山地圖原有功能。
# 不影響其他地圖及共用 CutsceneDirector。
# ============================================================


# ============================================================
# 1. 地圖與劇情設定
# ============================================================

@export_group("劇情設定")

## 是否播放火山原有的開場劇情
@export var play_opening: bool = true

## 原有 Dialogic 劇本名稱
@export var opening_timeline: String = "opening"

## 指定開場使用的 Dialogic Style
##
## 留空：沿用目前的 Dialogic 排版機制。
## 若需要頭頂氣泡，可填入已建立的氣泡 Style 名稱。
##
## 不修改 Dialogic 全域預設 Style。
@export var opening_style: String = ""


# ============================================================
# 2. 除錯設定
# ============================================================

@export_group("除錯設定")

## 是否顯示地圖初始化及劇情紀錄
@export var debug_log: bool = true


# ============================================================
# 3. 角色資源及節點
# ============================================================

## 阿尼的 Dialogic 角色資源路徑
const ANI_CHARACTER_PATH: String = (
	"res://dialogic/character/阿尼.dch"
)

## 保留原有畫架傳送降落點
@onready var spawn_point: Marker2D = (
	get_node_or_null("PortalSpawnPoint") as Marker2D
)


# ============================================================
# 4. 內部劇情狀態
# ============================================================

## 本地圖是否正在播放開場劇情
var _opening_active: bool = false

## 紀錄本次劇情所控制的玩家
var _opening_player: Node2D = null

## 紀錄劇情開始前的狀態機處理模式
var _previous_process_mode: int = (
	Node.PROCESS_MODE_INHERIT
)


# ============================================================
# 5. 地圖初始化
# ============================================================

func _ready() -> void:

	# --------------------------------------------------------
	# A. 更新目前地圖名稱
	# --------------------------------------------------------

	DataManager.update_map_name("火山")

	# --------------------------------------------------------
	# B. 處理原有畫架快速傳送
	#
	# 透過畫架傳送抵達時，不播放開場劇情。
	# --------------------------------------------------------

	if DataManager.is_teleporting:

		_apply_portal_arrival()

		return

	# --------------------------------------------------------
	# C. 檢查是否允許播放開場
	# --------------------------------------------------------

	if not play_opening:
		return

	# --------------------------------------------------------
	# D. 等待既有跨場景轉場結束
	#
	# 避免黑幕仍在執行時就啟動 Dialogic。
	#
	# 直接 F6 測試火山時，不需要等待轉場訊號。
	# --------------------------------------------------------

	if SceneTransition.is_transitioning:

		await SceneTransition.transition_settled

	else:

		await get_tree().process_frame

	# 確認地圖仍然存在
	if not is_inside_tree():
		return

	# --------------------------------------------------------
	# E. 播放開場劇情
	# --------------------------------------------------------

	_start_opening()


# ============================================================
# 6. 尋找目前地圖的玩家
#
# 避免使用上一張地圖已經卸載的玩家節點。
# ============================================================

func _get_current_player() -> Node2D:

	var player: Node2D = DataManager.player_node

	if is_instance_valid(player):

		if is_ancestor_of(player):
			return player

	# 備用：透過 player 群組尋找
	for node in get_tree().get_nodes_in_group("player"):

		if node is Node2D and is_ancestor_of(node):

			return node as Node2D

	# 相容原有 player 節點名稱
	return find_child(
		"player",
		true,
		false
	) as Node2D


# ============================================================
# 7. 畫架傳送降落
#
# 保留舊有的 PortalSpawnPoint 機制。
# 不接入尚未完成的正式畫架存檔系統。
# ============================================================

func _apply_portal_arrival() -> void:

	var player: Node2D = _get_current_player()

	if not is_instance_valid(player):

		push_warning(
			"【Volcano】找不到玩家，無法完成傳送定位"
		)

		return

	if not is_instance_valid(spawn_point):

		push_warning(
			"【Volcano】找不到 PortalSpawnPoint"
		)

		return

	# 更新全域玩家引用
	DataManager.player_node = player

	# 將玩家移動至原本的降落點
	player.global_position = spawn_point.global_position

	# 防止物理插值造成瞬間拖影
	player.reset_physics_interpolation()

	# 清除傳送前的移動速度
	if player is CharacterBody2D:

		var body := player as CharacterBody2D

		body.velocity = Vector2.ZERO

	# 重設相機平滑位置
	var camera: Camera2D = (
		get_viewport().get_camera_2d()
	)

	if is_instance_valid(camera):

		camera.reset_smoothing()

		camera.force_update_scroll()

	# 完成傳送後關閉旗標
	DataManager.is_teleporting = false

	_log("畫架傳送定位完成")


# ============================================================
# 8. 播放火山開場劇情
# ============================================================

func _start_opening() -> void:

	# 防止重複播放
	if _opening_active:
		return

	# 不干擾其他正在播放的劇情
	if Dialogic.current_timeline != null:

		push_warning(
			"【Volcano】已有劇情正在播放，略過火山開場"
		)

		return

	# 檢查劇本是否存在
	if not Dialogic.timeline_exists(opening_timeline):

		push_warning(
			"【Volcano】找不到開場劇本："
			+ opening_timeline
		)

		return

	# 檢查玩家
	var player: Node2D = _get_current_player()

	if not is_instance_valid(player):

		push_warning(
			"【Volcano】找不到玩家，取消開場劇情"
		)

		return

	DataManager.player_node = player

	# --------------------------------------------------------
	# A. 選擇開場排版
	#
	# 只有 Inspector 有填寫 Style 時才指定。
	# 不強制其他地圖使用火山的排版。
	# --------------------------------------------------------

	if not opening_style.strip_edges().is_empty():

		Dialogic.Styles.load_style(
			opening_style
		)

	# --------------------------------------------------------
	# B. 鎖定玩家操作
	# --------------------------------------------------------

	_opening_active = true

	_opening_player = player

	_lock_player(player)

	# --------------------------------------------------------
	# C. 監聽劇情結束
	#
	# 使用 CONNECT_ONE_SHOT。
	# 本次劇情結束後自動解除訊號連接，
	# 避免干擾之後其他地圖的劇情。
	# --------------------------------------------------------

	if not Dialogic.timeline_ended.is_connected(
		_on_dialogic_ended
	):

		Dialogic.timeline_ended.connect(
			_on_dialogic_ended,
			CONNECT_ONE_SHOT
		)

	# --------------------------------------------------------
	# D. 正式播放劇本
	# --------------------------------------------------------

	var layout: Node = Dialogic.start(
		opening_timeline
	)

	if not is_instance_valid(layout):

		push_warning(
			"【Volcano】無法取得 Dialogic Layout"
		)

		if Dialogic.current_timeline == null:

			_on_dialogic_ended()

		return

	# --------------------------------------------------------
	# E. 嘗試綁定頭頂氣泡
	#
	# 本次修正的核心。
	#
	# 只有目前 Layout 支援 register_character()
	# 才執行角色氣泡綁定。
	#
	# 一般立繪或普通對話排版沒有此函式，
	# 因此安全略過，不中斷劇情。
	# --------------------------------------------------------

	_register_character_bubble(
		layout,
		player
	)

	_log("開場劇情已啟動：" + opening_timeline)


# ============================================================
# 9. 安全綁定阿尼的對話氣泡
# ============================================================

func _register_character_bubble(
	layout: Node,
	player: Node2D
) -> void:

	if not is_instance_valid(layout):
		return

	if not is_instance_valid(player):
		return

	# --------------------------------------------------------
	# A. 確認 Layout 是否支援氣泡註冊
	#
	# 原本程式缺少此項檢查，
	# 導致 default_layout_base.gd 發生執行錯誤。
	# --------------------------------------------------------

	if not layout.has_method("register_character"):

		_log(
			"目前 Layout 不支援頭頂氣泡註冊，"
			+ "沿用一般對話排版"
		)

		return

	# --------------------------------------------------------
	# B. 確認玩家有 BubbleMaker 節點
	# --------------------------------------------------------

	var bubble_marker: Node = (
		player.get_node_or_null("BubbleMaker")
	)

	if not is_instance_valid(bubble_marker):

		push_warning(
			"【Volcano】玩家缺少 BubbleMaker，略過氣泡綁定"
		)

		return

	# --------------------------------------------------------
	# C. 確認角色資源存在
	# --------------------------------------------------------

	if not ResourceLoader.exists(ANI_CHARACTER_PATH):

		push_warning(
			"【Volcano】找不到阿尼的 Dialogic 角色資源"
		)

		return

	var ani_character: Resource = load(
		ANI_CHARACTER_PATH
	)

	if ani_character == null:

		push_warning(
			"【Volcano】阿尼角色資源載入失敗"
		)

		return

	# --------------------------------------------------------
	# D. 正式註冊角色氣泡
	# --------------------------------------------------------

	layout.call(
		"register_character",
		ani_character,
		bubble_marker
	)

	_log("阿尼頭頂對話氣泡綁定完成")


# ============================================================
# 10. 劇情期間鎖定玩家
#
# 沿用原有 Player 的：
# - is_in_dialogue
# - state_machine
# - animated_sprite_2d
#
# 不修改 Player 腳本。
# ============================================================

func _lock_player(player: Node2D) -> void:

	if not is_instance_valid(player):
		return

	if "is_in_dialogue" in player:

		player.set(
			"is_in_dialogue",
			true
		)

	# 停止玩家目前的移動
	if player is CharacterBody2D:

		var body := player as CharacterBody2D

		body.velocity = Vector2.ZERO

	# 暫停玩家狀態機
	if "state_machine" in player:

		var machine: Node = (
			player.get("state_machine") as Node
		)

		if is_instance_valid(machine):

			_previous_process_mode = machine.process_mode

			machine.process_mode = (
				Node.PROCESS_MODE_DISABLED
			)

	# 保留原有面向下方的待機動畫
	_play_player_idle(player)

	_log("劇情開始，玩家操作已鎖定")


# ============================================================
# 11. 劇情結束，恢復玩家控制
# ============================================================

func _on_dialogic_ended() -> void:

	if not _opening_active:
		return

	_opening_active = false

	# 若因開場失敗而手動執行本函式，
	# 也必須解除原本的訊號連接。
	if Dialogic.timeline_ended.is_connected(
		_on_dialogic_ended
	):

		Dialogic.timeline_ended.disconnect(
			_on_dialogic_ended
		)

	var player: Node2D = _opening_player

	_opening_player = null

	if not is_instance_valid(player):
		return

	# 解除劇情操作鎖
	if "is_in_dialogue" in player:

		player.set(
			"is_in_dialogue",
			false
		)

	# 恢復玩家原本的狀態機處理模式
	if "state_machine" in player:

		var machine: Node = (
			player.get("state_machine") as Node
		)

		if is_instance_valid(machine):

			machine.process_mode = (
				_previous_process_mode
			)

	# 恢復待機動畫
	_play_player_idle(player)

	_log("對話徹底結束，狀態機已恢復，玩家可自由操作")


# ============================================================
# 12. 安全播放玩家待機動畫
#
# 避免動畫節點或指定動畫不存在時出現錯誤。
# ============================================================

func _play_player_idle(player: Node2D) -> void:

	if not is_instance_valid(player):
		return

	if not ("animated_sprite_2d" in player):
		return

	var sprite: AnimatedSprite2D = (
		player.get("animated_sprite_2d")
		as AnimatedSprite2D
	)

	if not is_instance_valid(sprite):
		return

	if sprite.sprite_frames == null:
		return

	if sprite.sprite_frames.has_animation("idle_down"):

		sprite.play("idle_down")


# ============================================================
# 13. 統一除錯輸出
# ============================================================

func _log(message: String) -> void:

	if debug_log:

		print(
			"【Volcano】" + message
		)
